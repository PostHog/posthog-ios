//
//  PostHogLogLevel.swift
//  PostHog
//
//  Created by Ioannis Josephides on 09/05/2025.
//

import Foundation

/// Severity level for a captured log entry. Used by both the session-replay
/// console-log subsystem (iOS-only) and the cross-platform logs feature.
///
/// Case order preserves the original public rawValues for `info` (0), `warn`
/// (1), and `error` (2) — those shipped before the enum was extended with
/// `trace`, `debug`, and `fatal`, so any ObjC consumer holding their integer
/// constants stays binary-compatible. Severity comparisons (`>=`) must use
/// `severityNumber`, not `rawValue` — rawValue order is no longer
/// severity-monotonic.
///
/// Maps to OpenTelemetry severity numbers (`TRACE=1`, `DEBUG=5`, `INFO=9`,
/// `WARN=13`, `ERROR=17`, `FATAL=21`) for the OTLP wire format.
@objc(PostHogLogLevel) public enum PostHogLogLevel: Int, CaseIterable {
    /// Informational messages, debugging output, and general logs
    /// (`severityNumber` 9).
    case info
    /// Warning messages indicating potential issues or deprecation notices
    /// (`severityNumber` 13).
    case warn
    /// Error messages indicating failures or critical issues
    /// (`severityNumber` 17).
    case error
    /// Finest-grained tracing detail (`severityNumber` 1).
    case trace
    /// Diagnostic information useful while debugging (`severityNumber` 5).
    case debug
    /// An unrecoverable failure; the app likely cannot continue
    /// (`severityNumber` 21).
    case fatal

    /// Lowercase identifier (e.g. `"info"`) used as the wire-format string.
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

    /// OTLP `severityText` — the lowercase identifier (`"trace"`, `"info"`, …).
    /// The OTLP spec permits any casing; PostHog's logs ingestion normalizes
    /// either, but lowercase keeps the wire payload consistent.
    var severityText: String {
        name
    }

    /// Parse a severity from its canonical lowercase name. Tolerates
    /// surrounding whitespace and casing. Returns `nil` for unknown values.
    static func from(name: String) -> PostHogLogLevel? {
        let normalized = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return PostHogLogLevel.allCases.first { $0.name == normalized }
    }
}
