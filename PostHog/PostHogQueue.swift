//
//  PostHogQueue.swift
//  PostHog
//
//  Created by Ben White on 06.02.23.
//

import Foundation

/// HTTP status codes that trigger an exponential-backoff retry. Matches
/// posthog-android's `RETRYABLE_STATUS_CODES` exactly.
private let retriableStatusCodes: Set<Int> = [429, 500, 502, 503, 504]

/// Clamps `value` to a minimum of 1. Used wherever we initialise / halve
/// the adaptive batch limits so we never store a value below 1.
private func clamped(_ value: Int) -> Int {
    max(1, value)
}

/// Adaptive limits for the events queue. Both `cap` and `flushAt` are halved
/// together on HTTP 413 and stay reduced for the SDK's lifetime — matching
/// posthog-android. Stored privately rather than mutating
/// `config.maxBatchSize` / `config.flushAt` so user-supplied config fields
/// aren't silently changed.
private struct BatchLimits {
    var cap: Int
    var flushAt: Int

    static func initial(from config: PostHogConfig) -> BatchLimits {
        BatchLimits(cap: clamped(config.maxBatchSize), flushAt: clamped(config.flushAt))
    }

    /// Halves both `cap` and `flushAt`, returning the new cap. `actualBatchSize`
    /// (the number of events actually sent) bounds the halving so a 413 with
    /// a partial batch — queue depth was below `cap` — doesn't waste halvings
    /// on a cap that wasn't reached anyway. Mirrors posthog-js-lite's
    /// behaviour; posthog-android halves from `config.maxBatchSize` directly.
    @discardableResult
    mutating func halve(actualBatchSize: Int) -> Int {
        cap = clamped(min(cap, actualBatchSize) / 2)
        flushAt = clamped(flushAt / 2)
        return cap
    }
}

/**
 # Queue

 The queue uses File persistence. This allows us to
 1. Only send events when we have a network connection
 2. Ensure that we can survive app closing or offline situations
 3. Not hold too much in memory

 */

class PostHogQueue {
    enum PostHogApiEndpoint: Int {
        case batch
        case snapshot
    }

    private let config: PostHogConfig
    private let api: PostHogApi
    private var paused: Bool = false
    private let pausedLock = NSLock()
    private var pausedUntil: Date?
    private var retryCount: TimeInterval = 0
    #if !os(watchOS)
        private let reachability: Reachability?
        private var reachableToken: RegistrationToken?
        private var unreachableToken: RegistrationToken?
    #endif

    private var isFlushing = false
    private let isFlushingLock = NSLock()
    private var timer: Timer?
    private let timerLock = NSLock()
    private let endpoint: PostHogApiEndpoint
    private let dispatchQueue: DispatchQueue

    private var batchLimits: BatchLimits
    private let batchLimitsLock = NSLock()

    /// Internal, used for testing
    var depth: Int {
        fileQueue.depth
    }

    let fileQueue: PostHogFileBackedQueue

    #if !os(watchOS)
        init(_ config: PostHogConfig, _ storage: PostHogStorage, _ api: PostHogApi, _ endpoint: PostHogApiEndpoint, _ reachability: Reachability?) {
            self.config = config
            self.api = api
            self.reachability = reachability
            self.endpoint = endpoint
            batchLimits = .initial(from: config)

            switch endpoint {
            case .batch:
                fileQueue = PostHogFileBackedQueue(queue: storage.url(forKey: .queue), oldQueues: [storage.url(forKey: .oldQueueFolder), storage.url(forKey: .oldQueuePlist)])
                dispatchQueue = DispatchQueue(label: "com.posthog.Queue", target: .global(qos: .utility))
            case .snapshot:
                fileQueue = PostHogFileBackedQueue(queue: storage.url(forKey: .replayQeueue))
                dispatchQueue = DispatchQueue(label: "com.posthog.ReplayQueue", target: .global(qos: .utility))
            }
        }
    #else
        init(_ config: PostHogConfig, _ storage: PostHogStorage, _ api: PostHogApi, _ endpoint: PostHogApiEndpoint) {
            self.config = config
            self.api = api
            self.endpoint = endpoint
            batchLimits = .initial(from: config)

            switch endpoint {
            case .batch:
                fileQueue = PostHogFileBackedQueue(queue: storage.url(forKey: .queue), oldQueues: [storage.url(forKey: .oldQueueFolder), storage.url(forKey: .oldQueuePlist)])
                dispatchQueue = DispatchQueue(label: "com.posthog.Queue", target: .global(qos: .utility))
            case .snapshot:
                fileQueue = PostHogFileBackedQueue(queue: storage.url(forKey: .replayQeueue))
                dispatchQueue = DispatchQueue(label: "com.posthog.ReplayQueue", target: .global(qos: .utility))
            }
        }
    #endif

    private func eventHandler(_ payload: PostHogConsumerPayload) {
        hedgeLog("Sending batch of \(payload.events.count) events to PostHog")

        switch endpoint {
        case .batch:
            api.batch(events: payload.events) { result in
                self.handleResult(result, payload)
            }
        case .snapshot:
            api.snapshot(events: payload.events) { result in
                self.handleResult(result, payload)
            }
        }
    }

    private func handleResult(_ result: PostHogBatchUploadInfo, _ payload: PostHogConsumerPayload) {
        // -1 means its not anything related to the API but rather network or something else, so we try again
        let statusCode = result.statusCode ?? -1

        // Network error (-1), 3xx redirect, or transient server error: pause
        // and retry the same batch.
        let isRetriable = statusCode == -1
            || (300 ... 399 ~= statusCode)
            || retriableStatusCodes.contains(statusCode)

        if isRetriable {
            retryCount += 1
            let delay = min(retryCount * retryDelay, maxRetryDelay)
            pauseFor(seconds: delay)
            hedgeLog("Pausing queue consumption for \(delay) seconds due to \(retryCount) API failure(s).")
            payload.completion(false)
            return
        }

        // 413 Payload Too Large: halve both the batch cap and the flush
        // threshold and retry without popping. Once the cap reaches 1, drop
        // the batch — we can't shrink any further, so retrying is futile.
        // Matches posthog-android's `deleteFilesIfAPIError`.
        //
        // TODO: posthog-android also drops all queued events after
        // `config.maxRetries` consecutive failures (PostHogQueue.kt:208-212).
        // We don't have an equivalent safeguard yet — track as a follow-up.
        if statusCode == 413 {
            let actualBatchSize = payload.events.count
            let halvedCap: Int? = batchLimitsLock.withLock {
                guard batchLimits.cap > 1 else { return nil }
                return batchLimits.halve(actualBatchSize: actualBatchSize)
            }
            if let halvedCap {
                hedgeLog("Queue: HTTP 413, halved batch cap to \(halvedCap)")
                retryCount = 0
                payload.completion(false)
                return
            }
            hedgeLog("Queue: dropping batch after HTTP 413 (cap == 1)")
            retryCount = 0
            payload.completion(true)
            return
        }

        // 2xx success or non-retriable 4xx (auth, malformed, etc.): pop the
        // batch. The cap stays where it is — no ramp-up, matching
        // posthog-android and posthog-js-lite.
        retryCount = 0
        payload.completion(true)
    }

    func start(disableReachabilityForTesting: Bool,
               disableQueueTimerForTesting: Bool)
    {
        if !disableReachabilityForTesting {
            #if !os(watchOS)
                // Subscribe via the multicast so events, replay, and logs queues
                // can all receive notifications without overwriting each other.
                reachableToken = reachability?.onReachable.subscribe { [weak self] reachability in
                    guard let self else { return }
                    self.pausedLock.withLock {
                        if self.config.dataMode == .wifi, reachability.connection != .wifi {
                            hedgeLog("Queue is paused because its not in WiFi mode")
                            self.paused = true
                        } else {
                            self.paused = false
                        }
                    }

                    // Always trigger a flush when we are on wifi
                    if reachability.connection == .wifi {
                        if !self.isFlushing {
                            self.flush()
                        }
                    }
                }

                unreachableToken = reachability?.onUnreachable.subscribe { [weak self] _ in
                    guard let self else { return }
                    self.pausedLock.withLock {
                        hedgeLog("Queue is paused because network is unreachable")
                        self.paused = true
                    }
                }

                do {
                    try reachability?.startNotifier()
                } catch {
                    hedgeLog("Error: Unable to monitor network reachability: \(error)")
                }
            #endif
        }

        if !disableQueueTimerForTesting {
            timerLock.withLock {
                DispatchQueue.main.async {
                    self.timer = Timer.scheduledTimer(withTimeInterval: self.config.flushIntervalSeconds, repeats: true, block: { _ in
                        if !self.isFlushing {
                            self.flush()
                        }
                    })
                }
            }
        }
    }

    /// Internal, used for testing
    func clear() {
        fileQueue.clear()
    }

    func stop() {
        timerLock.withLock {
            timer?.invalidate()
            timer = nil
        }
        #if !os(watchOS)
            // Tokens auto-unsubscribe on deinit; nilling here detaches earlier
            // so we do not receive callbacks after stop().
            reachableToken = nil
            unreachableToken = nil
        #endif
    }

    func flush() {
        if !canFlush() {
            return
        }

        let cap = batchLimitsLock.withLock { batchLimits.cap }
        take(cap) { payload in
            if !payload.events.isEmpty {
                self.eventHandler(payload)
            } else {
                // there's nothing to be sent
                payload.completion(true)
            }
        }
    }

    func flushIfOverThreshold() {
        let threshold = batchLimitsLock.withLock { batchLimits.flushAt }
        if fileQueue.depth >= threshold {
            flush()
        }
    }

    func add(_ event: PostHogEvent) {
        if fileQueue.depth >= config.maxQueueSize {
            hedgeLog("Queue is full, dropping oldest event")
            // first is always oldest
            fileQueue.delete(index: 0)
        }

        guard let data = toJSONData(event.toJSON()) else {
            hedgeLog("Tried to queue unserialisable PostHogEvent")
            return
        }

        fileQueue.add(data)
        hedgeLog("Queued event '\(event.event)'. Depth: \(fileQueue.depth)")
        flushIfOverThreshold()
    }

    private func take(_ count: Int, completion: @escaping (PostHogConsumerPayload) -> Void) {
        dispatchQueue.async {
            self.isFlushingLock.withLock {
                if self.isFlushing {
                    return
                }
                self.isFlushing = true
            }

            let items = self.fileQueue.peek(count)

            var processing = [PostHogEvent]()

            for item in items {
                // each element is a PostHogEvent if fromJSON succeeds
                guard let event = PostHogEvent.fromJSON(item) else {
                    continue
                }
                processing.append(event)
            }

            completion(PostHogConsumerPayload(events: processing) { success in
                if success, items.count > 0 {
                    self.fileQueue.pop(items.count)
                    hedgeLog("Completed!")
                }

                self.isFlushingLock.withLock {
                    self.isFlushing = false
                }
            })
        }
    }

    private func pauseFor(seconds: TimeInterval) {
        pausedUntil = Date().addingTimeInterval(seconds)
    }

    private func canFlush() -> Bool {
        if isFlushing {
            hedgeLog("Already flushing")
            return false
        }

        if paused {
            // We don't flush data if the queue is paused
            hedgeLog("The queue is paused due to the reachability check")
            return false
        }

        if let pausedUntil, pausedUntil > Date() {
            // We don't flush data if the queue is temporarily paused
            hedgeLog("The queue is paused until `\(pausedUntil)`")
            return false
        }

        return true
    }
}

#if TESTING
    extension PostHogQueue {
        /// Exposes the adaptive batch cap so 413 halving and poison-drop
        /// tests can assert the cap value.
        var currentBatchCapForTesting: Int {
            batchLimitsLock.withLock { batchLimits.cap }
        }

        /// Exposes the adaptive flush threshold so 413 tests can assert it
        /// was halved alongside the batch cap.
        var currentFlushAtForTesting: Int {
            batchLimitsLock.withLock { batchLimits.flushAt }
        }
    }
#endif
