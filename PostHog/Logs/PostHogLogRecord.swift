//
//  PostHogLogRecord.swift
//  PostHog
//

import Foundation

/// A single log entry queued for delivery to PostHog.
///
/// Records are produced by `captureLog` (or `logger.<level>`), persisted to disk
/// via `PostHogLogsQueue`, and serialized as OpenTelemetry log records on the wire.
///
/// `PostHogLogRecord` is a value type so user-supplied `beforeSend` callbacks can
/// mutate a local copy and return a transformed instance without affecting the
/// queued record before it has been processed.
public struct PostHogLogRecord {
    /// The log message body. Required; empty bodies are dropped at capture time.
    public var body: String

    /// Severity level. Defaults to `.info`.
    public var level: PostHogLogSeverity

    /// Optional attributes attached to the record. Values must be JSON-serializable;
    /// `nil` values are filtered out before sending.
    public var attributes: [String: Any]

    /// Optional W3C trace context — 32 hex characters.
    public var traceId: String?

    /// Optional W3C trace context — 16 hex characters.
    public var spanId: String?

    /// Optional W3C trace flags.
    public var traceFlags: Int?

    /// Capture-time wall clock in nanoseconds since Unix epoch, encoded as a
    /// string per OTLP/JSON. Snapshotted at capture so identity / session
    /// changes between capture and flush cannot corrupt the record.
    public var timeUnixNano: String

    /// Equal to `timeUnixNano` for in-process synchronous capture; the OTLP
    /// shape carries both fields so we populate both.
    public var observedTimeUnixNano: String

    // MARK: - Per-capture context snapshot

    //
    // These fields are filled in by the caller (PostHogSDK) at capture time. The
    // logs queue itself does not read SDK state, so a record carries everything
    // needed to be sent independently of when the flush actually happens.

    public var distinctId: String?
    public var sessionId: String?
    public var screenName: String?
    public var appState: String?
    public var featureFlagKeys: [String]

    public init(
        body: String,
        level: PostHogLogSeverity = .info,
        attributes: [String: Any] = [:],
        traceId: String? = nil,
        spanId: String? = nil,
        traceFlags: Int? = nil,
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
        let now = timeUnixNano ?? PostHogLogRecord.nanosNow()
        self.timeUnixNano = now
        self.observedTimeUnixNano = observedTimeUnixNano ?? now
        self.distinctId = distinctId
        self.sessionId = sessionId
        self.screenName = screenName
        self.appState = appState
        self.featureFlagKeys = featureFlagKeys
    }
    /// Current wall clock as a uint64 nanosecond string. OTLP/JSON encodes
    /// uint64 as a string because JSON numbers cannot represent uint64 precisely.
    public static func nanosNow() -> String {
        let secs = Date().timeIntervalSince1970
        // Avoid Double precision loss at large magnitudes by splitting into
        // whole seconds + nanos within the second.
        let whole = UInt64(secs)
        let frac = secs - Double(whole)
        let nanosInSecond = UInt64(frac * 1_000_000_000)
        return "\(whole * 1_000_000_000 + nanosInSecond)"
    }

    // MARK: - Persistence

    //
    // Records are persisted to disk via PostHogFileBackedQueue, so they need to
    // round-trip through a JSON representation. We keep the on-disk shape internal
    // (it is not the OTLP wire shape) — the queue rebuilds the OTLP payload at
    // flush time so we can change the wire format without rewriting persisted
    // records.

    func toStorageJSON() -> [String: Any] {
        var json: [String: Any] = [
            "body": body,
            "level": level.name,
            "timeUnixNano": timeUnixNano,
            "observedTimeUnixNano": observedTimeUnixNano,
            "featureFlagKeys": featureFlagKeys,
        ]
        if !attributes.isEmpty {
            // Drop unserializable values defensively. sanitizeDictionary treats nil
            // entries as empty input, so we only call it when we have content.
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
        guard let json = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any] else {
            return nil
        }
        return fromStorageJSON(json)
    }

    static func fromStorageJSON(_ json: [String: Any]) -> PostHogLogRecord? {
        guard let body = json["body"] as? String else { return nil }
        let levelName = (json["level"] as? String) ?? "info"
        let level = PostHogLogSeverity.from(name: levelName) ?? .info
        let attributes = (json["attributes"] as? [String: Any]) ?? [:]
        let timeUnixNano = (json["timeUnixNano"] as? String) ?? PostHogLogRecord.nanosNow()
        let observedTimeUnixNano = (json["observedTimeUnixNano"] as? String) ?? timeUnixNano
        let featureFlagKeys = (json["featureFlagKeys"] as? [String]) ?? []
        return PostHogLogRecord(
            body: body,
            level: level,
            attributes: attributes,
            traceId: json["traceId"] as? String,
            spanId: json["spanId"] as? String,
            traceFlags: json["traceFlags"] as? Int,
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
