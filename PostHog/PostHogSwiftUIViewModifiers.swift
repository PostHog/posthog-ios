//
//  PostHogSwiftUIViewModifiers.swift
//  PostHog
//
//  Created by Manoel Aranda Neto on 05.09.24.
//

#if canImport(SwiftUI)
    import Foundation
    import SwiftUI

    struct PostHogSwiftUIViewModifier: ViewModifier {
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

    public extension View {
        func postHogScreenView(_ screenName: String,
                               _ properties: [String: Any]? = nil) -> some View
        {
            modifier(PostHogSwiftUIViewModifier(viewEventName: screenName,
                                                screenEvent: true,
                                                properties: properties))
        }

        func postHogViewEvent(_ event: String,
                              _ properties: [String: Any]? = nil) -> some View
        {
            modifier(PostHogSwiftUIViewModifier(viewEventName: event,
                                                screenEvent: false,
                                                properties: properties))
        }
    }

#endif
