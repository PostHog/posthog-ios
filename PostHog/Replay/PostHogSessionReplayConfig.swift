//
//  PostHogSessionReplayConfig.swift
//  PostHog
//
//  Created by Manoel Aranda Neto on 19.03.24.
//
#if os(iOS)
    import Foundation

    @objc(PostHogSessionReplayConfig) public class PostHogSessionReplayConfig: NSObject {
        /// Enable masking of all text and text input fields
        /// Default: true
        @objc public var maskAllTextInputs: Bool = true

        /// Enable masking of all images to a placeholder
        /// Default: true
        @objc public var maskAllImages: Bool = true

        /// Enable masking of all sandboxed system views
        /// These may include UIImagePickerController, PHPickerViewController and CNContactPickerViewController
        /// Default: true
        @objc public var maskAllSandboxedViews: Bool = true

        /// Enable masking of images that likely originated from user's photo library (UIKit only)
        /// Default: false
        ///
        /// - Note: Deprecated
        @available(*, deprecated, message: "This property has no effect and will be removed in the next major release. To learn how to manually mask user photos please see our Privacy controls documentation: https://posthog.com/docs/session-replay/privacy?tab=iOS")
        @objc public var maskPhotoLibraryImages: Bool = false

        /// Enable capturing network telemetry
        /// Default: true
        ///
        /// Note: When enabled, can be disabled remotely via project settings (requires `PostHogConfig.remoteConfig` to be enabled)
        @objc public var captureNetworkTelemetry: Bool = true

        /// By default Session replay will capture all the views on the screen as a wireframe,
        /// By enabling this option, PostHog will capture the screenshot of the screen.
        /// The screenshot may contain sensitive information, use with caution.
        /// Default: false
        @objc public var screenshotMode: Bool = false

        /// Debouncer delay used to reduce the number of snapshots captured and reduce performance impact
        /// This is used for capturing the view as a wireframe or screenshot
        /// The lower the number more snapshots will be captured but higher the performance impact
        /// Defaults to 1s
        @available(*, deprecated, message: "Deprecated in favor of 'throttleDelay' which provides identical functionality. Will be removed in the next major release.")
        @objc public var debouncerDelay: TimeInterval {
            get { throttleDelay }
            set { throttleDelay = newValue }
        }

        /// Throttle delay used to reduce the number of snapshots captured and reduce performance impact
        /// This is used for capturing the view as a wireframe or screenshot
        /// The lower the number more snapshots will be captured but higher the performance impact
        /// Defaults to 1s
        ///
        /// Note: Previously `debouncerDelay`
        @objc public var throttleDelay: TimeInterval = 1

        /// Enable capturing console output for session replay.
        ///
        /// When enabled, logs from the following sources will be captured:
        /// - Standard output (stdout)
        /// - Standard error (stderr)
        /// - OSLog messages
        /// - NSLog messages
        ///
        /// Each log entry will be tagged with a level (info/warning/error) based on the message content
        /// and the source.
        ///
        /// Defaults to `false`
        ///
        /// Note: When enabled, can be disabled remotely via project settings (requires `PostHogConfig.remoteConfig` to be enabled)
        @objc public var captureLogs: Bool = false

        /// Further configuration for capturing console output
        @objc public var captureLogsConfig: PostHogSessionReplayConsoleLogConfig = .init()

        /// Session recording sample rate, between 0.0 and 1.0.
        ///
        /// 1.0 means every session will be recorded, 0.0 means no sessions will be recorded.
        /// Sampling is deterministic based on the session ID, so the same session will always
        /// produce the same sampling decision.
        ///
        /// When set, takes precedence over the remote config sample rate.
        /// When `nil`, the remote config sample rate is used (if available), otherwise all sessions are recorded.
        ///
        /// Values outside the 0.0–1.0 range are ignored and treated as `nil`.
        ///
        /// Defaults to `nil`
        @objc public var sampleRate: NSNumber? {
            didSet {
                if let value = sampleRate?.doubleValue, value < 0.0 || value > 1.0 {
                    hedgeLog("PostHogSessionReplayConfig.sampleRate must be between 0.0 and 1.0, got \(value). Ignoring.")
                    sampleRate = nil
                }
            }
        }

        /// Returns an array of plugin types based on current configuration
        func getPluginTypes() -> [PostHogSessionReplayPlugin.Type] {
            var types: [PostHogSessionReplayPlugin.Type] = []

            if captureLogs {
                types.append(PostHogSessionReplayConsoleLogsPlugin.self)
            }

            if captureNetworkTelemetry {
                types.append(PostHogSessionReplayNetworkPlugin.self)
            }

            return types
        }
    }
#endif
