//
//  PostHogLogLevel.swift
//  PostHog
//
//  Created by Ioannis Josephides on 09/05/2025.
//

#if os(iOS)
    import Foundation

    /// The severity level of a console log entry.
    ///
    /// Used to categorize logs by their severity in session replay.
    @objc public enum PostHogLogLevel: Int {
        /// Informational messages, debugging output, and general logs
        case info
        /// Warning messages indicating potential issues or deprecation notices
        case warn
        /// Error messages indicating failures or critical issues
        case error
    }
#endif
