//
//  PostHogFeatureFlagResult.swift
//  PostHog
//
//  Created by Dustin Byrne on 29/01/2026.
//

import Foundation

/// Result object containing all information about a feature flag evaluation.
///
/// This struct provides access to the flag value, variant, payload, and other metadata
/// in a single convenient object.
///
/// ## Example Usage
/// ```swift
/// if let result = PostHogSDK.shared.getFeatureFlagResult("my-feature") {
///     if result.enabled {
///         // Feature is enabled
///         if let variant = result.variant {
///             // Handle specific variant
///             print("Variant: \(variant)")
///         }
///         if let payload = result.payload as? [String: Any] {
///             // Use the payload data
///         }
///     }
/// }
/// ```
@objc(PostHogFeatureFlagResult)
public class PostHogFeatureFlagResult: NSObject {
    /// The key of the feature flag.
    @objc public let key: String

    /// Whether the feature flag is enabled.
    ///
    /// This is `true` if the flag value is:
    /// - A boolean `true`
    /// - A non-null string (variant)
    @objc public let enabled: Bool

    /// The variant name if this is a multivariate flag, otherwise `nil`.
    @objc public let variant: String?

    /// The payload associated with this feature flag, if any.
    ///
    /// The payload can be any JSON-serializable value (string, number, boolean, array, or dictionary).
    @objc public let payload: Any?

    init(key: String, enabled: Bool, variant: String?, payload: Any?) {
        self.key = key
        self.enabled = enabled
        self.variant = variant
        self.payload = payload
    }

    /// Returns the payload deserialized as the specified Decodable type.
    ///
    /// If the payload is already an instance of T, returns it directly.
    /// Otherwise, attempts to serialize to JSON and decode.
    ///
    /// - Parameter type: The type to decode the payload as
    /// - Returns: The payload as type T, or nil if the payload is nil or decoding fails
    public func payloadAs<T: Decodable>(_ type: T.Type) -> T? {
        guard let payload else { return nil }

        if let typed = payload as? T {
            return typed
        }

        guard JSONSerialization.isValidJSONObject(payload) else {
            return nil
        }

        do {
            let data = try JSONSerialization.data(withJSONObject: payload)
            return try JSONDecoder().decode(type, from: data)
        } catch {
            return nil
        }
    }
}
