//
//  PostHogLogRecord.swift
//  PostHog
//

import Foundation

/// A captured log entry passed to your `beforeSend` callback. Mutate the
/// fields below to redact, enrich, or rewrite the record; return `nil` to
/// drop it.
///
/// Instances are created by the SDK at capture time. Mutations made after the
/// callback returns have no effect — the record is encoded into the on-disk
/// queue as soon as `beforeSend` finishes.
@objc public final class PostHogLogRecord: NSObject {
    enum AppState: String {
        case foreground
        case background
    }

    /// The log message body. Required; empty bodies are dropped at capture time.
    @objc public var body: String

    /// Severity of the log entry. Reassign to re-classify (e.g. demote a
    /// noisy `.warn` to `.debug`).
    @objc public var level: PostHogLogSeverity

    /// Free-form attributes attached to this record. Values must be
    /// JSON-serializable (`String`, `Int`, `Double`, `Bool`, arrays/dicts of
    /// the same, `NSNumber`); anything else is silently dropped at flush
    /// time. Use this to add structured context (request ids, build numbers,
    /// experiment buckets) or to remove keys you don't want sent.
    ///
    /// **From ObjC**: bridges to an immutable `NSDictionary`. To mutate, take
    /// a `mutableCopy`, edit it, and assign back to the property — in-place
    /// mutation on the returned dictionary will fail.
    @objc public var attributes: [String: Any]

    /// W3C trace id (32 hex characters) if you've correlated this log with a
    /// distributed trace. `nil` when no trace context is associated. Set or
    /// rewrite for tracing integrations.
    @objc public var traceId: String?

    /// W3C span id (16 hex characters) if this log belongs to a span. `nil`
    /// when no span is active.
    @objc public var spanId: String?

    /// W3C trace flags. Lower 8 bits are the bitfield; bit 0 is the
    /// `sampled` flag. `nil` omits the field on the wire; `0` explicitly
    /// emits zero.
    @objc public var traceFlags: NSNumber?

    /// PostHog distinct id of the user at capture time, or `nil` if no user
    /// is identified. Set to `nil` (or to a hash) to redact.
    @objc public var distinctId: String?

    /// PostHog session id at capture time, or `nil` if no session is active.
    /// Set to `nil` to disassociate the record from the session.
    @objc public var sessionId: String?

    /// Last screen name observed by automatic screen-view tracking, or `nil`
    /// if screen tracking is disabled or no screen has been seen yet. Set to
    /// `nil` (or rewrite) to redact navigation context.
    @objc public var screenName: String?

    var appState: String?

    /// Feature flag keys that were active at capture time. Empty when no
    /// flags are loaded. Useful for correlating logs with experiment
    /// cohorts; clear or filter to redact.
    ///
    /// **From ObjC**: bridges to an immutable `NSArray`. Replace the
    /// property to mutate; in-place mutation will fail.
    @objc public var featureFlagKeys: [String]

    // MARK: - Wire-format internals

    var timeUnixNano: String
    var observedTimeUnixNano: String

    init(
        body: String,
        level: PostHogLogSeverity = .info,
        attributes: [String: Any] = [:],
        traceId: String? = nil,
        spanId: String? = nil,
        traceFlags: NSNumber? = nil,
        timeUnixNano: String? = nil,
        observedTimeUnixNano: String? = nil,
        distinctId: String? = nil,
        sessionId: String? = nil,
        screenName: String? = nil,
        appState: String? = nil,
        featureFlagKeys: [String] = []
    ) {
        self.body = body
        self.level = level
        self.attributes = attributes
        self.traceId = traceId
        self.spanId = spanId
        self.traceFlags = traceFlags
        let now = timeUnixNano ?? nanosNow()
        self.timeUnixNano = now
        self.observedTimeUnixNano = observedTimeUnixNano ?? now
        self.distinctId = distinctId
        self.sessionId = sessionId
        self.screenName = screenName
        self.appState = appState
        self.featureFlagKeys = featureFlagKeys
        super.init()
    }

    // MARK: - Persistence

    // The on-disk shape is internal and decoupled from the OTLP wire format,
    // so the wire format can change without rewriting persisted records.

    func toStorageJSON() -> [String: Any] {
        var json: [String: Any] = [
            "body": body,
            "level": level.name,
            "timeUnixNano": timeUnixNano,
            "observedTimeUnixNano": observedTimeUnixNano,
            "featureFlagKeys": featureFlagKeys,
        ]
        if !attributes.isEmpty {
            json["attributes"] = sanitizeDictionary(attributes) ?? [:]
        }
        if let traceId { json["traceId"] = traceId }
        if let spanId { json["spanId"] = spanId }
        if let traceFlags { json["traceFlags"] = traceFlags }
        if let distinctId { json["distinctId"] = distinctId }
        if let sessionId { json["sessionId"] = sessionId }
        if let screenName { json["screenName"] = screenName }
        if let appState { json["appState"] = appState }
        return json
    }

    static func fromStorageJSON(_ data: Data) -> PostHogLogRecord? {
        guard let json = fromJSONData(data) else {
            return nil
        }
        return fromStorageJSON(json)
    }

    static func fromStorageJSON(_ json: [String: Any]) -> PostHogLogRecord? {
        guard let body = json["body"] as? String else { return nil }
        let levelName = (json["level"] as? String) ?? "info"
        let level = PostHogLogSeverity.from(name: levelName) ?? .info
        let attributes = (json["attributes"] as? [String: Any]) ?? [:]
        let timeUnixNano = (json["timeUnixNano"] as? String) ?? nanosNow()
        let observedTimeUnixNano = (json["observedTimeUnixNano"] as? String) ?? timeUnixNano
        let featureFlagKeys = (json["featureFlagKeys"] as? [String]) ?? []
        return PostHogLogRecord(
            body: body,
            level: level,
            attributes: attributes,
            traceId: json["traceId"] as? String,
            spanId: json["spanId"] as? String,
            traceFlags: json["traceFlags"] as? NSNumber,
            timeUnixNano: timeUnixNano,
            observedTimeUnixNano: observedTimeUnixNano,
            distinctId: json["distinctId"] as? String,
            sessionId: json["sessionId"] as? String,
            screenName: json["screenName"] as? String,
            appState: json["appState"] as? String,
            featureFlagKeys: featureFlagKeys
        )
    }
}
