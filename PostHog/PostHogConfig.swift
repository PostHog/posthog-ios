//
//  PostHogConfig.swift
//  PostHog
//
//  Created by Ben White on 07.02.23.
//
import Foundation

/// Callback invoked before an event is persisted or sent.
///
/// Return the event (mutated or unchanged) to continue processing, or `nil` to drop it.
/// Blocks run synchronously on the capture caller's thread and compose in registration order.
///
/// - Parameter event: The event about to be queued.
/// - Returns: The event to queue, or `nil` to drop it.
public typealias BeforeSendBlock = (PostHogEvent) -> PostHogEvent?

/// Runtime configuration for a `PostHogSDK` instance.
///
/// Create a config with your project token, mutate any options you need, then pass it to
/// `PostHogSDK.shared.setup(_:)` or `PostHogSDK.with(_:)`. Options that control queues,
/// integrations, or resource attributes should be set before setup; later mutations may not
/// affect already-installed SDK components.
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
        static let maxRetries: Int = 3
        static let featureFlagRequestMaxRetries: Int = 1
    }

    /// Network connectivity mode required before queued data may be flushed.
    @objc(PostHogDataMode) public enum PostHogDataMode: Int {
        /// Flush only while the device is connected to Wi-Fi.
        case wifi
        /// Legacy cellular mode.
        ///
        /// Currently behaves the same as `.any`; only `.wifi` applies a stricter flush restriction.
        case cellular
        /// Flush while any network connection is available.
        case any
    }

    /// PostHog ingestion host used for all SDK network requests.
    ///
    /// Defaults to `PostHogConfig.defaultHost` when the initializer host is empty or invalid.
    @objc public let host: URL

    /// Your PostHog project token.
    ///
    /// You can find it at:
    /// https://us.posthog.com/settings/project-details#variables
    ///
    /// This field was formerly named `apiKey`.
    @objc public let projectToken: String

    /// Obsolete alias for `projectToken`.
    @available(*, deprecated, message: "Use projectToken instead. This will be removed in the next major version.")
    @objc public var apiKey: String {
        hedgeLog("apiKey is deprecated and will be removed in the next major version. Use projectToken instead.")
        return projectToken
    }
    /// Number of queued events that triggers an automatic flush.
    ///
    /// Lower values send data sooner but can increase battery and network usage.
    /// Default: `20` (`5` on tvOS).
    @objc public var flushAt: Int = Defaults.flushAt

    /// Maximum number of events kept in the on-disk queue before older events are dropped.
    ///
    /// Default: `1000` (`100` on tvOS).
    @objc public var maxQueueSize: Int = Defaults.maxQueueSize

    /// Maximum number of events included in a single batch request.
    ///
    /// Default: `50`.
    @objc public var maxBatchSize: Int = Defaults.maxBatchSize

    /// Interval, in seconds, between periodic queue flush checks.
    ///
    /// Lower values deliver events closer to real time but can increase battery usage.
    /// Default: `30`.
    @objc public var flushIntervalSeconds: TimeInterval = Defaults.flushIntervalSeconds

    /// Maximum number of consecutive flush attempts before the entire queue is
    /// dropped to avoid infinite retries against a permanently-broken backend.
    /// Increments on every retriable failure including HTTP 413 cap halving;
    /// resets on a successful 2xx response. Default 3.
    @objc public var maxRetries: Int = Defaults.maxRetries

    /// Maximum number of retries for feature flag requests after transient network errors or retryable HTTP responses.
    /// Defaults to 1. Set to 0 to disable feature flag request retries.
    @objc public var featureFlagRequestMaxRetries: Int = Defaults.featureFlagRequestMaxRetries
    /// Required network connectivity mode for flushing queued data.
    ///
    /// Only `.wifi` currently restricts flushing; `.cellular` behaves the same as `.any`.
    /// Default: `.any`.
    @objc public var dataMode: PostHogDataMode = .any

    /// Whether feature flag lookups automatically capture `$feature_flag_called` events.
    ///
    /// Individual lookup calls can override this value with their `sendFeatureFlagEvent` parameter.
    /// Default: `true`.
    @objc public var sendFeatureFlagEvent: Bool = true

    /// Whether feature flags are loaded automatically during SDK setup.
    ///
    /// Default: `true`.
    @objc public var preloadFeatureFlags: Bool = true

    /// Deprecated no-op for remote config loading.
    ///
    /// Remote config is now always loaded; setting this property has no effect.
    ///
    /// - Deprecated: Remote config is always loaded. This option will be removed in a future version.
    @available(*, deprecated, message: "Remote config is now always loaded. This option is a no-op and will be removed in a future version.")
    @objc public var remoteConfig: Bool {
        get { true }
        set {
            if !newValue {
                hedgeLog("remoteConfig is deprecated and is now always enabled. Setting it to false has no effect.")
            }
        }
    }

    /// Whether the SDK automatically captures application lifecycle events.
    ///
    /// When enabled, the SDK records events such as `Application Installed`,
    /// `Application Updated`, `Application Opened`, and background/foreground transitions.
    /// Default: `true`.
    @objc public var captureApplicationLifecycleEvents: Bool = true

    /// Automatically captures a `$screen` event whenever a `UIViewController` appears
    /// (via `viewDidAppear` swizzling).
    ///
    /// `$screen_name` stamping on subsequent events is a related effect: any
    /// successful `screen()` call — whether fired by this auto-capture path **or
    /// invoked manually** via `PostHogSDK.shared.screen(...)` — caches the screen
    /// name so it lands as `$screen_name` on every later event the SDK captures.
    /// To opt out of `$screen_name` stamping entirely, set this to `false` **and**
    /// avoid calling `screen(...)` manually.
    ///
    /// Default: `true`
    @objc public var captureScreenViews: Bool = true

    /// Enable method swizzling for SDK functionality that depends on it
    ///
    /// When disabled, functionality that require swizzling (like autocapture, screen views, session replay, surveys) will not be installed.
    ///
    /// Note: Disabling swizzling will limit session rotation logic to only detect application open and background events.
    /// Session rotation will still work, just with reduced granularity for detecting user activity.
    ///
    /// Default: true
    @objc public var enableSwizzling: Bool = true

    #if os(iOS) || os(macOS)
        /// Automatically register the device's APNs token with PostHog by swizzling
        /// `application(_:didRegisterForRemoteNotificationsWithDeviceToken:)`, so Workflows can
        /// deliver push notifications.
        ///
        /// - Note: Requires `enableSwizzling` to be `true`. To register tokens without swizzling, call
        ///   `PostHogSDK.registerPushNotificationToken(_:)` from your own
        ///   `application(_:didRegisterForRemoteNotificationsWithDeviceToken:)` implementation.
        ///   Registration is iOS-only in this version.
        ///
        /// Default: true. Set to `false` to opt out.
        @objc public var capturePushNotificationSubscriptions: Bool = true

        /// Automatically capture a `$push_notification_opened` event when the user taps a notification,
        /// by swizzling `UNUserNotificationCenterDelegate`.
        ///
        /// - Note: Requires `enableSwizzling` to be `true`. To capture opens without swizzling, call
        ///   `PostHogSDK.capturePushNotificationOpened(response:)` from your own
        ///   `userNotificationCenter(_:didReceive:withCompletionHandler:)` implementation.
        ///
        /// Default: true. Set to `false` to opt out.
        @objc public var capturePushNotificationOpened: Bool = true
    #endif

    #if os(iOS) || targetEnvironment(macCatalyst)
        /// Enables UIKit element interaction autocapture on iOS and Mac Catalyst.
        ///
        /// Requires `enableSwizzling = true`.
        /// Default: `false`.
        @objc public var captureElementInteractions: Bool = false

        /// Rage click detection configuration.
        @objc public let rageClickConfig: PostHogRageClickConfig = .init()
    #endif

    /// Enables verbose SDK diagnostic logging.
    ///
    /// Default: `false`.
    @objc public var debug: Bool = false

    /// Starts the SDK in an opted-out state when set before setup.
    ///
    /// While opted out, capture calls are ignored and integrations are not installed.
    /// Use `PostHogSDK.optIn()` and `PostHogSDK.optOut()` to change the persisted state at runtime.
    /// Default: `false`.
    @objc public var optOut: Bool = false

    /// Hook used to customize newly generated anonymous IDs.
    ///
    /// The SDK passes its generated UUID v7 and stores the UUID returned by this closure.
    /// Existing stored anonymous IDs are not regenerated.
    ///
    /// - Parameter uuid: The SDK-generated anonymous UUID.
    /// - Returns: The UUID to persist as the anonymous ID.
    @objc public var getAnonymousId: ((UUID) -> UUID) = { uuid in uuid }

    /// Pre-seeded identity and feature-flag state applied during setup, before any
    /// network request completes.
    ///
    /// Set this before calling `setup(_:)` so events captured synchronously during
    /// initialization (`Application Installed` / `Application Updated`, pre-identify
    /// lifecycle events) carry a caller-controlled `$distinct_id` rather than the
    /// SDK-generated UUID, and so feature flag reads return caller-provided values
    /// before the first `/flags` response. Mirrors the [`bootstrap` option in `posthog-js`](https://posthog.com/docs/feature-flags/bootstrapping).
    ///
    /// Identity is seeded on a fresh install. For a returning user, an identified bootstrap
    /// (`isIdentifiedId == true`) reconciles against the stored identity — upgrading a
    /// matching anonymous ID to identified, merging a differing anonymous user into the
    /// bootstrapped ID, or preserving a different already-identified user. An anonymous
    /// bootstrap is ignored once an anonymous ID is persisted.
    ///
    /// Feature flags are applied on every initialization and take precedence over the
    /// persisted flag cache. They are a temporary base layer: the first complete `/flags`
    /// response replaces them entirely, while a partial or errored response overlays only
    /// the keys it recomputed.
    ///
    /// Defaults to `nil` (use the SDK-generated UUID and no bootstrapped flags).
    @objc public var bootstrap: PostHogBootstrapConfig?

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

    private var _propertiesSanitizer: PostHogPropertiesSanitizer?
    var legacyPropertiesSanitizer: PostHogPropertiesSanitizer? {
        _propertiesSanitizer
    }

    /// Hook that allows to sanitize the event properties
    /// The hook is called before the event is cached or sent over the wire
    @available(*, deprecated, message: "Use beforeSend instead")
    @objc public var propertiesSanitizer: PostHogPropertiesSanitizer? {
        get { _propertiesSanitizer }
        set { _propertiesSanitizer = newValue }
    }
    /// Determines the behavior for processing user profiles.
    @objc public var personProfiles: PostHogPersonProfiles = .identifiedOnly

    /// Automatically set common device and app properties as person properties for feature flag evaluation.
    ///
    /// When enabled, the SDK will automatically set the following person properties:
    /// - $app_version: App version from bundle
    /// - $app_build: App build number from bundle
    /// - $app_namespace: App bundle identifier
    /// - $os_name: Operating system name (iOS, macOS, etc.)
    /// - $os_version: Operating system version
    /// - $device_type: Device type (Mobile, Tablet, Desktop, etc.)
    /// - $lib: SDK name
    /// - $lib_version: SDK version
    ///
    /// This helps ensure feature flags that rely on these properties work correctly
    /// without waiting for server-side processing of identify() calls.
    ///
    /// Default: true
    @objc public var setDefaultPersonProperties: Bool = true

    /// Evaluation contexts for feature flags.
    ///
    /// When configured, only feature flags that have at least one matching evaluation tag
    /// will be evaluated. Feature flags with no evaluation tags will always be evaluated
    /// for backward compatibility.
    ///
    /// Example usage:
    /// ```swift
    /// config.evaluationContexts = ["production", "web", "checkout"]
    /// ```
    ///
    /// This helps ensure feature flags are only evaluated in the appropriate contexts
    /// for your SDK instance.
    ///
    /// Default: nil (all flags are evaluated)
    @objc public var evaluationContexts: [String]?

    /// Deprecated alias for `evaluationContexts`.
    ///
    /// - Deprecated: Use `evaluationContexts` instead. This property will be removed in a future version.
    @available(*, deprecated, message: "Use evaluationContexts instead. This property will continue to work but will be removed in a future version.")
    @objc public var evaluationEnvironments: [String]? {
        get { evaluationContexts }
        set {
            if newValue != nil {
                hedgeLog("evaluationEnvironments is deprecated. Use evaluationContexts instead.")
            }
            evaluationContexts = newValue
        }
    }

    /// The identifier of the App Group that should be used to store shared analytics data.
    /// PostHog will try to get the physical location of the App Group’s shared container, otherwise fallback to the default location
    /// Default: nil
    @objc public var appGroupIdentifier: String?

    /// Session replay snapshot endpoint path.
    ///
    /// - Warning: This value is managed by the SDK from remote configuration and should not
    ///   be changed by application code.
    @objc public var snapshotEndpoint: String = "/s/"

    /// Default PostHog ingestion host for US Cloud projects.
    ///
    /// Use `"https://eu.i.posthog.com"` for EU Cloud projects.
    public static let defaultHost: String = "https://us.i.posthog.com"

    #if os(iOS)
        /// When set, PostHog injects tracing headers into `URLSession` requests whose
        /// destination hostname exactly matches one of the configured hostnames.
        ///
        /// Injected headers on iOS:
        /// - `X-POSTHOG-DISTINCT-ID`
        /// - `X-POSTHOG-SESSION-ID`
        ///
        /// Notes:
        /// - Requires `enableSwizzling = true`
        /// - Hostname matching is exact and does not include ports or subdomain wildcards
        /// - iOS does not send `X-POSTHOG-WINDOW-ID` because mobile apps do not have a per-window/tab concept
        /// - Existing values for these headers will be overwritten
        @objc public var tracingHeaders: [String]?

        /// Enable Recording of Session Replays for iOS
        ///
        /// Note: Ingestion controls (sampling, feature flags, and event triggers) are currently applied using AND logic.
        /// All configured conditions must be satisfied for recording to start.
        ///
        /// Default: false
        @objc public var sessionReplay: Bool = false
        /// Session Replay configuration
        @objc public let sessionReplayConfig: PostHogSessionReplayConfig = .init()
    #endif

    /// Configuration for error tracking.
    ///
    /// See known limitations: https://posthog.com/docs/error-tracking/installation/ios#limitations
    @objc public let errorTrackingConfig: PostHogErrorTrackingConfig = .init()

    /// Configuration for the logs subsystem (manual `captureLog` capture).
    /// Mutate fields on `config.logs` before calling `PostHogSDK.setup(_:)`.
    @objc public let logs: PostHogLogsConfig = .init()

    /// Enable mobile surveys
    ///
    /// Default: true
    ///
    /// Note: Event triggers will only work with the instance that first enables surveys.
    /// In case of multiple instances, please make sure you are capturing events on the instance that has config.surveys = true
    @available(iOS 15.0, *)
    @available(watchOS, unavailable, message: "Surveys are only available on iOS 15+")
    @available(macOS, unavailable, message: "Surveys are only available on iOS 15+")
    @available(tvOS, unavailable, message: "Surveys are only available on iOS 15+")
    @available(visionOS, unavailable, message: "Surveys are only available on iOS 15+")
    @objc public var surveys: Bool {
        get { _surveys }
        set { setSurveys(newValue) }
    }

    /// Configuration for mobile survey presentation and localization.
    ///
    /// Mutate fields on `config.surveysConfig` or replace this object before calling setup.
    /// Available on iOS 15 and later.
    @available(iOS 15.0, *)
    @available(watchOS, unavailable, message: "Surveys are only available on iOS 15+")
    @available(macOS, unavailable, message: "Surveys are only available on iOS 15+")
    @available(tvOS, unavailable, message: "Surveys are only available on iOS 15+")
    @available(visionOS, unavailable, message: "Surveys are only available on iOS 15+")
    @objc public var surveysConfig: PostHogSurveysConfig {
        get { _surveysConfig }
        set { setSurveysConfig(newValue) }
    }

    /// Optional custom URLSessionConfiguration for network requests
    /// If not set, uses URLSessionConfiguration.default
    /// Useful for testing, proxying, or custom network configurations
    @objc public var urlSessionConfiguration: URLSessionConfiguration?

    /// Custom headers to send with every request to the PostHog API.
    /// Useful for reverse-proxy setups that require authentication, e.g. an `Authorization` header.
    /// Read once when the SDK is set up; changes after setup are ignored.
    @objc public var requestHeaders: [String: String]?

    // only internal
    var disableReachabilityForTesting: Bool = false
    var disableQueueTimerForTesting: Bool = false
    var disableFlushOnBackgroundForTesting: Bool = false
    var disableRemoteConfigForTesting: Bool = false
    /// Storage manager used by this configuration.
    ///
    /// - Warning: This is an SDK extension point used internally to share identity storage
    ///   with SDK integrations and tests. Application code should not normally replace it.
    public var storageManager: PostHogStorageManager?

    private static func normalizeProjectToken(_ projectToken: String) -> String {
        projectToken.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Creates a configuration using the default PostHog host.
    ///
    /// - Parameter projectToken: Your PostHog project token. Leading and trailing whitespace is trimmed.
    @objc(projectToken:)
    public init(
        projectToken: String
    ) {
        self.projectToken = Self.normalizeProjectToken(projectToken)
        host = URL(string: PostHogConfig.defaultHost)!
    }

    /// Creates a configuration with an explicit PostHog ingestion host.
    ///
    /// - Parameters:
    ///   - projectToken: Your PostHog project token. Leading and trailing whitespace is trimmed.
    ///   - host: PostHog ingestion host, for example `"https://us.i.posthog.com"` or
    ///     `"https://eu.i.posthog.com"`. Empty or invalid values fall back to `defaultHost`.
    @objc(projectToken:host:)
    public init(
        projectToken: String,
        host: String = defaultHost
    ) {
        let normalizedHost = host.trimmingCharacters(in: .whitespacesAndNewlines)

        self.projectToken = Self.normalizeProjectToken(projectToken)
        self.host = URL(string: normalizedHost.isEmpty ? PostHogConfig.defaultHost : normalizedHost) ?? URL(string: PostHogConfig.defaultHost)!
    }

    /// Creates a configuration using the deprecated `apiKey` name.
    ///
    /// - Parameter apiKey: Your PostHog project token.
    /// - Deprecated: Use `init(projectToken:)` instead.
    @available(*, deprecated, message: "Use init(projectToken:) instead. This will be removed in the next major version.")
    @objc(apiKey:)
    public convenience init(
        apiKey: String
    ) {
        hedgeLog("apiKey is deprecated and will be removed in the next major version. Use projectToken instead.")
        self.init(projectToken: apiKey)
    }

    /// Creates a configuration using the deprecated `apiKey` name and an explicit host.
    ///
    /// - Parameters:
    ///   - apiKey: Your PostHog project token.
    ///   - host: PostHog ingestion host. Empty or invalid values fall back to `defaultHost`.
    /// - Deprecated: Use `init(projectToken:host:)` instead.
    @available(*, deprecated, message: "Use init(projectToken:host:) instead. This will be removed in the next major version.")
    @objc(apiKey:host:)
    public convenience init(
        apiKey: String,
        host: String = defaultHost
    ) {
        hedgeLog("apiKey is deprecated and will be removed in the next major version. Use projectToken instead.")
        self.init(projectToken: apiKey, host: host)
    }

    /// Returns an array of integrations to be installed based on current configuration
    func getIntegrations() -> [PostHogIntegration] {
        var integrations: [PostHogIntegration] = []

        #if os(iOS) || os(macOS) || os(tvOS)
            if errorTrackingConfig.autoCapture {
                integrations.append(PostHogErrorTrackingAutoCaptureIntegration())
            }
        #endif

        if captureScreenViews {
            integrations.append(PostHogScreenViewIntegration())
        }

        if captureApplicationLifecycleEvents {
            integrations.append(PostHogAppLifeCycleIntegration())
        }

        #if os(iOS)
            if tracingHeaders?.isEmpty == false {
                integrations.append(PostHogTracingHeadersIntegration())
            }

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

            if rageClickConfig.enabled {
                integrations.append(PostHogRageClickIntegration())
            }
        #endif

        #if os(iOS) || os(macOS)
            if #available(iOS 14.0, macOS 11.0, *) {
                // Token registration is iOS-only in v1 (the backend rejects `macos`); opened-capture
                // works on both platforms.
                #if os(iOS)
                    if capturePushNotificationSubscriptions {
                        integrations.append(PostHogPushNotificationSubscriptionIntegration())
                    }
                #endif
                if capturePushNotificationOpened {
                    integrations.append(PostHogPushNotificationOpenIntegration())
                }
            }
        #endif

        return integrations
    }

    var _surveys: Bool = true // swiftlint:disable:this identifier_name
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
    private var beforeSend = BeforeSendChain<PostHogEvent>()

    /// Replaces the event `beforeSend` chain with the provided blocks.
    ///
    /// Blocks run synchronously in array order before an event is cached or sent. Returning
    /// `nil` from any block drops the event and skips the remaining blocks.
    ///
    /// - Parameter blocks: Ordered callbacks that can mutate or drop events.
    public func setBeforeSend(_ blocks: [BeforeSendBlock]) {
        beforeSend.set(blocks)
    }

    /// Replaces the event `beforeSend` chain with the provided blocks.
    ///
    /// - Parameter blocks: Ordered callbacks that can mutate or drop events.
    public func setBeforeSend(_ blocks: BeforeSendBlock...) {
        setBeforeSend(blocks)
    }

    /// Replaces the event `beforeSend` chain from Objective-C boxed callbacks.
    ///
    /// - Parameter blocks: Ordered Objective-C callback boxes.
    @available(swift, obsoleted: 1.0, message: "Use setBeforeSend(_ blocks: BeforeSendBlock...) instead")
    @objc public func setBeforeSend(_ blocks: [BoxedBeforeSendBlock]) {
        setBeforeSend(blocks.map(\.block))
    }

    func runBeforeSend(_ event: PostHogEvent) -> PostHogEvent? {
        beforeSend.run(event)
    }
}
