//
//  PostHogQueue.swift
//  PostHog
//
//  Created by Ben White on 06.02.23.
//

import Foundation

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
    /// batch can drain.
    @discardableResult
    mutating func halve(actualBatchSize: Int) -> Int {
        cap = clamped(min(cap, actualBatchSize) / 2)
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
    private let config: PostHogConfig
    private let endpoint: QueueEndpoint<Record>
    private let configuredMaxQueueSize: Int
    private let timerInterval: TimeInterval

    /// Guards `paused`, `pausedUntil`, `retryCount`, `payloadTooLargeCount`, and
    /// `failingSince`. These are touched from the URLSession completion queue
    /// (handleResult), the timer's main-thread callback (canFlush), and the
    /// reachability callbacks (onReachable / onUnreachable) — all without
    /// coordination — so a single state lock keeps them consistent against
    /// ThreadSanitizer.
    private let stateLock = NSLock()
    private var paused: Bool = false
    private var pausedUntil: Date?
    /// Consecutive retriable failures (transport `-1` and server 5xx/429/…),
    /// used only to ramp the backoff delay. Reset on any success or full drop.
    /// It deliberately does *not* gate the HTTP 413 halving budget — see
    /// `payloadTooLargeCount`.
    private var retryCount: Int = 0
    /// Consecutive HTTP 413 batch-halving attempts, compared against
    /// `config.maxRetries`. Kept separate from `retryCount` so transport and
    /// 5xx failures — which must never drop the queue — can't consume the 413
    /// halving budget and let the first 413 wipe every buffered record.
    /// Incremented only when a 413 halves the cap; reset on success, on the
    /// 413 poison drop, and on a full queue drop.
    private var payloadTooLargeCount: Int = 0
    /// Wall clock of the first failure in the current unhealthy-backend streak,
    /// or `nil` while healthy. Only server-side retriable failures (5xx, 429,
    /// …) arm it; a transport failure clears it instead, so an offline stretch
    /// can't count toward the drop window. Also cleared on any success.
    ///
    /// In-memory only — not persisted with the on-disk queue, so the streak and
    /// therefore the `maxRetryWindowSeconds` drop window are measured within a
    /// single process lifetime and restart from zero on every app launch. On
    /// platforms that terminate processes frequently (iOS) the window-based
    /// drop rarely fires; `maxQueueSize` remains the effective bound on the
    /// buffer. Kept in memory deliberately: persisting it would add a storage
    /// key and a disk write on each first failure for a safeguard that never
    /// causes data loss or unbounded growth on its own.
    private var failingSince: Date?

    /// Invoked from `dropAllQueuedRecords` with the number of records wiped and
    /// the reason. The SDK wires this to emit a diagnostic event so a full
    /// queue drop — the last remaining silent, total data-loss path — becomes
    /// measurable.
    var onRecordsDropped: ((Int, String) -> Void)?
    #if !os(watchOS)
        private let reachability: Reachability?
        private var reachableToken: RegistrationToken?
        private var unreachableToken: RegistrationToken?
    #endif

    private var isFlushing = false
    private let isFlushingLock = NSLock()
    /// Guards `timer` and `stopped`. The flag is set by `stop()` so a `start()`
    /// whose main-thread block hasn't fired yet can short-circuit instead of
    /// scheduling a timer that escapes invalidation.
    private let timerLock = NSLock()
    private var timer: Timer?
    private var stopped: Bool = false
    private let dispatchQueue: DispatchQueue

    private var batchLimits: BatchLimits
    private let batchLimitsLock = NSLock()

    /// Records accepted per `rateCapWindowSeconds`. `0` disables the cap and
    /// is the default for endpoints that don't opt in.
    private let rateCapMax: Int
    private let rateCapWindowSeconds: TimeInterval

    /// Guards the tumbling-window state below. Separate from `stateLock` so a
    /// hot-path `add(_:)` doesn't contend with reachability / retry traffic.
    private let rateCapLock = NSLock()
    private var rateCapWindowStart: Date?
    private var rateCapCount: Int = 0
    /// Flips to `true` the first time we drop a record in the current window;
    /// reset when the window rolls. Used to emit one warning per window
    /// instead of one per dropped record.
    private var rateCapDropWarned = false

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
            rateCapMax = endpoint.rateCapMax(config)
            rateCapWindowSeconds = endpoint.rateCapWindowSeconds(config)
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
            rateCapMax = endpoint.rateCapMax(config)
            rateCapWindowSeconds = endpoint.rateCapWindowSeconds(config)
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

        // A transport failure (-1: lost connectivity, timeout, no route) means
        // we could not reach the backend — not that it rejected our data. It is
        // universally retriable and must never drop the queue. Everything else
        // is up to the endpoint's retry policy.
        let isTransportFailure = statusCode == -1
        let isRetriable = isTransportFailure || endpoint.isRetriableStatusCode(statusCode)

        if isRetriable {
            // `since` is the start of the current server-failure streak, or
            // `nil` when the streak isn't armed. A transport failure *resets*
            // the clock — the backend just went unreachable, so this is no
            // longer a responsive-but-unhealthy streak — while a server-side
            // failure arms it if it wasn't already. Clearing (not merely
            // ignoring) `failingSince` on a transport failure is what keeps an
            // offline stretch from counting toward the drop window: otherwise a
            // 500, then hours offline, then one more 500 would see the whole
            // gap as sustained backend failure and wipe the queue.
            let (newCount, since): (Int, Date?) = stateLock.withLock {
                retryCount += 1
                if isTransportFailure {
                    failingSince = nil
                } else if failingSince == nil {
                    failingSince = now()
                }
                return (retryCount, failingSince)
            }

            // Drop the queue only when a responsive-but-unhealthy backend has
            // kept rejecting our batches for a sustained window. Transport
            // failures are excluded: the events wait on disk for connectivity
            // to return and `maxQueueSize` bounds growth, so a flaky network
            // can never wipe the buffer.
            if let since, now().timeIntervalSince(since) >= config.maxRetryWindowSeconds {
                dropAllQueuedRecords(reason: "backend failing for over \(config.maxRetryWindowSeconds)s")
                payload.completion(true)
                return
            }

            let backoffDelay = min(TimeInterval(newCount) * retryDelay, maxRetryDelay)
            let delay = max(backoffDelay, result.retryAfter ?? 0)
            pauseFor(seconds: delay)
            hedgeLog("Pausing queue consumption for \(delay) seconds due to \(newCount) API failure(s).")
            payload.completion(false)
            return
        }

        // 413 Payload Too Large. Two paths:
        //  - cap > 1: this is a retry. Increment the 413 halving count, drop
        //    all if `maxRetries` exceeded, otherwise halve cap and retry the
        //    same records.
        //  - cap == 1: poison drop. The offending record can't shrink any
        //    further, so we drop the batch and apply the endpoint's poison
        //    cap policy. Don't count it as a retry — the drop *is* the
        //    resolution, not another attempt.
        if statusCode == 413 {
            let canHalve = batchLimitsLock.withLock { batchLimits.cap > 1 && payload.records.count > 1 }

            if canHalve {
                let newCount = stateLock.withLock { () -> Int in
                    payloadTooLargeCount += 1
                    return payloadTooLargeCount
                }
                if newCount > config.maxRetries {
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
            // cautious until a successful send.
            hedgeLog("Queue: dropping batch after HTTP 413 (cap == 1)")
            stateLock.withLock {
                retryCount = 0
                payloadTooLargeCount = 0
                failingSince = nil
            }
            payload.completion(true)
            return
        }

        // 2xx success or non-retriable 4xx (auth, malformed, etc.): pop the
        // batch. Cap stays where it is — no ramp on success.
        stateLock.withLock {
            retryCount = 0
            payloadTooLargeCount = 0
            failingSince = nil
        }
        payload.completion(true)
    }

    /// Drops every queued record from disk and resets the retry / pause state.
    /// Reserved for a backend that keeps rejecting our batches past
    /// `maxRetryWindowSeconds`, or repeated HTTP 413 halving — never a network
    /// blip. Reports the number of dropped records through `onRecordsDropped`
    /// so the loss is measurable. Cap is left where it is — new records
    /// starting against a known-bad backend benefit from the conservative cap
    /// until proven otherwise.
    private func dropAllQueuedRecords(reason: String) {
        let dropped = fileQueue.depth
        hedgeLog("Queue: dropping all queued records — \(reason)")
        fileQueue.clear()
        stateLock.withLock {
            retryCount = 0
            payloadTooLargeCount = 0
            failingSince = nil
            pausedUntil = nil
        }
        if dropped > 0 {
            onRecordsDropped?(dropped, reason)
        }
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
                    self.stateLock.withLock {
                        if self.config.dataMode == .wifi, reachability.connection != .wifi {
                            hedgeLog("Queue is paused because its not in WiFi mode")
                            self.paused = true
                        } else {
                            self.paused = false
                        }
                    }

                    if reachability.connection == .wifi {
                        self.flush()
                    }
                }

                unreachableToken = reachability?.onUnreachable.subscribe { [weak self] _ in
                    guard let self else { return }
                    self.stateLock.withLock {
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
            // Schedule on the main runloop so the Timer fires in a default
            // mode. The lock is re-acquired *inside* the dispatched block so a
            // concurrent `stop()` (which sets `stopped = true`) can short-
            // circuit and prevent a leaked timer.
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.timerLock.withLock {
                    guard !self.stopped else { return }
                    self.timer = Timer.scheduledTimer(withTimeInterval: self.timerInterval, repeats: true, block: { [weak self] _ in
                        self?.timerFired()
                    })
                }
            }
        }
    }

    private func timerFired() {
        flush()
    }

    /// Internal, used for testing
    func clear() {
        fileQueue.clear()
        rateCapLock.withLock {
            rateCapWindowStart = nil
            rateCapCount = 0
            rateCapDropWarned = false
        }
    }

    func stop() {
        // Snapshot the timer under the lock, then invalidate on the main
        // thread (Timer requires invalidation on the runloop it was scheduled
        // on). Setting `stopped = true` blocks any in-flight `start()` whose
        // main-thread block has not yet fired from creating a new timer.
        let timerToInvalidate: Timer? = timerLock.withLock {
            stopped = true
            let snapshot = timer
            timer = nil
            return snapshot
        }
        if let timerToInvalidate {
            if Thread.isMainThread {
                timerToInvalidate.invalidate()
            } else {
                DispatchQueue.main.async {
                    timerToInvalidate.invalidate()
                }
            }
        }

        #if !os(watchOS)
            // Releases the multicast tokens; new subscriber callbacks won't be
            // dispatched after this. Callbacks already past the multicast
            // snapshot can still complete — the `[weak self]` capture on each
            // subscription neutralises them once the queue is also nilled.
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

    /// Enqueues a record on the caller's thread. Encoding plus the
    /// `fileQueue.add` disk write are synchronous — sized in microseconds for
    /// a healthy filesystem but technically blocking. We keep it sync to
    /// preserve crash durability: a process kill between `add()` returning and
    /// a deferred write would lose the record. Callers on hot paths (main
    /// thread, frame loops) should be aware.
    ///
    /// Rate cap drops happen *before* the FIFO eviction check so a new record
    /// over the cap doesn't displace an older queued one — the rate cap is a
    /// caller-side throttle, not a buffer policy.
    func add(_ record: Record) {
        if !consumeRateCap() {
            noteRateCapDropped()
            return
        }

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
        hedgeLog("Queued \(endpoint.describe(record)). Depth: \(fileQueue.depth)")
        flushIfOverThreshold()
    }

    /// Returns `true` if the record can be enqueued, `false` if the per-window
    /// cap has been reached. Re-anchors the window on negative elapsed so
    /// wall-clock jumps don't strand the counter.
    private func consumeRateCap() -> Bool {
        if rateCapMax <= 0 {
            return true
        }
        return rateCapLock.withLock {
            rollRateCapWindowIfNeeded()
            if rateCapCount >= rateCapMax {
                return false
            }
            rateCapCount += 1
            return true
        }
    }

    /// Caller must hold `rateCapLock`.
    private func rollRateCapWindowIfNeeded() {
        let current = now()
        guard let start = rateCapWindowStart else {
            rateCapWindowStart = current
            rateCapCount = 0
            rateCapDropWarned = false
            return
        }
        let elapsed = current.timeIntervalSince(start)
        if elapsed < 0 || elapsed >= rateCapWindowSeconds {
            rateCapWindowStart = current
            rateCapCount = 0
            rateCapDropWarned = false
        }
    }

    /// Logs the first rate-cap drop in each window and silences subsequent
    /// ones, to avoid spamming console at high record rates.
    private func noteRateCapDropped() {
        rateCapLock.withLock {
            guard !rateCapDropWarned else { return }
            rateCapDropWarned = true
            hedgeLog("Queue rate cap exceeded (\(rateCapMax) per \(rateCapWindowSeconds)s), dropping records this window")
        }
    }

    private func take(_ count: Int, completion: @escaping (PostHogConsumerPayload<Record>) -> Void) {
        dispatchQueue.async { [weak self] in
            guard let self else { return }

            // Re-check pause state on the dispatch queue: the synchronous
            // `canFlush()` snapshot can lie if reachability flipped or
            // `pausedUntil` was set between the caller's check and now.
            if self.pauseReason() != nil { return }

            // Atomically test-and-set the flushing flag. `withLock` returns
            // the closure value, so a `false` here means another flush is
            // already in flight and we bail out of the function — not just
            // the closure.
            let acquired: Bool = self.isFlushingLock.withLock {
                if self.isFlushing { return false }
                self.isFlushing = true
                return true
            }
            if !acquired {
                hedgeLog("Already flushing")
                return
            }

            let items = self.fileQueue.peek(count)

            var processing: [Record] = []

            for item in items {
                guard let record = self.endpoint.decode(item) else {
                    continue
                }
                processing.append(record)
            }

            completion(PostHogConsumerPayload(records: processing) { [weak self] success in
                guard let self else { return }
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
        let until = now().addingTimeInterval(seconds)
        stateLock.withLock { pausedUntil = until }
    }

    /// Returns a human-readable pause reason if the queue is currently
    /// paused, or `nil` if it can flush. Used by both the synchronous
    /// pre-check in `flush()` and the re-check inside `take()`.
    private func pauseReason() -> String? {
        let (isPaused, until) = stateLock.withLock { (paused, pausedUntil) }
        if isPaused { return "paused due to the reachability check" }
        if let until, until > now() { return "paused until `\(until)`" }
        return nil
    }

    private func canFlush() -> Bool {
        if let reason = pauseReason() {
            hedgeLog("The queue is \(reason)")
            return false
        }
        return true
    }
}

#if TESTING
    extension PostHogQueue {
        var currentBatchCapForTesting: Int {
            batchLimitsLock.withLock { batchLimits.cap }
        }

        var currentFlushAtForTesting: Int {
            batchLimitsLock.withLock { batchLimits.flushAt }
        }

        var currentRetryCountForTesting: Int {
            stateLock.withLock { retryCount }
        }
    }
#endif
