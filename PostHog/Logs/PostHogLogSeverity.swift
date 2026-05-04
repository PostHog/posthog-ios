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
@objc(PostHogLogSeverity) public enum PostHogLogSeverity: Int {
    case trace
    case debug
    case info
    case warn
    case error
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
        switch self {
        case .trace: return "TRACE"
        case .debug: return "DEBUG"
        case .info: return "INFO"
        case .warn: return "WARN"
        case .error: return "ERROR"
        case .fatal: return "FATAL"
        }
    }

    /// Parse a severity from its lowercase string form. Returns `nil` for unknown values.
    public static func from(name: String) -> PostHogLogSeverity? {
        switch name.lowercased() {
        case "trace": return .trace
        case "debug": return .debug
        case "info": return .info
        case "warn", "warning": return .warn
        case "error": return .error
        case "fatal", "critical": return .fatal
        default: return nil
        }
    }
}
