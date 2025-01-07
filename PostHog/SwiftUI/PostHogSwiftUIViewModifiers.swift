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
         - Returns: A modified view that will be tracked as a screen in PostHog.
         */
        func postHogScreenView(_ screenName: String? = nil,
                               _ properties: [String: Any]? = nil) -> some View
        {
            let viewEventName = screenName ?? "\(type(of: self))"
            return modifier(PostHogSwiftUIViewModifier(viewEventName: viewEventName,
                                                       screenEvent: true,
                                                       properties: properties))
        }

        func postHogViewSeen(_ event: String,
                             _ properties: [String: Any]? = nil) -> some View
        {
            modifier(PostHogSwiftUIViewModifier(viewEventName: event,
                                                screenEvent: false,
                                                properties: properties))
        }
    }

    private struct PostHogSwiftUIViewModifier: ViewModifier {
        let viewEventName: String

        let screenEvent: Bool

        let properties: [String: Any]?

        func body(content: Content) -> some View {
            content.onAppear {
                if screenEvent {
                    PostHogSDK.shared.screen(viewEventName, properties: properties)
                } else {
                    PostHogSDK.shared.capture(viewEventName, properties: properties)
                }
            }
        }
    }

#endif
