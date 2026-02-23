//
//  PostHogDeepLinkModifier.swift
//  PostHog
//
//  Created by Jeremiah Erinola on 21.02.26.
//

import Foundation
import SwiftUI

#if canImport(SwiftUI) && (os(iOS) || os(tvOS) || os(macOS) || os(watchOS) || os(visionOS))

    @available(iOS 14.0, macOS 11.0, tvOS 14.0, watchOS 7.0, *)
    public struct PostHogDeepLinkModifier: ViewModifier {
        public func body(content: Content) -> some View {
            content
                .onOpenURL { url in
                    PostHogSDK.shared.captureDeepLink(url: url)
                }
                .onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { userActivity in
                    if let url = userActivity.webpageURL {
                        PostHogSDK.shared.captureDeepLink(url: url, referrer: userActivity.referrerURL?.absoluteString)
                    }
                }
        }
    }

    @available(iOS 14.0, macOS 11.0, tvOS 14.0, watchOS 7.0, *)
    public extension View {
        /// Captures deep link events (URL opens and Universal Links) automatically.
        ///
        /// This modifier attaches `.onOpenURL` and `.onContinueUserActivity` handlers to the view.
        /// When a deep link is detected, it triggers a `Deep Link Opened` event in PostHog.
        ///
        /// - Returns: A view that handles deep links.
        func postHogDeepLinkHandler() -> some View {
            modifier(PostHogDeepLinkModifier())
        }
    }

#endif
