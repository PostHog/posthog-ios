//
//  PostHogErrorTrackingConfig.swift
//  PostHog
//
//  Created by Ioannis Josephides on 11/11/2025.
//

import Foundation

/// Configuration for error tracking and exception capture
///
/// This class controls how exceptions are captured and processed,
/// including which stack trace frames are marked as "in-app" code.
@objc public class PostHogErrorTrackingConfig: NSObject {
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

    // MARK: - Initialization

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
