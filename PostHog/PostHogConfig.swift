//
//  PostHogConfig.swift
//  PostHog
//
//  Created by Ben White on 07.02.23.
//
import Foundation

public typealias BeforeSendBlock = (PostHogEvent) -> PostHogEvent?

@objc public final class BoxedBeforeSendBlock: NSObject {
    @objc public let block: BeforeSendBlock

    @objc(block:)
    public init(block: @escaping BeforeSendBlock) {
        self.block = block
    }
}

@objc(PostHogConfig) public class PostHogConfig: NSObject {
    enum Defaults {
        #if os(tvOS)
            static let flushAt: Int = 5
            static let maxQueueSize: Int = 100
        #else
            static let flushAt: Int = 20
            static let maxQueueSize: Int = 1000
        #endif
        static let maxBatchSize: Int = 50
        static let flushIntervalSeconds: TimeInterval = 30
    }

    @objc(PostHogDataMode) public enum PostHogDataMode: Int {
        case wifi
        case cellular
        case any
    }

    @objc public let host: URL
    @objc public let apiKey: String
    @objc public var flushAt: Int = Defaults.flushAt
    @objc public var maxQueueSize: Int = Defaults.maxQueueSize
    @objc public var maxBatchSize: Int = Defaults.maxBatchSize
    @objc public var flushIntervalSeconds: TimeInterval = Defaults.flushIntervalSeconds
    @objc public var dataMode: PostHogDataMode = .any
    @objc public var sendFeatureFlagEvent: Bool = true
    @objc public var preloadFeatureFlags: Bool = true

    /// Preload PostHog remote config automatically
    /// Default: true
    ///
    /// Note: Surveys rely on remote config. Disabling this will also disable Surveys
    @objc public var remoteConfig: Bool = true

    @objc public var captureApplicationLifecycleEvents: Bool = true
    @objc public var captureScreenViews: Bool = true
    #if os(iOS) || targetEnvironment(macCatalyst)
        /// Enable autocapture for iOS
        /// Default: false
        @objc public var captureElementInteractions: Bool = false
    #endif
    @objc public var debug: Bool = false
    @objc public var optOut: Bool = false
    @objc public var getAnonymousId: ((UUID) -> UUID) = { uuid in uuid }

    /// Flag to reuse the anonymous Id between `reset()` and next `identify()` calls
    ///
    /// If enabled, the anonymous Id will be reused for all anonymous users on this device,
    /// essentially creating a "Guest user Id" as long as this option is enabled.
    ///
    /// Note:
    ///     Events captured *before* call to *identify()* won't be linked to the identified user
    ///     Events captured *after*  call to *reset()* won't be linked to the identified user
    ///
    /// Defaults to false.
    @objc public var reuseAnonymousId: Bool = false

    /// Hook that allows to sanitize the event properties
    /// The hook is called before the event is cached or sent over the wire
    @available(*, deprecated, message: "Use beforeSend instead")
    @objc public var propertiesSanitizer: PostHogPropertiesSanitizer?
    /// Determines the behavior for processing user profiles.
    @objc public var personProfiles: PostHogPersonProfiles = .identifiedOnly

    /// Automatically set common device and app properties as person properties for feature flag evaluation.
    ///
    /// When enabled, the SDK will automatically set the following person properties:
    /// - $app_version: App version from bundle
    /// - $app_build: App build number from bundle
    /// - $os_name: Operating system name (iOS, macOS, etc.)
    /// - $os_version: Operating system version
    /// - $device_type: Device type (Mobile, Tablet, Desktop, etc.)
    /// - $locale: User's current locale
    ///
    /// This helps ensure feature flags that rely on these properties work correctly
    /// without waiting for server-side processing of identify() calls.
    ///
    /// Default: true
    @objc public var setDefaultPersonProperties: Bool = true

    /// The identifier of the App Group that should be used to store shared analytics data.
    /// PostHog will try to get the physical location of the App Group’s shared container, otherwise fallback to the default location
    /// Default: nil
    @objc public var appGroupIdentifier: String?

    /// Internal
    /// Do not modify it, this flag is read and updated by the SDK via feature flags
    @objc public var snapshotEndpoint: String = "/s/"

    /// or EU Host: 'https://eu.i.posthog.com'
    public static let defaultHost: String = "https://us.i.posthog.com"

    #if os(iOS)
        /// Enable Recording of Session Replays for iOS
        /// Default: false
        @objc public var sessionReplay: Bool = false
        /// Session Replay configuration
        @objc public let sessionReplayConfig: PostHogSessionReplayConfig = .init()
    #endif

    /// Enable mobile surveys
    /// Experimental support
    ///
    /// Default: false
    ///
    /// Note: Event triggers will only work with the instance that first enables surveys.
    /// In case of multiple instances, please make sure you are capturing events on the instance that has config.surveys = true
    @available(iOS 15.0, *)
    @available(watchOS, unavailable, message: "Surveys are only available on iOS 15+")
    @available(macOS, unavailable, message: "Surveys are only available on iOS 15+")
    @available(tvOS, unavailable, message: "Surveys are only available on iOS 15+")
    @available(visionOS, unavailable, message: "Surveys are only available on iOS 15+")
    @_spi(Experimental)
    @objc public var surveys: Bool {
        get { _surveys }
        set { setSurveys(newValue) }
    }

    @available(iOS 15.0, *)
    @available(watchOS, unavailable, message: "Surveys are only available on iOS 15+")
    @available(macOS, unavailable, message: "Surveys are only available on iOS 15+")
    @available(tvOS, unavailable, message: "Surveys are only available on iOS 15+")
    @available(visionOS, unavailable, message: "Surveys are only available on iOS 15+")
    @_spi(Experimental)
    @objc public var surveysConfig: PostHogSurveysConfig {
        get { _surveysConfig }
        set { setSurveysConfig(newValue) }
    }

    // only internal
    var disableReachabilityForTesting: Bool = false
    var disableQueueTimerForTesting: Bool = false
    // internal
    public var storageManager: PostHogStorageManager?

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

    /// Returns an array of integrations to be installed based on current configuration
    func getIntegrations() -> [PostHogIntegration] {
        var integrations: [PostHogIntegration] = []

        if captureScreenViews {
            integrations.append(PostHogScreenViewIntegration())
        }

        if captureApplicationLifecycleEvents {
            integrations.append(PostHogAppLifeCycleIntegration())
        }

        #if os(iOS)
            if sessionReplay {
                integrations.append(PostHogReplayIntegration())
            }

            if _surveys {
                integrations.append(PostHogSurveyIntegration())
            }

        #endif

        #if os(iOS) || targetEnvironment(macCatalyst)
            if captureElementInteractions {
                integrations.append(PostHogAutocaptureIntegration())
            }
        #endif

        return integrations
    }

    var _surveys: Bool = false // swiftlint:disable:this identifier_name
    private func setSurveys(_ value: Bool) {
        // protection against objc API availability warning instead of error
        // Unlike swift, which enforces stricter safety rules, objc just displays a warning
        if #available(iOS 15.0, *) {
            _surveys = value
        }
    }

    var _surveysConfig: PostHogSurveysConfig = .init() // swiftlint:disable:this identifier_name
    private func setSurveysConfig(_ value: PostHogSurveysConfig) {
        // protection against objc API availability warning instead of error
        // Unlike swift, which enforces stricter safety rules, objc just displays a warning
        if #available(iOS 15.0, *) {
            _surveysConfig = value
        }
    }

    /// Hook that allows to sanitize the event
    /// The hook is called before the event is cached or sent over the wire
    private var beforeSend: BeforeSendBlock = { $0 }

    private static func buildBeforeSendBlock(_ blocks: [BeforeSendBlock]) -> BeforeSendBlock {
        { event in
            blocks.reduce(event) { event, block in
                event.flatMap(block)
            }
        }
    }

    public func setBeforeSend(_ blocks: [BeforeSendBlock]) {
        beforeSend = Self.buildBeforeSendBlock(blocks)
    }

    public func setBeforeSend(_ blocks: BeforeSendBlock...) {
        setBeforeSend(blocks)
    }

    @available(*, unavailable, message: "Use setBeforeSend(_ blocks: BeforeSendBlock...) instead")
    @objc public func setBeforeSend(_ blocks: [BoxedBeforeSendBlock]) {
        setBeforeSend(blocks.map(\.block))
    }

    func runBeforeSend(_ event: PostHogEvent) -> PostHogEvent? {
        beforeSend(event)
    }
}
