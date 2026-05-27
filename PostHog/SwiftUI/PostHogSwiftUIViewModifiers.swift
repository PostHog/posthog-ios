//
//  PostHogSwiftUIViewModifiers.swift
//  PostHog
//
//  Created by Manoel Aranda Neto on 05.09.24.
//

#if canImport(SwiftUI)
    import Foundation
    import SwiftUI

    /// SwiftUI analytics capture helpers.
    public extension View {
        /// Marks a SwiftUI view to be tracked as a `$screen` event when `onAppear` runs.
        ///
        /// - Parameters:
        ///   - screenName: The screen name. Defaults to the view's type name.
        ///   - properties: Additional properties to attach to the `$screen` event.
        ///   - postHog: SDK instance used to send the event. Defaults to `PostHogSDK.shared`.
        /// - Returns: A modified view that captures a screen view when it appears.
        func postHogScreenView(_ screenName: String? = nil,
                               _ properties: [String: Any]? = nil,
                               postHog: PostHogSDK? = nil) -> some View
        {
            let viewEventName = screenName ?? "\(type(of: self))"
            return modifier(PostHogSwiftUIViewModifier(viewEventName: viewEventName,
                                                       screenEvent: true,
                                                       properties: properties,
                                                       postHog: postHog))
        }

        /// Captures a custom event when this SwiftUI view appears.
        ///
        /// - Parameters:
        ///   - event: Event name to capture.
        ///   - properties: Additional event properties.
        ///   - postHog: SDK instance used to send the event. Defaults to `PostHogSDK.shared`.
        /// - Returns: A modified view that captures the event when it appears.
        func postHogViewSeen(_ event: String,
                             _ properties: [String: Any]? = nil,
                             postHog: PostHogSDK? = nil) -> some View
        {
            modifier(PostHogSwiftUIViewModifier(viewEventName: event,
                                                screenEvent: false,
                                                properties: properties,
                                                postHog: postHog))
        }
    }

    private struct PostHogSwiftUIViewModifier: ViewModifier {
        let viewEventName: String

        let screenEvent: Bool

        let properties: [String: Any]?

        let postHog: PostHogSDK?

        func body(content: Content) -> some View {
            content.onAppear {
                if screenEvent {
                    instance.screen(viewEventName, properties: properties)
                } else {
                    instance.capture(viewEventName, properties: properties)
                }
            }
        }

        private var instance: PostHogSDK {
            postHog ?? PostHogSDK.shared
        }
    }

#endif
