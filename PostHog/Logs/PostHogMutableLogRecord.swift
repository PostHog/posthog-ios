//
//  PostHogMutableLogRecord.swift
//  PostHog
//

import Foundation

/// Mutable view over a captured log record handed to `beforeSend` callbacks.
///
/// Exposes only the redaction-safe fields. Wire-format internals
/// (`timeUnixNano`, `observedTimeUnixNano`, OTLP encoding) are deliberately
/// kept off this surface so callbacks cannot corrupt them.
///
/// Lifetime is one capture: the SDK builds an instance from the internal
/// `PostHogLogRecord`, runs the `beforeSend` chain, and copies the mutated
/// fields back. Holding a reference past the callback has no effect on the
/// enqueued record.
@objc(PostHogMutableLogRecord) public final class PostHogMutableLogRecord: NSObject {
    /// The log message body. Setting this to an empty string drops the record
    /// after `beforeSend` returns.
    @objc public var body: String

    @objc public var level: PostHogLogLevel

    /// Attributes attached to the record. Values must be JSON-serializable;
    /// non-serializable entries are dropped at flush time.
    ///
    /// **From ObjC**: this bridges to an immutable `NSDictionary`. To mutate,
    /// take a `mutableCopy` and assign back to the property — in-place
    /// mutation on the returned dictionary will fail.
    @objc public var attributes: [String: Any]

    /// Optional W3C trace context — 32 hex characters.
    @objc public var traceId: String?

    /// Optional W3C trace context — 16 hex characters.
    @objc public var spanId: String?

    /// Optional W3C trace flags. The lower 8 bits are the W3C bitfield; bit 0
    /// is the `sampled` flag. `nil` means "field absent on the wire".
    @objc public var traceFlags: NSNumber?

    /// User's PostHog distinct id at capture time. `nil` if no user is
    /// identified. Rewrite for redaction.
    @objc public var distinctId: String?

    /// Active PostHog session id at capture time. `nil` if no session is
    /// active.
    @objc public var sessionId: String?

    /// Last-seen screen name at capture time, populated automatically when
    /// screen view tracking is enabled.
    @objc public var screenName: String?

    /// `"foreground"` or `"background"` at capture time.
    @objc public var appState: String?

    /// Keys of feature flags that were active at capture time. Useful for
    /// correlating log records with experiment cohorts; empty when no flags
    /// are loaded. Clear or filter for redaction.
    ///
    /// **From ObjC**: bridges to an immutable `NSArray`. Replace the property
    /// to mutate; in-place mutation on the returned array will fail.
    @objc public var featureFlagKeys: [String]

    init(_ record: PostHogLogRecord) {
        body = record.body
        level = record.level
        attributes = record.attributes
        traceId = record.traceId
        spanId = record.spanId
        traceFlags = record.traceFlags
        distinctId = record.distinctId
        sessionId = record.sessionId
        screenName = record.screenName
        appState = record.appState
        featureFlagKeys = record.featureFlagKeys
        super.init()
    }

    func apply(to record: PostHogLogRecord) {
        record.body = body
        record.level = level
        record.attributes = attributes
        record.traceId = traceId
        record.spanId = spanId
        record.traceFlags = traceFlags
        record.distinctId = distinctId
        record.sessionId = sessionId
        record.screenName = screenName
        record.appState = appState
        record.featureFlagKeys = featureFlagKeys
    }
}
