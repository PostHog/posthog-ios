//
//  PostHogDeepLinkListener.swift
//  PostHog
//
//  Created by Jeremiah Erinola on 23.02.26.
//

#if canImport(SwiftUI)
    import Foundation
    import SwiftUI

    /// A SwiftUI ViewModifier that listens for deep link events and forwards them to PostHog.
    private struct PostHogDeepLinkListener: ViewModifier {
        let posthog: PostHogSDK?

        func body(content: Content) -> some View {
            #if os(iOS) || os(tvOS) || os(macOS)
                if #available(iOS 14.0, tvOS 14.0, macOS 11.0, *) {
                    content
                        .onOpenURL { url in
                            posthog?.captureDeepLink(url: url)
                        }
                        .onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { activity in
                            posthog?.captureDeepLink(userActivity: activity)
                        }
                } else {
                    content
                }
            #else
                content
            #endif
        }
    }

    public extension View {
        /// Attach a PostHog deep link listener to this view. The listener will forward
        /// .onOpenURL and .onContinueUserActivity events to the provided PostHogSDK instance.
        /// - Parameter posthog: The PostHogSDK instance to use for tracking. If not provided,
        ///   the currently installed instance will be used if available.
        func postHogDeepLinkListener(_ posthog: PostHogSDK? = nil) -> some View {
            let sdk = posthog ?? PostHogSDK.shared
            return modifier(PostHogDeepLinkListener(posthog: sdk))
        }
    }
#endif
