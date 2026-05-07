//
//  PostHogLogSeverity.swift
//  PostHog
//

import Foundation

/// Severity level for a captured log record sent to PostHog's logs ingestion.
///
/// Cases are declared in severity order so `>=` comparisons on the raw value
/// give the expected result from both Swift and ObjC. ObjC consumers can
/// safely write `if (record.severity >= PostHogLogSeverityWarn) { ... }`.
///
/// Maps to OpenTelemetry severity numbers (`TRACE=1`, `DEBUG=5`, `INFO=9`,
/// `WARN=13`, `ERROR=17`, `FATAL=21`) for the OTLP wire format.
@objc public enum PostHogLogSeverity: Int, CaseIterable {
    /// Finest-grained tracing detail.
    case trace
    /// Diagnostic information useful while debugging.
    case debug
    /// Informational messages and general logs.
    case info
    /// Warning messages indicating potential issues or deprecation notices.
    case warn
    /// Error messages indicating failures or critical issues.
    case error
    /// An unrecoverable failure; the app likely cannot continue.
    case fatal

    /// Lowercase identifier used as the wire-format string and disk codec key.
    var name: String {
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
    var severityNumber: Int {
        switch self {
        case .trace: return 1
        case .debug: return 5
        case .info: return 9
        case .warn: return 13
        case .error: return 17
        case .fatal: return 21
        }
    }

    /// OTLP `severityText` — the lowercase identifier (`"trace"`, `"debug"`,
    /// `"info"`, `"warn"`, `"error"`, `"fatal"`).
    var severityText: String {
        name
    }

    /// Parse a severity from its canonical lowercase name. Tolerates
    /// surrounding whitespace and casing. Returns `nil` for unknown values.
    static func from(name: String) -> PostHogLogSeverity? {
        let normalized = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return PostHogLogSeverity.allCases.first { $0.name == normalized }
    }
}
