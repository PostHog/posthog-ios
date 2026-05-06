//
//  PostHogLogsConfig.swift
//  PostHog
//

import Foundation

/// A `beforeSend` callback gets one chance to mutate or drop a log record
/// before it is enqueued. Returning `nil` drops the record. Runs synchronously
/// on the thread that called `captureLog`.
public typealias PostHogBeforeSendLogBlock = (PostHogLogRecord) -> PostHogLogRecord?

@objc public final class BoxedBeforeSendLogBlock: NSObject {
    @objc public let block: PostHogBeforeSendLogBlock

    @objc(block:)
    public init(block: @escaping PostHogBeforeSendLogBlock) {
        self.block = block
    }
}

/// Configuration for the PostHog logs subsystem. Mutate fields on `config.logs`
/// before calling `PostHogSDK.setup(_:)`.
@objc(PostHogLogsConfig) public final class PostHogLogsConfig: NSObject {
    enum Defaults {
        static let flushIntervalSeconds: TimeInterval = PostHogConfig.Defaults.flushIntervalSeconds
        static let maxBatchSize: Int = PostHogConfig.Defaults.maxBatchSize
        static let maxBufferSize: Int = 100
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

    /// Initial maximum number of records sent in a single request. Halved on
    /// HTTP 413 responses (down to 1, then dropping the offender) and ramped
    /// back up by 1 on each healthy send.
    @objc public var maxBatchSize: Int = Defaults.maxBatchSize

    /// OpenTelemetry `service.name` resource attribute. Defaults to the host
    /// app's bundle identifier (or `"unknown_service"` if unavailable).
    @objc public var serviceName: String = bundleIdentifier(fallback: "unknown_service")

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
    @objc public var resourceAttributes: [String: Any] = [:]

    /// Maximum number of records accepted per `rateCapWindowSeconds`. Set to
    /// `0` to disable.
    @objc public var rateCapMaxLogs: Int = Defaults.rateCapMaxLogs

    /// Tumbling window in seconds used by the rate cap.
    @objc public var rateCapWindowSeconds: TimeInterval = Defaults.rateCapWindowSeconds

    /// Hook invoked before each record is enqueued. Returning `nil` drops the
    /// record; returning a record with an empty `body` also drops it.
    /// Multiple blocks compose left-to-right; if any returns `nil`, later
    /// blocks are skipped.
    private var beforeSend = BeforeSendChain<PostHogLogRecord>()

    public func setBeforeSend(_ blocks: [PostHogBeforeSendLogBlock]) {
        beforeSend.set(blocks)
    }

    public func setBeforeSend(_ blocks: PostHogBeforeSendLogBlock...) {
        setBeforeSend(blocks)
    }

    @available(*, unavailable, message: "Use setBeforeSend(_ blocks: PostHogBeforeSendLogBlock...) instead")
    @objc public func setBeforeSend(_ blocks: [BoxedBeforeSendLogBlock]) {
        setBeforeSend(blocks.map(\.block))
    }

    func runBeforeSend(_ record: PostHogLogRecord) -> PostHogLogRecord? {
        beforeSend.run(record)
    }

    @objc override public init() {
        super.init()
    }
}
