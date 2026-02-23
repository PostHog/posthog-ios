//
//  PostHogDeepLinkIntegration.swift
//  PostHog
//
//  Created by Jeremiah Erinola on 18.02.26.
//

import Foundation

#if os(iOS) || os(tvOS)
import UIKit
#endif

class PostHogDeepLinkIntegration: PostHogIntegration {
    var requiresSwizzling: Bool { false }

    private static var integrationInstalledLock = NSLock()
    private static var integrationInstalled = false

    private weak var postHog: PostHogSDK?

    // Store a reference to the active SDK instance for the static tracking methods
    // We only support one active SDK instance for deep link tracking at a time because
    // deep links are global app events.
    static weak var currentInstance: PostHogSDK?

    func install(_ postHog: PostHogSDK) throws {
        try PostHogDeepLinkIntegration.integrationInstalledLock.withLock {
            if PostHogDeepLinkIntegration.integrationInstalled {
                throw InternalPostHogError(description: "Deep link integration already installed to another PostHogSDK instance.")
            }
            PostHogDeepLinkIntegration.integrationInstalled = true
        }

        self.postHog = postHog
        PostHogDeepLinkIntegration.currentInstance = postHog

        start()
    }

    func uninstall(_ postHog: PostHogSDK) {
        if self.postHog === postHog || self.postHog == nil {
            stop()
            self.postHog = nil
            PostHogDeepLinkIntegration.currentInstance = nil
            PostHogDeepLinkIntegration.integrationInstalledLock.withLock {
                PostHogDeepLinkIntegration.integrationInstalled = false
            }
        }
    }

    func start() {
        // No-op: swizzling removed
    }

    func stop() {
        // No-op: no observers are added
    }
}

// MARK: - Tracking Logic

extension PostHogDeepLinkIntegration {
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

    #if os(iOS) || os(tvOS)
    static func trackDeepLink(url: URL, options: [UIApplication.OpenURLOptionsKey: Any]) {
        let referrer = options[.sourceApplication] as? String
        trackDeepLink(url: url, referrer: referrer)
    }

    @available(iOS 13.0, tvOS 13.0, *)
    static func trackDeepLink(url: URL, options: UIScene.OpenURLOptions) {
        trackDeepLink(url: url, referrer: options.sourceApplication)
    }

    static func trackDeepLink(userActivity: NSUserActivity) {
        if userActivity.activityType == NSUserActivityTypeBrowsingWeb, let url = userActivity.webpageURL {
            trackDeepLink(url: url, referrer: userActivity.referrerURL?.absoluteString)
        }
    }
    #endif

    static func trackDeepLink(url: URL, referrer: String?) {
        guard let postHog = PostHogDeepLinkIntegration.currentInstance,
              postHog.config.captureDeepLinks else { return }

        let properties = buildDeepLinkProperties(url: url, referrer: referrer)
        postHog.capture("Deep Link Opened", properties: properties)
    }
}

#if os(iOS) || os(tvOS)
public extension PostHogSDK {
    @discardableResult
    func handleOpenURL(_ url: URL, options: [UIApplication.OpenURLOptionsKey: Any] = [:]) -> Bool {
        PostHogDeepLinkIntegration.trackDeepLink(url: url, options: options)
        return false
    }

    @available(iOS 13.0, tvOS 13.0, *)
    @discardableResult
    func handleSceneOpenURL(_ url: URL, options: UIScene.OpenURLOptions) -> Bool {
        PostHogDeepLinkIntegration.trackDeepLink(url: url, options: options)
        return false
    }

    @discardableResult
    func handleUserActivity(_ userActivity: NSUserActivity) -> Bool {
        PostHogDeepLinkIntegration.trackDeepLink(userActivity: userActivity)
        return false
    }
}
#endif

