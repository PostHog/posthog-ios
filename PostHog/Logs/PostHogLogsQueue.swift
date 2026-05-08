//
//  PostHogLogsQueue.swift
//  PostHog
//

import Foundation

/// Wraps `PostHogQueue<PostHogLogRecord>` with a tumbling-window rate cap;
/// everything else (persistence, retry, 413 halving, reachability) is owned
/// by the inner generic queue. `config.logs` values are snapshotted at init
/// so post-setup mutations don't race the queue threads.
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

    var depth: Int { inner.depth }

    var fileQueue: PostHogFileBackedQueue { inner.fileQueue }

    var currentBatchCapForTesting: Int {
        #if TESTING
            return inner.currentBatchCapForTesting
        #else
            return 0
        #endif
    }

    // Clamp to 0; a negative window would make `elapsed >= window`
    // trivially true and reset the counter on every call.
    #if !os(watchOS)
        init(_ config: PostHogConfig, _ storage: PostHogStorage, _ api: PostHogApi, _ reachability: Reachability?) {
            rateCapMaxLogs = max(0, config.logs.rateCapMaxLogs)
            rateCapWindowSeconds = max(0, config.logs.rateCapWindowSeconds)
            let resourceAttributes = Self.buildResourceAttributes(config.logs)
            let endpoint = QueueEndpoint<PostHogLogRecord>.logs(
                api: api,
                resourceAttributes: resourceAttributes
            )
            inner = PostHogQueue(config, storage, endpoint, reachability)
        }
    #else
        init(_ config: PostHogConfig, _ storage: PostHogStorage, _ api: PostHogApi) {
            rateCapMaxLogs = max(0, config.logs.rateCapMaxLogs)
            rateCapWindowSeconds = max(0, config.logs.rateCapWindowSeconds)
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

    func clear() {
        inner.clear()
        stateLock.withLock {
            rateCapWindowStart = nil
            rateCapCount = 0
            rateCapDropWarned = false
        }
    }

    // MARK: - Add

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

    /// Re-anchors the window on any negative elapsed so wall-clock jumps
    /// don't strand the counter.
    private func consumeRateCap() -> Bool {
        // Both clamp to 0 in init when invalid; treat 0 as "no cap".
        if rateCapMaxLogs <= 0 || rateCapWindowSeconds <= 0 {
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
