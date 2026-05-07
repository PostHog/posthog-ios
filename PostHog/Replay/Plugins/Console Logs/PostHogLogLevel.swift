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
/// Use `severityNumber` (or `PostHogLogLevelHelpers` from ObjC) for `>=`-style
/// severity comparisons. Comparing `rawValue` directly will give the wrong
/// order — the cases are not declared in severity order.
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

    /// OTLP `severityNumber` (1, 5, 9, 13, 17, 21). Use this for severity
    /// comparisons — comparing `rawValue` will give the wrong order.
    /// ObjC callers: see `PostHogLogLevelHelpers`.
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

    /// OTLP `severityText` — the lowercase identifier (`"trace"`, `"debug"`,
    /// `"info"`, `"warn"`, `"error"`, `"fatal"`).
    /// ObjC callers: see `PostHogLogLevelHelpers`.
    public var severityText: String {
        name
    }

    /// Parse a severity from its canonical lowercase name. Tolerates
    /// surrounding whitespace and casing. Returns `nil` for unknown values.
    static func from(name: String) -> PostHogLogLevel? {
        let normalized = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return PostHogLogLevel.allCases.first { $0.name == normalized }
    }
}

/// Severity helpers for `PostHogLogLevel` — call from ObjC to get the OTLP
/// severity number or text for a level.
///
/// Use `severityNumberForLevel:` for `>=`-style severity comparisons; comparing
/// the raw enum integer directly will give the wrong order for `trace` /
/// `debug` / `fatal`.
///
/// ```objc
/// NSInteger n = [PostHogLogLevelHelpers severityNumberForLevel:record.level];
/// if (n >= [PostHogLogLevelHelpers severityNumberForLevel:PostHogLogLevelWarn]) {
///     // ...
/// }
/// ```
@objc public final class PostHogLogLevelHelpers: NSObject {
    /// OTLP severity number for `level` (1 = trace, 5 = debug, 9 = info,
    /// 13 = warn, 17 = error, 21 = fatal).
    @objc public static func severityNumber(for level: PostHogLogLevel) -> Int {
        level.severityNumber
    }

    /// OTLP severity text for `level` (`"trace"`, `"debug"`, `"info"`,
    /// `"warn"`, `"error"`, `"fatal"`).
    @objc public static func severityText(for level: PostHogLogLevel) -> String {
        level.severityText
    }
}
