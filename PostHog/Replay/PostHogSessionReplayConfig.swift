//
//  PostHogSessionReplayConfig.swift
//  PostHog
//
//  Created by Manoel Aranda Neto on 19.03.24.
//
#if os(iOS)
    import Foundation

    /// Configuration for iOS session replay capture.
    ///
    /// Mutate fields on `config.sessionReplayConfig` before calling `PostHogSDK.setup(_:)`.
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

        /// Enable recording touch coordinates in session replay. Screenshot capture is unaffected.
        /// Set before SDK setup. Runtime changes are not supported.
        /// Default: true
        @objc public var captureTouches: Bool = true

        /// Enable capturing network telemetry
        /// Default: true
        ///
        /// Note: When enabled, can be disabled remotely via project settings
        @objc public var captureNetworkTelemetry: Bool = true

        /// Deprecated. Session replay always captures screenshots of the screen, with sensitive
        /// content masked according to the masking options above.
        ///
        /// This property has no effect: it always reads `true` and ignores writes.
        @available(*, deprecated, message: "Wireframe capture was removed and session replay always records masked screenshots. This property has no effect and will be removed in a future major release. Use the masking options or postHogMask() to hide sensitive content.")
        @objc public var screenshotMode: Bool {
            get { true }
            set {} // swiftlint:disable:this unused_setter_value
        }

        /// Throttle delay used to reduce the number of snapshots captured and reduce performance impact
        /// This is used for capturing the screenshot
        /// The lower the number more snapshots will be captured but higher the performance impact
        /// Defaults to 1s
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
        /// Note: When enabled, can be disabled remotely via project settings
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

        #if !SWIFT_PACKAGE || SessionReplay
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
        #endif
    }
#endif
