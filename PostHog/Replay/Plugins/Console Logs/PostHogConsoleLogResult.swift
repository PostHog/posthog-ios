//
//  PostHogConsoleLogResult.swift
//  PostHog
//
//  Created by Ioannis Josephides on 09/05/2025.
//

#if os(iOS)
    import Foundation

    /**
     A model representing a processed console log entry for session replay.

     Describes a single console log entry after it has been processed by `PostHogSessionReplayConsoleLogConfig.processConsoleOutput`.
     Each instance contains the log message content and its determined severity level.
     */
    @objc public class PostHogConsoleLogResult: NSObject {
        /// The severity level of the log entry.
        /// This determines how the log will be displayed in the session replay and
        /// whether it will be captured based on `minimumLogLevel` setting.
        @objc public let level: PostHogConsoleLogLevel

        /// The actual content of the log message.
        /// This is the processed and sanitized log message
        @objc public let message: String

        /// Creates a new console log result.
        /// - Parameters:
        ///   - level: The severity level of the log entry
        ///   - message: The processed log message content
        @objc public init(level: PostHogConsoleLogLevel, message: String) {
            self.level = level
            self.message = message
            super.init()
        }
    }
#endif
