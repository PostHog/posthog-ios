//
//  PostHogLogsConfig.swift
//  PostHog
//

import Foundation

/// A `beforeSend` callback gets one chance to mutate or drop a log record
/// before it is enqueued. Returning `nil` drops the record; mutating the
/// record's `body` to an empty string also drops it. Multiple blocks compose
/// left-to-right; if any returns `nil`, later blocks are skipped. Runs
/// synchronously on the thread that called `captureLog`.
public typealias PostHogBeforeSendLogBlock = (PostHogMutableLogRecord) -> PostHogMutableLogRecord?

/// Configuration for the PostHog logs subsystem. Mutate fields on `config.logs`
/// before calling `PostHogSDK.setup(_:)`.
@objc public final class PostHogLogsConfig: NSObject {
    enum Defaults {
        static let flushIntervalSeconds: TimeInterval = PostHogConfig.Defaults.flushIntervalSeconds
        static let maxBatchSize: Int = PostHogConfig.Defaults.maxBatchSize
        static let maxBufferSize: Int = PostHogConfig.Defaults.maxQueueSize
        static let flushAt: Int = PostHogConfig.Defaults.flushAt
        static let rateCapMaxLogs: Int = 500
        static let rateCapWindowSeconds: TimeInterval = 10
    }

    /// How often the queue checks for records to flush. Read once when the
    /// queue is started by `PostHogSDK.setup(_:)`; mutating this after setup
    /// has no effect on the already-scheduled timer.
    @objc public var flushIntervalSeconds: TimeInterval = Defaults.flushIntervalSeconds

    /// Maximum number of records held on disk. When full, the oldest record is
    /// dropped (FIFO).
    @objc public var maxBufferSize: Int = Defaults.maxBufferSize

    /// Threshold at which the queue triggers a flush automatically. Smaller
    /// than `maxBatchSize` lets the queue fire smaller batches on a steady
    /// cadence rather than waiting for the full cap.
    @objc public var flushAt: Int = Defaults.flushAt

    /// Initial maximum number of records sent in a single request. Halved on
    /// HTTP 413 responses (down to 1, then dropping the offender). Cap stays
    /// where halved — no ramp on success.
    @objc public var maxBatchSize: Int = Defaults.maxBatchSize

    /// OpenTelemetry `service.name` resource attribute. Defaults to the host
    /// app's bundle identifier.
    @objc public var serviceName: String = getBundleIdentifier()

    /// OpenTelemetry `service.version` resource attribute. Defaults to the
    /// host app's `CFBundleShortVersionString`, or empty if unavailable.
    /// Empty values are omitted from the wire payload.
    @objc public var serviceVersion: String = appVersionString() ?? ""

    /// OpenTelemetry `deployment.environment` resource attribute. Omitted from
    /// the payload when nil.
    @objc public var environment: String?

    /// Additional OpenTelemetry resource attributes attached to every batch.
    /// SDK-managed keys (`telemetry.sdk.*`, `os.*`, `service.name`) win on key
    /// collision so users can't shadow them.
    ///
    /// **From ObjC**: bridges to an immutable `NSDictionary`. Replace the
    /// property to change it; in-place mutation on the returned dictionary
    /// will fail.
    @objc public var resourceAttributes: [String: Any] = [:]

    /// Maximum number of records accepted per `rateCapWindowSeconds`. Set to
    /// `0` to disable.
    @objc public var rateCapMaxLogs: Int = Defaults.rateCapMaxLogs

    /// Tumbling window in seconds used by the rate cap.
    @objc public var rateCapWindowSeconds: TimeInterval = Defaults.rateCapWindowSeconds

    private var beforeSend = BeforeSendChain<PostHogMutableLogRecord>()

    public func setBeforeSend(_ blocks: [PostHogBeforeSendLogBlock]) {
        beforeSend.set(blocks)
    }

    public func setBeforeSend(_ blocks: PostHogBeforeSendLogBlock...) {
        setBeforeSend(blocks)
    }

    @available(swift, obsoleted: 1.0, message: "Use setBeforeSend(_ blocks: PostHogBeforeSendLogBlock...) instead")
    @objc public func setBeforeSend(_ blocks: [BoxedBeforeSendLogBlock]) {
        setBeforeSend(blocks.map(\.block))
    }

    func runBeforeSend(_ record: PostHogLogRecord) -> PostHogLogRecord? {
        let view = PostHogMutableLogRecord(record)
        guard let mutated = beforeSend.run(view) else { return nil }
        // Empty body is the documented sentinel for "drop this record" — enforce
        // here so capture-side callers can't forget the check.
        if mutated.body.isEmpty { return nil }
        mutated.apply(to: record)
        return record
    }

    @objc override public init() {
        super.init()
    }
}
