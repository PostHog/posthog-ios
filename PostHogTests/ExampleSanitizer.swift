//
//  ExampleSanitizer.swift
//  PostHogTests
//
//  Created by Manoel Aranda Neto on 06.08.24.
//

import Foundation
import PostHog

class ExampleSanitizer: PostHogPropertiesSanitizer {
    public func sanitize(_ properties: [String: Any]) -> [String: Any] {
        var sanitizedProperties = properties
        // Perform sanitization
        // For example, removing keys with empty values
        for (key, value) in properties {
            if let stringValue = value as? String, stringValue.isEmpty {
                sanitizedProperties.removeValue(forKey: key)
            }
        }
        return sanitizedProperties
    }
}
