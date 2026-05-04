//
//  PostHogLogsOTLP.swift
//  PostHog
//

import Foundation

/// OpenTelemetry / OTLP-JSON serialization for log records.
///
/// Emits the OTLP `LogsService` request shape
/// (`resourceLogs[].scopeLogs[].logRecords[]`) — distinct from PostHog's
/// internal events batch shape because the logs ingestion endpoint expects OTLP.
///
/// All functions here are pure and synchronous; they do not touch SDK state.
enum PostHogLogsOTLP {
    static let scopeName = postHogiOSSdkName

    /// Wraps a Swift value as an OTLP `AnyValue`. Returns `nil` for values that
    /// have no representable OTLP form (which the caller should drop).
    ///
    /// `Int`, `Int8`...`Int64`, `UInt8`...`UInt32` map to `intValue` (encoded as
    /// a string per proto3 JSON int64 rules). `Double` / `Float` / `CGFloat` map
    /// to `doubleValue` for finite numbers and `stringValue` ("NaN" | "Infinity"
    /// | "-Infinity") otherwise — required because JSON cannot represent those
    /// floats directly.
    static func toAnyValue(_ value: Any) -> [String: Any]? {
        if value is NSNull { return nil }
        if let str = value as? String { return ["stringValue": str] }
        if let bool = value as? Bool { return ["boolValue": bool] }
        if let numeric = numericAnyValue(value) { return numeric }
        if let composite = compositeAnyValue(value) { return composite }
        if let url = value as? URL { return ["stringValue": url.absoluteString] }
        if let date = value as? Date { return ["stringValue": toISO8601String(date)] }
        // Last resort: stringify so the user gets *something* rather than a
        // silently dropped attribute. Matches the JS SDK's behaviour for
        // non-primitive values.
        return ["stringValue": String(describing: value)]
    }

    /// Handles `NSNumber`, `Double`, `Float`, and integer types. Returns `nil`
    /// for non-numeric values so the main dispatcher can keep walking the type
    /// ladder.
    ///
    /// Order matters: `NSNumber` bridges booleans, so the `Bool` check in
    /// `toAnyValue` must run before this helper.
    private static func numericAnyValue(_ value: Any) -> [String: Any]? {
        if let number = value as? NSNumber {
            // Identify floats via the underlying CFNumber type so we don't
            // accidentally serialize a `Double` as an `intValue`.
            switch CFNumberGetType(number) {
            case .floatType, .float32Type, .float64Type, .doubleType, .cgFloatType:
                return doubleAnyValue(number.doubleValue)
            default:
                if let intVal = value as? Int { return ["intValue": String(intVal)] }
                if let int64Val = value as? Int64 { return ["intValue": String(int64Val)] }
                return ["intValue": String(number.int64Value)]
            }
        }
        if let dbl = value as? Double { return doubleAnyValue(dbl) }
        if let flt = value as? Float { return doubleAnyValue(Double(flt)) }
        return nil
    }

    /// Handles arrays and string-keyed dictionaries. Returns `nil` for other
    /// types.
    private static func compositeAnyValue(_ value: Any) -> [String: Any]? {
        if let array = value as? [Any] {
            let mapped = array.compactMap { toAnyValue($0) }
            return ["arrayValue": ["values": mapped]]
        }
        if let dict = value as? [String: Any] {
            return ["kvlistValue": ["values": toKeyValueList(dict)]]
        }
        return nil
    }

    private static func doubleAnyValue(_ value: Double) -> [String: Any] {
        if value.isNaN { return ["stringValue": "NaN"] }
        if value.isInfinite {
            return ["stringValue": value > 0 ? "Infinity" : "-Infinity"]
        }
        return ["doubleValue": value]
    }

    /// Converts `[String: Any]` to an OTLP `KeyValue[]` list, dropping entries
    /// whose values cannot be represented.
    static func toKeyValueList(_ dict: [String: Any]) -> [[String: Any]] {
        var result: [[String: Any]] = []
        result.reserveCapacity(dict.count)
        // Sort keys so the wire output is deterministic — easier on tests and
        // diff-based debugging.
        for key in dict.keys.sorted() {
            // NSNull / nil-bridged values are treated as absent rather than
            // serialized as a literal null — OTLP has no null AnyValue.
            let raw = dict[key]
            guard let raw, !(raw is NSNull) else { continue }
            guard let value = toAnyValue(raw) else { continue }
            result.append(["key": key, "value": value])
        }
        return result
    }

    /// Builds a single OTLP `LogRecord` element from a stored record. Auto-attached
    /// context (distinctId, sessionId, screen.name, app.state, feature_flags) is
    /// merged in *underneath* the user's `attributes` so user-supplied keys win.
    static func buildLogRecord(_ record: PostHogLogRecord) -> [String: Any] {
        var attrs: [String: Any] = [:]
        if let distinctId = record.distinctId { attrs["posthogDistinctId"] = distinctId }
        if let sessionId = record.sessionId { attrs["sessionId"] = sessionId }
        if let screenName = record.screenName { attrs["screen.name"] = screenName }
        if let appState = record.appState { attrs["app.state"] = appState }
        if !record.featureFlagKeys.isEmpty { attrs["feature_flags"] = record.featureFlagKeys }
        // User-supplied attributes overwrite auto-attributes on key collision.
        for (key, value) in record.attributes {
            attrs[key] = value
        }

        var json: [String: Any] = [
            "timeUnixNano": record.timeUnixNano,
            "observedTimeUnixNano": record.observedTimeUnixNano,
            "severityNumber": record.level.severityNumber,
            "severityText": record.level.severityText,
            "body": ["stringValue": record.body],
        ]
        if !attrs.isEmpty {
            json["attributes"] = toKeyValueList(attrs)
        }
        if let traceId = record.traceId { json["traceId"] = traceId }
        if let spanId = record.spanId { json["spanId"] = spanId }
        if let traceFlags = record.traceFlags { json["flags"] = traceFlags }
        return json
    }

    /// Builds the full OTLP request payload (`{ "resourceLogs": [...] }`).
    ///
    /// - Parameters:
    ///   - records: Records to include in this batch.
    ///   - resourceAttributes: Already-merged map (SDK-managed keys overlaid on
    ///     top of the user's `resourceAttributes` config — that merging happens
    ///     in `PostHogLogsQueue` so this function stays pure).
    ///   - scopeVersion: Version string for the OTLP `InstrumentationScope`
    ///     (typically `postHogVersion`).
    static func buildPayload(
        records: [PostHogLogRecord],
        resourceAttributes: [String: Any],
        scopeVersion: String
    ) -> [String: Any] {
        let logRecords = records.map { buildLogRecord($0) }
        return [
            "resourceLogs": [
                [
                    "resource": [
                        "attributes": toKeyValueList(resourceAttributes),
                    ],
                    "scopeLogs": [
                        [
                            "scope": [
                                "name": scopeName,
                                "version": scopeVersion,
                            ],
                            "logRecords": logRecords,
                        ],
                    ],
                ],
            ],
        ]
    }
}
