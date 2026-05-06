//
//  PostHogLogSeverity.swift
//  PostHog
//

import Foundation

/// Severity level for a captured log record. Maps to OpenTelemetry severity
/// numbers (TRACE=1, DEBUG=5, INFO=9, WARN=13, ERROR=17, FATAL=21).
///
/// Named `PostHogLogSeverity` rather than `PostHogLogLevel` to avoid colliding
/// with the iOS-only `PostHogLogLevel` used by the session-replay console
/// capture plugin.
@objc(PostHogLogSeverity) public enum PostHogLogSeverity: Int, CaseIterable {
    /// Finest-grained tracing detail (`severityNumber` 1).
    case trace
    /// Diagnostic information useful while debugging (`severityNumber` 5).
    case debug
    /// Default level for regular runtime events (`severityNumber` 9).
    case info
    /// Something unexpected, but the operation continued (`severityNumber` 13).
    case warn
    /// An operation failed; the app may continue (`severityNumber` 17).
    case error
    /// An unrecoverable failure; the app likely cannot continue (`severityNumber` 21).
    case fatal

    /// Lowercase identifier (e.g. `"info"`) used as the wire-format string and
    /// by the public API.
    public var name: String {
        switch self {
        case .trace: return "trace"
        case .debug: return "debug"
        case .info: return "info"
        case .warn: return "warn"
        case .error: return "error"
        case .fatal: return "fatal"
        }
    }

    /// OTLP `severityNumber` (1, 5, 9, 13, 17, 21).
    public var severityNumber: Int {
        switch self {
        case .trace: return 1
        case .debug: return 5
        case .info: return 9
        case .warn: return 13
        case .error: return 17
        case .fatal: return 21
        }
    }

    /// OTLP `severityText` (uppercase identifier).
    public var severityText: String {
        name.uppercased()
    }

    /// Parse a severity from its canonical lowercase name. Tolerates surrounding
    /// whitespace and casing. Returns `nil` for unknown values.
    public static func from(name: String) -> PostHogLogSeverity? {
        let normalized = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return PostHogLogSeverity.allCases.first { $0.name == normalized }
    }
}
