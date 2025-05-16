//
//  PostHogSessionReplayConsoleLogConfig.swift
//  PostHog
//
//  Created by Ioannis Josephides on 09/05/2025.
//

#if os(iOS)
    import Foundation

    @objc public class PostHogSessionReplayConsoleLogConfig: NSObject {
        /// Block to process and format captured console output for session replay.
        ///
        /// This block is called whenever console output is captured. It allows you to:
        /// 1. Filter or modify log messages before they are sent to session replay
        /// 2. Determine the appropriate log level (info/warn/error) for each message
        /// 3. Format, sanitize or skip a log messages (e.g. remove sensitive data or PII)
        ///
        /// The default implementation:
        /// - Detect log level (best effort)
        /// - Process OSLog messages to remove metadata
        ///
        /// - Parameter output: The raw console output to process
        /// - Returns: Array of `PostHogConsoleLogResult` objects, one for each processed log entry. Return an empty array to skip a log output
        @objc public var logSanitizer: ((String) -> PostHogLogEntry?) = PostHogSessionReplayConsoleLogConfig.defaultLogSanitizer

        /// The minimum log level to capture in session replay.
        /// Only log messages with this level or higher will be captured.
        /// For example, if set to `.warn`:
        /// - `.error` messages will be captured
        /// - `.warn` messages will be captured
        /// - `.info` messages will be skipped
        ///
        /// Defaults to `.error` to minimize noise in session replays.
        @objc public var minLogLevel: PostHogLogLevel = .error

        /// Default implementation for processing console output.
        static func defaultLogSanitizer(_ message: String) -> PostHogLogEntry? {
            let message = String(message)
            // Determine console log level
            let level: PostHogLogLevel = {
                if message.range(of: logMessageWarningPattern, options: .regularExpression) != nil { return .warn }
                if message.range(of: logMessageErrorPattern, options: .regularExpression) != nil { return .error }
                return .info
            }()

            // For OSLog messages, extract just the log message part
            let sanitizedMessage = message.contains("OSLOG-") ? {
                if let tabIndex = message.lastIndex(of: "\t") {
                    return String(message[message.index(after: tabIndex)...])
                }
                return message
            }() : message

            return PostHogLogEntry(level: level, message: sanitizedMessage)
        }

        /// Default regular expression pattern used to identify error-level log messages.
        ///
        /// By default, it matches common error indicators such as:
        /// - The word "error", "exception", "fail" or "failed"
        /// - OSLog messages with type "Error" or "Fault"
        private static let logMessageErrorPattern = "(error|exception|fail(ed)?|OSLOG-.*type:\"Error\"|OSLOG-.*type:\"Fault\")"

        /// Default regular expression pattern used to identify warning-level log messages.
        ///
        /// By default, it matches common warning indicators such as:
        /// - The words "warning", "warn", "caution", or "deprecated"
        /// - OSLog messages with type "Warning"
        ///
        private static let logMessageWarningPattern = "(warn(ing)?|caution|deprecated|OSLOG-.*type:\"Warning\")"
    }
#endif
