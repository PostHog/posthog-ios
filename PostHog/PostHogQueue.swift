//
//  PostHogQueue.swift
//  PostHog
//
//  Created by Ben White on 06.02.23.
//

import Foundation

/// Clamps `value` to a minimum of 1. Used wherever we initialise / halve
/// the adaptive batch limits so we never store a value below 1.
private func clamped(_ value: Int) -> Int {
    max(1, value)
}

/// Adaptive limits stored privately on the queue rather than mutating
/// `config.maxBatchSize` / `config.flushAt` so user-supplied config fields
/// aren't silently changed. Both `cap` and `flushAt` are halved together on
/// HTTP 413.
private struct BatchLimits {
    var cap: Int
    var flushAt: Int

    static func initial(cap: Int, flushAt: Int) -> BatchLimits {
        BatchLimits(cap: clamped(cap), flushAt: clamped(flushAt))
    }

    /// Halves both `cap` and `flushAt`, returning the new cap. The cap is
    /// bounded by the actual batch size that triggered the halving — partial
    /// batches (queue depth below cap) shouldn't waste a halving step since
    /// the server only saw `actualBatchSize` records anyway. `flushAt` is
    /// clamped to the new `cap` so we never buffer more events than a single
    /// batch can drain. Mirrors posthog-android's `BatchLimits.halve`.
    @discardableResult
    mutating func halve(actualBatchSize: Int) -> Int {
        cap = max(1, min(cap, actualBatchSize) / 2)
        flushAt = clamped(min(flushAt / 2, cap))
        return cap
    }
}

/**
 # Queue

 The queue uses File persistence. This allows us to
 1. Only send events when we have a network connection
 2. Ensure that we can survive app closing or offline situations
 3. Not hold too much in memory

 Generic over `Record` so the same infrastructure can ship analytics events,
 replay snapshots, and OTLP log records — see `QueueEndpoint<Record>` for the
 per-wire codec, send, and retry/cap policy that varies between them.
 */

class PostHogQueue<Record> {
    /// True when `retryCount` has exceeded `maxRetries` after just being
    /// incremented for the current attempt. Comparison is `>` (not `>=`) so the
    /// configured value is the count of *retries* allowed before the drop fires
    /// — with the default of 3 you get attempts 1–3 retried, attempt 4 drops.
    /// Matches posthog-android.
    private static func retryCountExceeded(_ retryCount: TimeInterval, maxRetries: Int) -> Bool {
        Int(retryCount) > maxRetries
    }

    private let config: PostHogConfig
    private let endpoint: QueueEndpoint<Record>
    private let configuredMaxQueueSize: Int
    private let timerInterval: TimeInterval

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
    private let dispatchQueue: DispatchQueue

    private var batchLimits: BatchLimits
    private let batchLimitsLock = NSLock()

    /// Internal, used for testing
    var depth: Int {
        fileQueue.depth
    }

    let fileQueue: PostHogFileBackedQueue

    #if !os(watchOS)
        init(_ config: PostHogConfig, _ storage: PostHogStorage, _ endpoint: QueueEndpoint<Record>, _ reachability: Reachability?) {
            self.config = config
            self.endpoint = endpoint
            self.reachability = reachability
            configuredMaxQueueSize = endpoint.maxQueueSize(config)
            timerInterval = endpoint.flushIntervalSeconds(config)
            batchLimits = .initial(cap: endpoint.initialCap(config), flushAt: endpoint.initialFlushAt(config))
            fileQueue = PostHogFileBackedQueue(
                queue: storage.url(forKey: endpoint.storageKey),
                oldQueues: endpoint.oldStorageKeys.map { storage.url(forKey: $0) }
            )
            dispatchQueue = DispatchQueue(label: endpoint.dispatchQueueLabel, target: .global(qos: .utility))
        }
    #else
        init(_ config: PostHogConfig, _ storage: PostHogStorage, _ endpoint: QueueEndpoint<Record>) {
            self.config = config
            self.endpoint = endpoint
            configuredMaxQueueSize = endpoint.maxQueueSize(config)
            timerInterval = endpoint.flushIntervalSeconds(config)
            batchLimits = .initial(cap: endpoint.initialCap(config), flushAt: endpoint.initialFlushAt(config))
            fileQueue = PostHogFileBackedQueue(
                queue: storage.url(forKey: endpoint.storageKey),
                oldQueues: endpoint.oldStorageKeys.map { storage.url(forKey: $0) }
            )
            dispatchQueue = DispatchQueue(label: endpoint.dispatchQueueLabel, target: .global(qos: .utility))
        }
    #endif

    private func sendBatch(_ payload: PostHogConsumerPayload<Record>) {
        hedgeLog("Sending batch of \(payload.records.count) records to PostHog")
        endpoint.send(payload.records) { [weak self] result in
            self?.handleResult(result, payload)
        }
    }

    private func handleResult(_ result: PostHogUploadInfo, _ payload: PostHogConsumerPayload<Record>) {
        // -1 means its not anything related to the API but rather network or something else, so we try again
        let statusCode = result.statusCode ?? -1

        // Network error (-1), 3xx redirect (events only), or transient server
        // error: pause and retry the same batch.
        let isRetriable = statusCode == -1
            || (endpoint.redirectIsRetriable && (300 ... 399 ~= statusCode))
            || endpoint.retriableStatusCodes.contains(statusCode)

        if isRetriable {
            retryCount += 1
            if Self.retryCountExceeded(retryCount, maxRetries: config.maxRetries) {
                dropAllQueuedRecords(reason: "max retries (\(config.maxRetries)) exceeded")
                payload.completion(true)
                return
            }
            let delay = min(retryCount * retryDelay, maxRetryDelay)
            pauseFor(seconds: delay)
            hedgeLog("Pausing queue consumption for \(delay) seconds due to \(retryCount) API failure(s).")
            payload.completion(false)
            return
        }

        // 413 Payload Too Large. Two paths:
        //  - cap > 1: this is a retry. Increment retryCount, drop all if
        //    `maxRetries` exceeded, otherwise halve cap and retry the same
        //    records.
        //  - cap == 1: poison drop. The offending record can't shrink any
        //    further, so we drop the batch and apply the endpoint's poison
        //    cap policy. Don't count it as a retry — the drop *is* the
        //    resolution, not another attempt.
        if statusCode == 413 {
            let canHalve = batchLimitsLock.withLock { batchLimits.cap > 1 }

            if canHalve {
                retryCount += 1
                if Self.retryCountExceeded(retryCount, maxRetries: config.maxRetries) {
                    dropAllQueuedRecords(reason: "max retries (\(config.maxRetries)) exceeded after repeated HTTP 413")
                    payload.completion(true)
                    return
                }
                let actualBatchSize = payload.records.count
                let halvedCap = batchLimitsLock.withLock {
                    batchLimits.halve(actualBatchSize: actualBatchSize)
                }
                hedgeLog("Queue: HTTP 413, halved batch cap to \(halvedCap)")
                payload.completion(false)
                return
            }

            // Cap stays at 1 — the offender is gone but we keep being
            // cautious until a successful send. Matches posthog-android and
            // posthog-js-lite.
            hedgeLog("Queue: dropping batch after HTTP 413 (cap == 1)")
            retryCount = 0
            payload.completion(true)
            return
        }

        // 2xx success or non-retriable 4xx (auth, malformed, etc.): pop the
        // batch. Cap stays where it is — no ramp on success, matching
        // posthog-android and posthog-js-lite.
        retryCount = 0
        payload.completion(true)
    }

    /// Drops every queued record from disk and resets the retry / pause state.
    /// Called when `retryCount` exceeds `config.maxRetries` to avoid retrying
    /// forever against a permanently-broken backend. Cap is left where it is
    /// — new records starting against a known-bad backend benefit from the
    /// conservative cap until proven otherwise. Matches posthog-android's
    /// `dropAllEvents`.
    private func dropAllQueuedRecords(reason: String) {
        hedgeLog("Queue: dropping all queued records — \(reason)")
        fileQueue.clear()
        retryCount = 0
        pausedUntil = nil
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
                    self.timer = Timer.scheduledTimer(withTimeInterval: self.timerInterval, repeats: true, block: { _ in
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
            if !payload.records.isEmpty {
                self.sendBatch(payload)
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

    func add(_ record: Record) {
        if fileQueue.depth >= configuredMaxQueueSize {
            hedgeLog("Queue is full, dropping oldest record")
            // first is always oldest
            fileQueue.delete(index: 0)
        }

        guard let data = endpoint.encode(record) else {
            hedgeLog("Tried to queue unserialisable record")
            return
        }

        fileQueue.add(data)
        hedgeLog("Queued record. Depth: \(fileQueue.depth)")
        flushIfOverThreshold()
    }

    private func take(_ count: Int, completion: @escaping (PostHogConsumerPayload<Record>) -> Void) {
        dispatchQueue.async {
            self.isFlushingLock.withLock {
                if self.isFlushing {
                    return
                }
                self.isFlushing = true
            }

            let items = self.fileQueue.peek(count)

            var processing: [Record] = []

            for item in items {
                guard let record = self.endpoint.decode(item) else {
                    continue
                }
                processing.append(record)
            }

            completion(PostHogConsumerPayload(records: processing) { success in
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
