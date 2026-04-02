//
//  PostHogDeepLinkHelper.swift
//  PostHog
//
//  Created by Jeremiah Erinola on 18.02.26.
//

import Foundation

enum PostHogDeepLinkHelper {
    /// Builds deep link properties for a given URL and optional referrer.
    /// - Parameters:
    ///   - url: The URL that was opened.
    ///   - referrer: The referrer that triggered the deep link (optional). Can be an app bundle id or a URL.
    /// - Returns: A properties dictionary including `url`, `$referrer` (if provided), and `$referring_domain` (if referrer is a URL with a host).
    static func buildDeepLinkProperties(url: URL, referrer: String?) -> [String: Any] {
        var properties: [String: Any] = ["url": url.absoluteString]

        if let referrer = referrer {
            properties["$referrer"] = referrer

            // Try to extract domain from referrer if it looks like a URL
            if let referrerURL = URL(string: referrer), let host = referrerURL.host {
                properties["$referring_domain"] = host
            }
        }

        return properties
    }
}
