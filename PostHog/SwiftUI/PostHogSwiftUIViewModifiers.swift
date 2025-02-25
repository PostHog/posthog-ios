//
//  PostHogSwiftUIViewModifiers.swift
//  PostHog
//
//  Created by Manoel Aranda Neto on 05.09.24.
//

#if canImport(SwiftUI)
    import Foundation
    import SwiftUI

    public extension View {
        /**
         Marks a SwiftUI View to be tracked as a $screen event in PostHog when onAppear is called.

         - Parameters:
         - screenName: The name of the screen. Defaults to the type of the view.
         - properties: Additional properties to be tracked with the screen.
         - postHog: The instance to be used when sending the $screen event
         - Returns: A modified view that will be tracked as a screen in PostHog.
         */
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
