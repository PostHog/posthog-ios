//
//  PostHogSessionReplayConfig.swift
//  PostHog
//
//  Created by Manoel Aranda Neto on 19.03.24.
//
#if os(iOS) && (!SWIFT_PACKAGE || SessionReplay)
    import Foundation

    /// How session replay captures a screenshot. Set it with `PostHogSessionReplayConfig.captureMethod`.
    @objc(PostHogSessionReplayCaptureMethod) public enum PostHogSessionReplayCaptureMethod: Int {
        /// Renders the window with `drawHierarchy` on the main thread, once the screen has settled.
        case standard

        /// Renders the window on a background queue, so capture takes the least main-thread time.
        ///
        /// Try this if session replay causes main-thread hangs or dropped frames on complex screens.
        /// A frame is skipped when masked content moves while it renders.
        ///
        /// Warning: this triggers Main Thread Checker warnings and may briefly freeze the app the first
        /// time a screenshot is captured. Consider disabling Main Thread Checker in your scheme's run
        /// diagnostics when using it.
        case background

        /// Copies the window's layer tree on the main thread and renders the copy on the GPU with Metal,
        /// so the main thread only builds the copy. Takes less main-thread time than `.standard`, more than
        /// `.background`.
        ///
        /// Layers whose presentation can't be copied safely (an app's or a framework's own `CALayer`
        /// subclasses) are drawn from their model state instead. While one of them has an animation that
        /// moves or reshapes it, a playing Lottie animation for example, it is left out of the frame with
        /// everything under it.
        ///
        /// Not captured exactly:
        /// - Metal content (MapKit, SceneKit, SpriteKit, `MTKView`) shows as a striped
        ///   "Metal content" placeholder.
        /// - Video and camera previews stay blank, as with `.standard`.
        /// - Liquid Glass is approximated without refraction: sheets, alerts and dialogs as a blur of what's
        ///   behind them, smaller glass as a flat fill in its shape. Tinted glass keeps its tint. The labels and
        ///   icons on it are reproduced. On iOS 27, sheets, alerts and dialogs currently show as a flat panel
        ///   instead of a blur.
        ///
        /// Captures fall back to `.standard` when the device has no Metal or a render fails.
        ///
        /// While recording, the app keeps roughly 25 to 30 MB more memory resident on average (GPU memory held
        /// by Metal and Core Animation); peak memory is about the same as with `.standard`. Measured on an
        /// iPhone 17 Pro with `screenshotScale` unset, one pixel per point; a larger scale holds more.
        ///
        /// Experimental. iOS and Mac Catalyst only.
        case gpu
    }

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

        /// Resolution of screenshots, as a multiplier of the screen's native resolution.
        ///
        /// - `nil`: one pixel per point on every device, so a 402×874 pt screen uploads 402×874 pixels.
        /// - A value: that fraction of native resolution. On a 3x device, `1.0` uploads 1206×2622 pixels
        ///   (native) and `0.5` uploads 603×1311 (1.5 pixels per point).
        ///
        /// Values are clamped to 0.1...1.0, and NaN or infinite values reset it to `nil`. The replay's viewport in
        /// points is unchanged. Does not affect compression quality. Exposed as `NSNumber` so
        /// Objective-C can leave it unset. Applies to every `captureMethod`.
        ///
        /// Default: nil (one pixel per point)
        @objc public var screenshotScale: NSNumber? {
            didSet {
                guard let value = screenshotScale?.doubleValue else { return }
                screenshotScale = value.isFinite ? NSNumber(value: min(max(value, 0.1), 1)) : nil
            }
        }

        func screenshotPixelScale(nativeScale: CGFloat) -> CGFloat {
            screenshotScale.map { nativeScale * CGFloat($0.doubleValue) } ?? 1
        }

        /// How session replay captures each screenshot. See `PostHogSessionReplayCaptureMethod`.
        ///
        /// Default: `.standard`
        @objc public var captureMethod: PostHogSessionReplayCaptureMethod = .standard

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
