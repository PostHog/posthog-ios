//
//  PostHogErrorTrackingConfig.swift
//  PostHog
//
//  Created by Ioannis Josephides on 11/11/2025.
//

import Foundation

/// Configuration for error tracking and exception capture.
///
/// This class controls how exceptions are captured and processed,
/// including which stack trace frames are marked as "in-app" code.
@objc public class PostHogErrorTrackingConfig: NSObject {
    // MARK: - Crash Reporting

    /// Enable crash autocapture
    ///
    /// When enabled, the SDK will capture the following crash types:
    /// - Mach exceptions (e.g., `EXC_BAD_ACCESS`, `EXC_CRASH`)
    /// - POSIX signals (e.g., `SIGSEGV`, `SIGABRT`, `SIGBUS`)
    /// - Uncaught `NSException`s
    ///
    /// Crashes are persisted to disk and sent as `$exception` events with level "fatal" **on the next app launch**
    ///
    /// - Note: Crash reporting is automatically disabled when a debugger is attached,
    ///   as the debugger intercepts signals before the crash handler can process them.
    ///
    /// Default: false
    private var _autoCapture: Bool = false

    /// Whether crash autocapture is enabled.
    ///
    /// When enabled, fatal crashes are persisted and sent as `$exception` events on the next launch.
    /// Default: `false`.
    @available(watchOS, unavailable, message: "Crash autocapture is not available on watchOS")
    @available(visionOS, unavailable, message: "Crash autocapture is not available on visionOS")
    @objc public var autoCapture: Bool {
        get { _autoCapture }
        set { _autoCapture = newValue }
    }

    // MARK: - In-App Detection Configuration

    /// List of package/bundle identifiers to be considered in-app frames
    ///
    /// Takes precedence over `inAppExcludes`.
    /// If a frame's module matches any prefix in this list,
    /// it will be marked as in-app.
    ///
    /// Example:
    /// ```swift
    /// config.errorTrackingConfig.inAppIncludes = [
    ///     "MyApp",
    ///     "SharedUtils"
    /// ]
    /// ```
    ///
    /// **Default behavior:**
    /// - Automatically includes main bundle identifier
    /// - Automatically includes executable name
    ///
    /// **Precedence:** Priority 1 (highest)
    @objc public var inAppIncludes: [String] = []

    /// List of package/bundle identifiers to be excluded from in-app frames
    ///
    /// Frames matching these prefixes will be marked as not in-app,
    /// unless they also match `inAppIncludes` (which takes precedence).
    ///
    /// Example:
    /// ```swift
    /// config.errorTrackingConfig.inAppExcludes = [
    ///     "Alamofire",
    ///     "SDWebImage"
    /// ]
    /// ```
    ///
    /// **Precedence:** Priority 2 (after inAppIncludes)
    @objc public var inAppExcludes: [String] = []

    /// Configures whether stack trace frames are considered in-app by default
    /// when the origin cannot be determined or no explicit includes/excludes match.
    ///
    /// - If `true` (default): Frames are in-app unless explicitly excluded (allowlist approach)
    /// - If `false`: Frames are external unless explicitly included (denylist approach)
    ///
    /// **Default behavior when true:**
    /// - Known system frameworks (Foundation, UIKit, etc.) are excluded
    /// - All other packages are in-app unless in `inAppExcludes`
    ///
    /// **Precedence:** Priority 4 (final fallback)
    ///
    /// Default: true
    @objc public var inAppByDefault: Bool = true

    // MARK: - Exception Steps

    /// Configuration for exception steps (breadcrumb-style context records).
    ///
    /// Steps recorded via `PostHogSDK.addExceptionStep(_:properties:)` accumulate over the run and
    /// are attached to every captured `$exception` as `$exception_steps`, giving the error tracking
    /// UI a timeline of recent activity before each error.
    @objc public var exceptionSteps = PostHogExceptionStepsConfig()

    // MARK: - Initialization

    /// Creates an error tracking configuration with default in-app frame detection.
    override public init() {
        super.init()

        // Auto-add main bundle identifier
        inAppIncludes.append(getBundleIdentifier())

        // Auto-add executable name
        // This helps catch app code when bundle ID might not be in module name
        if let executableName = Bundle.main.object(forInfoDictionaryKey: "CFBundleExecutable") as? String {
            inAppIncludes.append(executableName)
        }
    }
}

/// Configuration for exception steps (breadcrumb-style context records).
///
/// Steps accumulate in a FIFO buffer bounded by a UTF-8 byte budget and are attached to every
/// captured `$exception`. On a fatal crash they are persisted with the crash context and attached
/// to the crash `$exception` on the next launch.
@objc public class PostHogExceptionStepsConfig: NSObject {
    /// Whether exception steps are recorded and attached to exceptions.
    ///
    /// When `false`, `addExceptionStep(_:properties:)` is a no-op and no steps are attached.
    ///
    /// Default: `true`.
    @objc public var enabled: Bool = true

    /// Maximum total UTF-8 byte size of the buffered steps.
    ///
    /// When adding a step would exceed this budget, the oldest steps are evicted first. A single
    /// step larger than the budget is rejected outright.
    ///
    /// Default: `32768` (32 KB).
    @objc public var maxBytes: Int = 32768
}
