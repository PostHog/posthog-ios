//
//  PostHogConsoleLogResult.swift
//  PostHog
//
//  Created by Ioannis Josephides on 09/05/2025.
//

import Foundation

@objc public class PostHogConsoleLogResult: NSObject {
    @objc public let level: PostHogConsoleLogLevel
    @objc public let message: String

    @objc public init(level: PostHogConsoleLogLevel, message: String) {
        self.level = level
        self.message = message
        super.init()
    }
}
