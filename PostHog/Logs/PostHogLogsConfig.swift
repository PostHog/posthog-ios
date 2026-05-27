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
///
/// - Parameter record: The log record about to be queued.
/// - Returns: The record to queue, or `nil` to drop it.
public typealias PostHogBeforeSendLogBlock = (PostHogLogRecord) -> PostHogLogRecord?

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

    /// How often the queue checks for records to flush. Set before
    /// `PostHogSDK.setup(_:)`; later mutations are ignored.
    @objc public var flushIntervalSeconds: TimeInterval = Defaults.flushIntervalSeconds

    /// Maximum number of records held on disk. When full, the oldest record is
    /// dropped (FIFO).
    @objc public var maxBufferSize: Int = Defaults.maxBufferSize

    /// Threshold at which the queue triggers a flush automatically. Smaller
    /// than `maxBatchSize` lets the queue fire smaller batches on a steady
    /// cadence rather than waiting for the full cap.
    @objc public var flushAt: Int = Defaults.flushAt

    /// Initial maximum number of records sent in a single request. May be
    /// reduced under server backpressure.
    @objc public var maxBatchSize: Int = Defaults.maxBatchSize

    /// OpenTelemetry `service.name` resource attribute. Defaults to the host
    /// app's bundle identifier. Set before `PostHogSDK.setup(_:)`; later
    /// mutations are ignored.
    @objc public var serviceName: String = getBundleIdentifier()

    /// OpenTelemetry `service.version` resource attribute. Defaults to the
    /// host app's `CFBundleShortVersionString`, or empty if unavailable.
    /// Empty values are omitted from the wire payload. Set before
    /// `PostHogSDK.setup(_:)`; later mutations are ignored.
    @objc public var serviceVersion: String = appVersionString() ?? ""

    /// OpenTelemetry `deployment.environment` resource attribute. Omitted from
    /// the payload when nil. Set before `PostHogSDK.setup(_:)`; later
    /// mutations are ignored.
    @objc public var environment: String?

    /// Additional OpenTelemetry resource attributes attached to every batch.
    /// SDK-managed keys (`telemetry.sdk.*`, `os.*`, `service.name`) win on key
    /// collision so users can't shadow them. Set before
    /// `PostHogSDK.setup(_:)`; later mutations are ignored.
    ///
    /// **From ObjC**: bridges to an immutable `NSDictionary`. Replace the
    /// property to change it; in-place mutation on the returned dictionary
    /// will fail.
    @objc public var resourceAttributes: [String: Any] = [:]

    /// Maximum number of records accepted per `rateCapWindowSeconds`. Set to
    /// `0` (or any non-positive value) to disable the cap. Set before
    /// `PostHogSDK.setup(_:)`; later mutations are ignored.
    @objc public var rateCapMaxLogs: Int = Defaults.rateCapMaxLogs

    /// Tumbling window in seconds used by the rate cap. Must be positive;
    /// non-positive values disable the cap. Set before `PostHogSDK.setup(_:)`;
    /// later mutations are ignored.
    @objc public var rateCapWindowSeconds: TimeInterval = Defaults.rateCapWindowSeconds

    private var beforeSend = BeforeSendChain<PostHogLogRecord>()

    /// Replaces the log `beforeSend` chain with the provided blocks.
    ///
    /// Blocks run synchronously in array order before a log is enqueued. Returning
    /// `nil` from any block drops the log and skips the remaining blocks.
    ///
    /// - Parameter blocks: Ordered callbacks that can mutate or drop log records.
    public func setBeforeSend(_ blocks: [PostHogBeforeSendLogBlock]) {
        beforeSend.set(blocks)
    }

    /// Replaces the log `beforeSend` chain with the provided blocks.
    ///
    /// - Parameter blocks: Ordered callbacks that can mutate or drop log records.
    public func setBeforeSend(_ blocks: PostHogBeforeSendLogBlock...) {
        setBeforeSend(blocks)
    }

    /// Replaces the log `beforeSend` chain from Objective-C boxed callbacks.
    ///
    /// - Parameter blocks: Ordered Objective-C callback boxes.
    @available(swift, obsoleted: 1.0, message: "Use setBeforeSend(_ blocks: PostHogBeforeSendLogBlock...) instead")
    @objc public func setBeforeSend(_ blocks: [BoxedBeforeSendLogBlock]) {
        setBeforeSend(blocks.map(\.block))
    }

    func runBeforeSend(_ record: PostHogLogRecord) -> PostHogLogRecord? {
        guard let result = beforeSend.run(record) else { return nil }
        // Empty (or whitespace-only) body is the documented sentinel for
        // "drop this record" — enforce here so capture-side callers can't
        // forget the check.
        if result.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return nil }
        return result
    }

    /// Creates a logs configuration with default queueing, resource, and rate-cap options.
    @objc override public init() {
        super.init()
    }
}
