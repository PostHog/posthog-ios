//
//  PostHogPropertiesSanitizer.swift
//  PostHog
//
//  Created by Manoel Aranda Neto on 06.08.24.
//

import Foundation

/// Protocol to sanitize the event properties
@objc(PostHogPropertiesSanitizer) public protocol PostHogPropertiesSanitizer {
    /// Sanitizes the event properties
    /// - Parameter properties: the event properties to sanitize
    /// - Returns: the sanitized properties
    ///
    /// Obs: `inout` cannot be used in Swift protocols, so you need to clone the properties
    ///
    /// ```swift
    /// private class ExampleSanitizer: PostHogPropertiesSanitizer {
    ///     public func sanitize(_ properties: [String: Any]) -> [String: Any] {
    ///         var sanitizedProperties = properties
    ///         // Perform sanitization
    ///         // For example, removing keys with empty values
    ///         for (key, value) in properties {
    ///             if let stringValue = value as? String, stringValue.isEmpty {
    ///                 sanitizedProperties.removeValue(forKey: key)
    ///             }
    ///         }
    ///         return sanitizedProperties
    ///     }
    /// }
    /// ```
    @objc func sanitize(_ properties: [String: Any]) -> [String: Any]
}
