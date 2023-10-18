//
//  PostHogConfig.swift
//  PostHog
//
//  Created by Ben White on 07.02.23.
//
import Foundation

@objc(PostHogConfig) public class PostHogConfig: NSObject {
    @objc(PostHogDataMode) public enum PostHogDataMode: Int {
        case wifi
        case cellular
        case any
    }

    @objc public let host: URL
    @objc public let apiKey: String
    @objc public var flushAt: Int = 20
    @objc public var maxQueueSize: Int = 1000
    @objc public var maxBatchSize: Int = 50
    @objc public var flushIntervalSeconds: TimeInterval = 30
    @objc public var dataMode: PostHogDataMode = .any
    @objc public var sendFeatureFlagEvent: Bool = true
    @objc public var preloadFeatureFlags: Bool = true
    @objc public var debug: Bool = false
    @objc public var optOut: Bool = false
    public static let defaultHost: String = "https://app.posthog.com"
    // TODO: encryption, captureApplicationLifecycleEvents, recordScreenViews, captureInAppPurchases,
    // capturePushNotifications, captureDeepLinks, launchOptions

    public init(
        apiKey: String,
        host: String = defaultHost
    ) {
        self.apiKey = apiKey
        self.host = URL(string: host) ?? URL(string: PostHogConfig.defaultHost)!
    }
}
