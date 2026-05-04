//
//  PostHogLogsQueue.swift
//  PostHog
//

import Foundation

/// Persists log records to disk and flushes them to `/i/v1/logs` in OTLP/JSON
/// batches. Owns its own folder, flush timer, and retry state.
///
/// **Reachability**: `Reachability.whenReachable` / `whenUnreachable` are
/// single-value properties — registering more than one subscriber overwrites
/// the previous one. The events queue owns those slots, so this queue does not
/// subscribe. Transient network failures fall through to the same exponential
/// `pausedUntil` backoff used for HTTP 5xx.
///
/// **Thread safety**: `add(_:)` and `flush()` are callable from any thread and
/// return immediately. In-memory state is guarded by `stateLock`; on-disk state
/// is owned by `PostHogFileBackedQueue` whose own internal lock makes its
/// operations safe to call from `dispatchQueue` (write path) and the URLSession
/// completion queue (`pop` path) concurrently. `stateLock` and `timerLock` are
/// never held simultaneously.
class PostHogLogsQueue {
    private let logsConfig: PostHogLogsConfig
    private let api: PostHogApi

    let fileQueue: PostHogFileBackedQueue
    private let dispatchQueue: DispatchQueue

    // MARK: State (guarded by stateLock unless noted)

    private let stateLock = NSLock()
    private var pausedUntil: Date?
    private var retryCount: TimeInterval = 0
    private var isFlushing = false
    /// Initial value matches `logsConfig.maxBatchSize`; halved on HTTP 413,
    /// ramped back up by 1 on healthy sends. Bounded by [1, maxBatchSize].
    private var currentBatchCap: Int
    private var rateCapWindowStart: Date?
    private var rateCapCount: Int = 0
    /// Flips to `true` the first time we drop a record in the current window;
    /// reset when the window rolls. Used to emit one warning per window instead
    /// of one per dropped record.
    private var rateCapDropWarned = false

    // MARK: Timer (guarded by timerLock — never held with stateLock)

    private let timerLock = NSLock()
    private var timer: Timer?
    /// Set by `stop()`. Prevents the deferred `DispatchQueue.main.async` block
    /// inside `start()` from racing in and creating a timer after teardown.
    private var stopped = false

    /// Internal, used for testing
    var depth: Int {
        fileQueue.depth
    }

    /// Internal, used for testing — exposes the adaptive batch cap so 413
    /// poison-drop tests can assert the cap was reset to `maxBatchSize`.
    var currentBatchCapForTesting: Int {
        stateLock.withLock { currentBatchCap }
    }

    init(_ config: PostHogConfig, _ storage: PostHogStorage, _ api: PostHogApi) {
        logsConfig = config.logs
        self.api = api
        fileQueue = PostHogFileBackedQueue(queue: storage.url(forKey: .logsQueue))
        dispatchQueue = DispatchQueue(label: "com.posthog.LogsQueue", target: .global(qos: .utility))
        currentBatchCap = max(1, config.logs.maxBatchSize)
    }

    // MARK: - Lifecycle

    /// `disableReachabilityForTesting` is accepted for API symmetry with
    /// `PostHogQueue.start(...)` but currently has no effect — the logs queue
    /// does not subscribe to reachability (see class doc).
    func start(disableReachabilityForTesting _: Bool, disableQueueTimerForTesting: Bool) {
        if disableQueueTimerForTesting { return }

        let interval = logsConfig.flushIntervalSeconds
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.timerLock.withLock {
                // If stop() ran before this main-async block fires, do not
                // create a timer that would outlive teardown.
                guard !self.stopped, self.timer == nil else { return }
                self.timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true, block: { [weak self] _ in
                    guard let self else { return }
                    let flushing = self.stateLock.withLock { self.isFlushing }
                    if !flushing {
                        self.flush()
                    }
                })
            }
        }
    }

    func stop() {
        timerLock.withLock {
            stopped = true
            timer?.invalidate()
            timer = nil
        }
    }

    /// Internal, used for testing.
    func clear() {
        fileQueue.clear()
        stateLock.withLock {
            pausedUntil = nil
            retryCount = 0
            isFlushing = false
            currentBatchCap = max(1, logsConfig.maxBatchSize)
            rateCapWindowStart = nil
            rateCapCount = 0
            rateCapDropWarned = false
        }
    }

    // MARK: - Add

    /// Enqueue a log record. The disk write runs synchronously on the calling
    /// thread so the record is durably persisted by the time this returns —
    /// matching `PostHogQueue.add(_:)`'s contract for events.
    func add(_ record: PostHogLogRecord) {
        // beforeSend runs before the rate cap so dropped records do not consume
        // budget.
        var processed = record
        if let beforeSend = logsConfig.beforeSend {
            guard let result = beforeSend(record) else {
                return
            }
            processed = result
        }

        // A user filter may have emptied the body — re-check so we never put an
        // empty record on the wire.
        if processed.body.isEmpty {
            hedgeLog("Logs queue: empty body after beforeSend, dropping record")
            return
        }

        if !consumeRateCap() {
            noteRateCapDropped()
            return
        }

        let storageJSON = processed.toStorageJSON()
        guard let data = toJSONData(storageJSON) else {
            hedgeLog("Could not serialize log record, dropping")
            return
        }

        if fileQueue.depth >= logsConfig.maxBufferSize {
            hedgeLog("Logs buffer is full (\(logsConfig.maxBufferSize)), dropping oldest record")
            fileQueue.delete(index: 0)
        }
        fileQueue.add(data)
        flushIfOverThreshold()
    }

    /// Tumbling-window rate cap. Returns `true` if the record should be admitted,
    /// `false` if the per-window limit has been reached. We re-anchor the window
    /// on any negative elapsed so wall-clock jumps don't strand the counter.
    private func consumeRateCap() -> Bool {
        if logsConfig.rateCapMaxLogs <= 0 {
            return true
        }
        return stateLock.withLock {
            rollRateCapWindowIfNeeded()
            if rateCapCount >= logsConfig.rateCapMaxLogs {
                return false
            }
            rateCapCount += 1
            return true
        }
    }

    /// Caller must hold `stateLock`.
    private func rollRateCapWindowIfNeeded() {
        let now = Date()
        guard let start = rateCapWindowStart else {
            rateCapWindowStart = now
            rateCapCount = 0
            rateCapDropWarned = false
            return
        }
        let elapsed = now.timeIntervalSince(start)
        if elapsed < 0 || elapsed >= logsConfig.rateCapWindowSeconds {
            rateCapWindowStart = now
            rateCapCount = 0
            rateCapDropWarned = false
        }
    }

    /// Logs the first rate-cap drop in each window and silences subsequent ones,
    /// to avoid spamming console at high record rates. The `hedgeLog` call runs
    /// inside the lock so any future swap to a non-thread-safe sink can rely on
    /// the warning being emitted under serialized state.
    private func noteRateCapDropped() {
        stateLock.withLock {
            guard !rateCapDropWarned else { return }
            rateCapDropWarned = true
            hedgeLog("Logs queue rate cap exceeded (\(logsConfig.rateCapMaxLogs) per \(logsConfig.rateCapWindowSeconds)s), dropping records this window")
        }
    }

    // MARK: - Flush

    /// Caller must already be on `dispatchQueue`. Skips the re-dispatch that
    /// `flush()` would normally do — used by `add()` after a write to avoid
    /// scheduling a second work item on the same serial queue.
    private func flushIfOverThreshold() {
        guard fileQueue.depth >= (stateLock.withLock { currentBatchCap }) else { return }
        guard let cap = acquireFlushSlot() else { return }
        executeFlushOnDispatchQueue(cap: cap)
    }

    func flush() {
        guard let cap = acquireFlushSlot() else { return }
        dispatchQueue.async { [weak self] in
            self?.executeFlushOnDispatchQueue(cap: cap)
        }
    }

    /// Atomically reserves the flush slot and reads `currentBatchCap` in the
    /// same critical section, so a concurrent 413 cannot halve the cap between
    /// this decision and the peek below. Returns nil if a flush is already in
    /// flight or the queue is in a backoff window.
    private func acquireFlushSlot() -> Int? {
        stateLock.withLock {
            if isFlushing {
                hedgeLog("Logs queue: already flushing")
                return nil
            }
            if let pausedUntil, pausedUntil > Date() {
                hedgeLog("Logs queue: paused until \(pausedUntil)")
                return nil
            }
            isFlushing = true
            return currentBatchCap
        }
    }

    /// Caller must be on `dispatchQueue` and must have already set `isFlushing`.
    private func executeFlushOnDispatchQueue(cap: Int) {
        let items = fileQueue.peek(cap)
        if items.isEmpty {
            stateLock.withLock { isFlushing = false }
            return
        }

        var records: [PostHogLogRecord] = []
        records.reserveCapacity(items.count)
        for item in items {
            if let record = PostHogLogRecord.fromStorageJSON(item) {
                records.append(record)
            }
        }

        // If every record on disk is corrupt we still need to pop them so we
        // do not loop forever on the same bad files.
        if records.isEmpty {
            hedgeLog("Logs queue: dropping \(items.count) unreadable record(s)")
            fileQueue.pop(items.count)
            stateLock.withLock { isFlushing = false }
            return
        }

        let payload = PostHogLogsOTLP.buildPayload(
            records: records,
            resourceAttributes: buildResourceAttributes(),
            scopeVersion: postHogVersion
        )

        let batchSize = items.count
        hedgeLog("Sending batch of \(batchSize) log records to PostHog")

        api.logs(payload: payload) { [weak self] result in
            self?.handleResult(result, batchSize: batchSize)
        }
    }

    /// Resource attributes attached to every batch. SDK-managed keys are layered
    /// on top of the user-supplied `resourceAttributes` so SDK keys win on key
    /// collision and users can't shadow `service.name`, `os.*`, etc.
    private func buildResourceAttributes() -> [String: Any] {
        var attrs: [String: Any] = [:]
        // User-supplied first so SDK keys can overwrite.
        for (key, value) in logsConfig.resourceAttributes {
            attrs[key] = value
        }
        attrs["service.name"] = logsConfig.serviceName ?? bundleIdentifierFallback()
        if let version = logsConfig.serviceVersion ?? bundleShortVersion() {
            attrs["service.version"] = version
        }
        if let env = logsConfig.environment {
            attrs["deployment.environment"] = env
        }
        attrs["telemetry.sdk.name"] = postHogSdkName
        attrs["telemetry.sdk.version"] = postHogVersion
        attrs["os.name"] = osName()
        attrs["os.version"] = osVersion()
        return attrs
    }

    private func handleResult(_ result: PostHogBatchUploadInfo, batchSize: Int) {
        let statusCode = result.statusCode ?? -1

        // Network error (-1) or transient server error (5xx, 408, 429): retry the
        // same records after exponential backoff.
        let retriable = statusCode == -1 || statusCode == 408 || statusCode == 429 || (500 ... 599 ~= statusCode)

        if retriable {
            stateLock.withLock {
                retryCount += 1
                let delay = min(retryCount * retryDelay, maxRetryDelay)
                pausedUntil = Date().addingTimeInterval(delay)
                hedgeLog("Logs queue: pausing \(delay)s after retry #\(Int(retryCount))")
                isFlushing = false
            }
            return
        }

        // 413 Payload Too Large: halve the cap and retry without popping. If the
        // batch is already a single record there is nothing to halve — drop it
        // so we don't loop forever on a poison record.
        if statusCode == 413 {
            if batchSize <= 1 {
                hedgeLog("Logs queue: dropping single oversized record (HTTP 413)")
                fileQueue.pop(1)
                stateLock.withLock {
                    // Reset cap since the offender is now gone.
                    currentBatchCap = max(1, logsConfig.maxBatchSize)
                    retryCount = 0
                    isFlushing = false
                }
                return
            }
            stateLock.withLock {
                currentBatchCap = max(1, currentBatchCap / 2)
                hedgeLog("Logs queue: HTTP 413, halved batch cap to \(currentBatchCap)")
                retryCount = 0
                isFlushing = false
            }
            return
        }

        // 2xx: pop the records and slowly ramp the cap back up toward configured max.
        if 200 ... 299 ~= statusCode {
            fileQueue.pop(batchSize)
            stateLock.withLock {
                if currentBatchCap < logsConfig.maxBatchSize {
                    currentBatchCap = min(logsConfig.maxBatchSize, currentBatchCap + 1)
                }
                retryCount = 0
                isFlushing = false
            }
            return
        }

        // Any other 4xx (auth, malformed, etc.) — pop the batch so a single bad
        // record can't poison the queue indefinitely.
        hedgeLog("Logs queue: dropping \(batchSize) record(s) after non-retriable HTTP \(statusCode)")
        fileQueue.pop(batchSize)
        stateLock.withLock {
            retryCount = 0
            isFlushing = false
        }
    }

    // MARK: - Resource attribute helpers

    private func bundleIdentifierFallback() -> String {
        Bundle.main.bundleIdentifier ?? "unknown_service"
    }

    private func bundleShortVersion() -> String? {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
    }

    private func osName() -> String {
        #if os(visionOS)
            return "visionOS"
        #elseif os(watchOS)
            return "watchOS"
        #elseif os(tvOS)
            return "tvOS"
        #elseif os(macOS) || targetEnvironment(macCatalyst)
            return "macOS"
        #elseif os(iOS)
            return "iOS"
        #else
            return "unknown"
        #endif
    }

    private func osVersion() -> String {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        return "\(version.majorVersion).\(version.minorVersion).\(version.patchVersion)"
    }
}
