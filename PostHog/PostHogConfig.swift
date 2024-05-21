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
    @objc public var captureApplicationLifecycleEvents: Bool = true
    @objc public var captureScreenViews: Bool = true
    @objc public var debug: Bool = false
    @objc public var optOut: Bool = false
    @objc public var getAnonymousId: ((UUID) -> UUID) = { uuid in uuid }
    /// Internal
    var snapshotEndpoint: String = "/s/"

    public static let defaultHost: String = "https://app.posthog.com"

    #if os(iOS)
        /// Enable Recording of Session Replays for iOS
        /// Experimental support
        /// Default: false
        @objc public var sessionReplay: Bool = false
        /// Session Replay configuration
        /// Experimental support
        @objc public let sessionReplayConfig: PostHogSessionReplayConfig = .init()
    #endif

    // only internal
    var disableReachabilityForTesting: Bool = false
    var disableQueueTimerForTesting: Bool = false

    @objc(apiKey:)
    public init(
        apiKey: String
    ) {
        self.apiKey = apiKey
        host = URL(string: PostHogConfig.defaultHost)!
    }

    @objc(apiKey:host:)
    public init(
        apiKey: String,
        host: String = defaultHost
    ) {
        self.apiKey = apiKey
        self.host = URL(string: host) ?? URL(string: PostHogConfig.defaultHost)!
    }
}
