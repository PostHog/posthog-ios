//
//  PostHogLogsQueue.swift
//  PostHog
//

import Foundation

/// Wraps a `PostHogQueue<PostHogLogRecord>` to add the two log-specific
/// behaviours that don't fit on the generic queue: a `beforeSend` hook and a
/// tumbling-window rate cap. Everything else (disk persistence, reachability,
/// flush timer, retry/backoff, HTTP 413 adaptive batching, `maxRetries`
/// queue-wide drop) is owned by the inner generic queue, which uses the
/// `QueueEndpoint<PostHogLogRecord>.logs(...)` spec for OTLP encoding and
/// post-flush cap policy.
///
/// **Thread safety**: `add(_:)` and `flush()` are callable from any thread and
/// return immediately. `stateLock` guards the rate-cap window state; the inner
/// queue owns its own locks for retry / cap state. All `config.logs` values
/// are snapshotted at init so post-setup mutations on the config don't race
/// with reads on the queue's threads.
class PostHogLogsQueue {
    private let inner: PostHogQueue<PostHogLogRecord>

    // MARK: Snapshotted from `config.logs` at init

    private let rateCapMaxLogs: Int
    private let rateCapWindowSeconds: TimeInterval

    // MARK: Rate-cap state (guarded by stateLock)

    private let stateLock = NSLock()
    private var rateCapWindowStart: Date?
    private var rateCapCount: Int = 0
    /// Flips to `true` the first time we drop a record in the current window;
    /// reset when the window rolls. Used to emit one warning per window
    /// instead of one per dropped record.
    private var rateCapDropWarned = false

    /// Internal, used for testing
    var depth: Int { inner.depth }

    /// Internal, used for testing — exposes the underlying file-backed queue
    /// so tests can peek at on-disk records directly.
    var fileQueue: PostHogFileBackedQueue { inner.fileQueue }

    /// Internal, used for testing — exposes the adaptive batch cap.
    var currentBatchCapForTesting: Int {
        #if TESTING
            return inner.currentBatchCapForTesting
        #else
            return 0
        #endif
    }

    #if !os(watchOS)
        init(_ config: PostHogConfig, _ storage: PostHogStorage, _ api: PostHogApi, _ reachability: Reachability?) {
            rateCapMaxLogs = config.logs.rateCapMaxLogs
            rateCapWindowSeconds = config.logs.rateCapWindowSeconds
            let resourceAttributes = Self.buildResourceAttributes(config.logs)
            let endpoint = QueueEndpoint<PostHogLogRecord>.logs(
                api: api,
                resourceAttributes: resourceAttributes
            )
            inner = PostHogQueue(config, storage, endpoint, reachability)
        }
    #else
        init(_ config: PostHogConfig, _ storage: PostHogStorage, _ api: PostHogApi) {
            rateCapMaxLogs = config.logs.rateCapMaxLogs
            rateCapWindowSeconds = config.logs.rateCapWindowSeconds
            let resourceAttributes = Self.buildResourceAttributes(config.logs)
            let endpoint = QueueEndpoint<PostHogLogRecord>.logs(
                api: api,
                resourceAttributes: resourceAttributes
            )
            inner = PostHogQueue(config, storage, endpoint)
        }
    #endif

    // MARK: - Lifecycle

    func start(disableReachabilityForTesting: Bool, disableQueueTimerForTesting: Bool) {
        inner.start(disableReachabilityForTesting: disableReachabilityForTesting,
                    disableQueueTimerForTesting: disableQueueTimerForTesting)
    }

    func stop() {
        inner.stop()
    }

    /// Internal, used for testing.
    func clear() {
        inner.clear()
        stateLock.withLock {
            rateCapWindowStart = nil
            rateCapCount = 0
            rateCapDropWarned = false
        }
    }

    // MARK: - Add

    /// Enqueue a log record. Runs the rate cap on the calling thread, then
    /// delegates to the inner generic queue (which performs the synchronous
    /// disk write per its `add()` contract).
    func add(_ record: PostHogLogRecord) {
        if !consumeRateCap() {
            noteRateCapDropped()
            return
        }

        inner.add(record)
    }

    func flush() {
        inner.flush()
    }

    // MARK: - Rate cap

    /// Tumbling-window rate cap. Returns `true` if the record should be
    /// admitted, `false` if the per-window limit has been reached. Re-anchors
    /// the window on any negative elapsed so wall-clock jumps don't strand
    /// the counter.
    private func consumeRateCap() -> Bool {
        if rateCapMaxLogs <= 0 {
            return true
        }
        return stateLock.withLock {
            rollRateCapWindowIfNeeded()
            if rateCapCount >= rateCapMaxLogs {
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
        if elapsed < 0 || elapsed >= rateCapWindowSeconds {
            rateCapWindowStart = now
            rateCapCount = 0
            rateCapDropWarned = false
        }
    }

    /// Logs the first rate-cap drop in each window and silences subsequent
    /// ones, to avoid spamming console at high record rates.
    private func noteRateCapDropped() {
        stateLock.withLock {
            guard !rateCapDropWarned else { return }
            rateCapDropWarned = true
            hedgeLog("Logs queue rate cap exceeded (\(rateCapMaxLogs) per \(rateCapWindowSeconds)s), dropping records this window")
        }
    }

    // MARK: - Resource attributes

    /// Resource attributes attached to every batch. SDK-managed keys are
    /// layered on top of the user-supplied `resourceAttributes` so SDK keys
    /// win on key collision and users can't shadow `service.name`, `os.*`,
    /// etc.
    private static func buildResourceAttributes(_ logsConfig: PostHogLogsConfig) -> [String: Any] {
        var attrs: [String: Any] = [:]
        for (key, value) in logsConfig.resourceAttributes {
            attrs[key] = value
        }
        attrs["service.name"] = logsConfig.serviceName
        if !logsConfig.serviceVersion.isEmpty {
            attrs["service.version"] = logsConfig.serviceVersion
        }
        if let env = logsConfig.environment {
            attrs["deployment.environment"] = env
        }
        attrs["telemetry.sdk.name"] = postHogSdkName
        attrs["telemetry.sdk.version"] = postHogVersion
        attrs["os.name"] = osName()
        attrs["os.version"] = osVersionString()
        return attrs
    }
}
