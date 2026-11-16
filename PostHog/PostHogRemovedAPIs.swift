//
//  PostHogRemovedAPIs.swift
//  PostHog
//

// TODO: Delete this file (and its Xcode project entries) a few minor versions into 4.x.
//
// Unavailable stubs for 3.x names, so code that still uses them gets a compile error that names
// the replacement (with an Xcode fix-it for plain renames) instead of "cannot find in scope".
// None of this can be called, so deleting it isn't a breaking change. They're Swift-only:
// Objective-C callers see the old selectors disappear.

import Foundation

/// Removed in PostHog 4.0. Use `PostHogConfig.setBeforeSend(_:)` instead.
@available(*, unavailable, message: "Removed in PostHog 4.0. Use PostHogConfig.setBeforeSend(_:) to change or drop event properties.")
public protocol PostHogPropertiesSanitizer {}

/// Configuration options removed or renamed in PostHog 4.0.
public extension PostHogConfig {
    /// Removed in PostHog 4.0. Use `projectToken` instead.
    @available(*, unavailable, renamed: "projectToken", message: "Renamed in PostHog 4.0.")
    var apiKey: String {
        projectToken
    }

    /// Removed in PostHog 4.0. Use `PostHogConfig(projectToken:)` instead.
    @available(*, unavailable, renamed: "init(projectToken:)", message: "Renamed in PostHog 4.0.")
    convenience init(apiKey: String) {
        self.init(projectToken: apiKey)
    }

    /// Removed in PostHog 4.0. Use `PostHogConfig(projectToken:host:)` instead.
    @available(*, unavailable, renamed: "init(projectToken:host:)", message: "Renamed in PostHog 4.0.")
    convenience init(apiKey: String, host: String) {
        self.init(projectToken: apiKey, host: host)
    }

    /// Removed in PostHog 4.0. Use `pushNotificationSubscriptionMaxRetries` instead.
    @available(*, unavailable, renamed: "pushNotificationSubscriptionMaxRetries", message: "Renamed in PostHog 4.0. It only ever limited push-notification subscription retries.")
    var maxRetries: Int {
        get { pushNotificationSubscriptionMaxRetries }
        set { pushNotificationSubscriptionMaxRetries = newValue }
    }

    /// Removed in PostHog 4.0. Use `evaluationContexts` instead.
    @available(*, unavailable, renamed: "evaluationContexts", message: "Renamed in PostHog 4.0.")
    var evaluationEnvironments: [String]? {
        get { evaluationContexts }
        set { evaluationContexts = newValue }
    }

    /// Removed in PostHog 4.0. Remote config is always loaded.
    @available(*, unavailable, message: "Removed in PostHog 4.0. Remote config is always loaded: delete the assignment.")
    var remoteConfig: Bool {
        get { true }
        set {} // swiftlint:disable:this unused_setter_value
    }

    /// Removed in PostHog 4.0. Use `setBeforeSend(_:)` instead.
    @available(*, unavailable, message: "Removed in PostHog 4.0. Use setBeforeSend(_:) to change or drop event properties.")
    var propertiesSanitizer: PostHogPropertiesSanitizer? {
        get { nil }
        set {} // swiftlint:disable:this unused_setter_value
    }
}

/// Data modes removed in PostHog 4.0.
public extension PostHogConfig.PostHogDataMode {
    /// Removed in PostHog 4.0. It behaved like `.any`, so use `.any` instead.
    @available(*, unavailable, renamed: "any", message: "Removed in PostHog 4.0. It behaved like .any.")
    static var cellular: PostHogConfig.PostHogDataMode {
        .any
    }
}

/// SDK APIs removed in PostHog 4.0.
public extension PostHogSDK {
    /// Removed in PostHog 4.0. Use `getFeatureFlagResult(_:sendFeatureFlagEvent:)` and read its `payload`.
    @available(*, unavailable, message: "Removed in PostHog 4.0. Use getFeatureFlagResult(key, sendFeatureFlagEvent: false)?.payload.")
    func getFeatureFlagPayload(_ key: String) -> Any? {
        getFeatureFlagResult(key, sendFeatureFlagEvent: false)?.payload
    }

    /// Removed in PostHog 4.0. Use `onFeatureFlags(_:)` instead.
    @available(*, unavailable, message: "Removed in PostHog 4.0. Use onFeatureFlags(_:), which runs on the main thread after each flag load.")
    static var didReceiveFeatureFlags: Notification.Name {
        Notification.Name("PostHogDidReceiveFeatureFlags")
    }
}

#if os(iOS) && (!SWIFT_PACKAGE || SessionReplay)
    /// Renamed to `PostHogConsoleLogLevel` in PostHog 4.0.
    @available(*, unavailable, renamed: "PostHogConsoleLogLevel", message: "Renamed in PostHog 4.0.")
    public typealias PostHogLogLevel = PostHogConsoleLogLevel

    /// Renamed to `PostHogConsoleLogEntry` in PostHog 4.0.
    @available(*, unavailable, renamed: "PostHogConsoleLogEntry", message: "Renamed in PostHog 4.0.")
    public typealias PostHogLogEntry = PostHogConsoleLogEntry

    /// Session replay options removed or renamed in PostHog 4.0.
    public extension PostHogSessionReplayConfig {
        /// Removed in PostHog 4.0. Use `throttleDelay` instead.
        @available(*, unavailable, renamed: "throttleDelay", message: "Renamed in PostHog 4.0.")
        var debouncerDelay: TimeInterval {
            get { throttleDelay }
            set { throttleDelay = newValue }
        }

        /// Removed in PostHog 4.0. Replay always records masked screenshots.
        @available(*, unavailable, message: "Removed in PostHog 4.0. Replay always records masked screenshots: delete the assignment.")
        var screenshotMode: Bool {
            get { true }
            set {} // swiftlint:disable:this unused_setter_value
        }

        /// Removed in PostHog 4.0. Use `captureMethod = .background` instead.
        @available(*, unavailable, message: "Removed in PostHog 4.0. Set captureMethod = .background instead of screenshotModeBackgroundCapture = true.")
        var screenshotModeBackgroundCapture: Bool {
            get { captureMethod == .background }
            set {} // swiftlint:disable:this unused_setter_value
        }

        /// Removed in PostHog 4.0. Use `captureMethod = .gpu` instead.
        @available(*, unavailable, message: "Removed in PostHog 4.0. Set captureMethod = .gpu instead of screenshotModeGPUCapture = true.")
        var screenshotModeGPUCapture: Bool {
            get { captureMethod == .gpu }
            set {} // swiftlint:disable:this unused_setter_value
        }

        /// Removed in PostHog 4.0. It had no effect.
        @available(*, unavailable, message: "Removed in PostHog 4.0. It had no effect: delete the assignment.")
        var maskPhotoLibraryImages: Bool {
            get { false }
            set {} // swiftlint:disable:this unused_setter_value
        }
    }
#endif
