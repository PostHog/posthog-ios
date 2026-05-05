//
//  PostHogQueue.swift
//  PostHog
//
//  Created by Ben White on 06.02.23.
//

import Foundation

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
    #endif

    private var isFlushing = false
    private let isFlushingLock = NSLock()
    private var timer: Timer?
    private let timerLock = NSLock()
    private let endpoint: PostHogApiEndpoint
    private let dispatchQueue: DispatchQueue

    /// Both halved on HTTP 413; the batch is dropped once the cap reaches 1.
    /// Once reduced, both stay reduced for the SDK's lifetime — matches
    /// posthog-android. There is no ramp-back-up on healthy sends and no
    /// reset on the poison drop. Stored privately rather than mutating
    /// `config.maxBatchSize` / `config.flushAt` so user-supplied config
    /// fields aren't silently changed.
    private var currentBatchCap: Int
    private var currentFlushAt: Int
    private let batchSizeLock = NSLock()

    /// Internal, used for testing
    var depth: Int {
        fileQueue.depth
    }

    /// Internal, used for testing — exposes the adaptive batch cap so 413
    /// halving and poison-drop tests can assert the cap value.
    var currentBatchCapForTesting: Int {
        batchSizeLock.withLock { currentBatchCap }
    }

    /// Internal, used for testing — exposes the adaptive flush threshold so
    /// 413 tests can assert it was halved alongside the batch cap.
    var currentFlushAtForTesting: Int {
        batchSizeLock.withLock { currentFlushAt }
    }

    let fileQueue: PostHogFileBackedQueue

    #if !os(watchOS)
        init(_ config: PostHogConfig, _ storage: PostHogStorage, _ api: PostHogApi, _ endpoint: PostHogApiEndpoint, _ reachability: Reachability?) {
            self.config = config
            self.api = api
            self.reachability = reachability
            self.endpoint = endpoint
            currentBatchCap = max(1, config.maxBatchSize)
            currentFlushAt = max(1, config.flushAt)

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
            currentBatchCap = max(1, config.maxBatchSize)
            currentFlushAt = max(1, config.flushAt)

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

        // Network error (-1), 3xx redirect, or transient server error: pause and
        // retry the same batch. The 5xx subset is intentionally narrow to match
        // posthog-android's RETRYABLE_STATUS_CODES.
        let retriable = statusCode == -1
            || (300 ... 399 ~= statusCode)
            || statusCode == 429
            || statusCode == 500
            || statusCode == 502
            || statusCode == 503
            || statusCode == 504

        if retriable {
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
        if statusCode == 413 {
            let halvedCap: Int? = batchSizeLock.withLock {
                guard currentBatchCap > 1 else { return nil }
                currentBatchCap = max(1, currentBatchCap / 2)
                currentFlushAt = max(1, currentFlushAt / 2)
                return currentBatchCap
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
            // Setup the monitoring of network status for the queue
            #if !os(watchOS)
                reachability?.whenReachable = { reachability in
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

                reachability?.whenUnreachable = { _ in
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
    }

    func flush() {
        if !canFlush() {
            return
        }

        let cap = batchSizeLock.withLock { currentBatchCap }
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
        let threshold = batchSizeLock.withLock { currentFlushAt }
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
