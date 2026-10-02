//
//  PostHogFeatureFlagsLoaded.swift
//  PostHog
//

import Foundation

/// The feature flags passed to an `onFeatureFlags` callback.
///
/// ## Example Usage
/// ```swift
/// let subscription = PostHogSDK.shared.onFeatureFlags { loaded in
///     if loaded.errorsLoading {
///         // The values are the last known (cached) flags
///     }
///     if loaded.variants["new-checkout"] as? String == "test" {
///         // Show the test variant
///     }
/// }
///
/// // Later, stop listening
/// subscription.unsubscribe()
/// ```
@objc(PostHogFeatureFlagsLoaded)
public final class PostHogFeatureFlagsLoaded: NSObject {
    /// The keys of the enabled feature flags.
    @objc public let flags: [String]

    /// The values of the enabled feature flags, keyed by flag key.
    ///
    /// A value is `true` for an enabled boolean flag, or the variant `String` for a multivariate flag.
    /// Disabled flags are not included.
    @objc public let variants: [String: Any]

    /// `true` if the latest attempt to load feature flags failed.
    ///
    /// When it did, ``flags`` and ``variants`` hold the last known values, which can be empty.
    @objc public let errorsLoading: Bool

    init(featureFlags: [String: Any], errorsLoading: Bool) {
        let enabled = featureFlags.filter { _, value in
            if let bool = value as? Bool {
                return bool
            }
            return value is String
        }
        flags = Array(enabled.keys)
        variants = enabled
        self.errorsLoading = errorsLoading
    }
}

/// A registration returned by `PostHogSDK.onFeatureFlags(_:)`.
///
/// The callback stays registered until you call ``unsubscribe()``. You don't need to keep
/// a reference to this object unless you want to unsubscribe later.
@objc(PostHogFeatureFlagsSubscription)
public final class PostHogFeatureFlagsSubscription: NSObject {
    private let onUnsubscribe: () -> Void

    init(_ onUnsubscribe: @escaping () -> Void) {
        self.onUnsubscribe = onUnsubscribe
    }

    /// Stops the callback from being invoked. Calling it more than once has no effect.
    @objc public func unsubscribe() {
        onUnsubscribe()
    }
}
