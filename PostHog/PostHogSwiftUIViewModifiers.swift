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

    struct PostHogSensitiveViewWrapperRepresentable: UIViewRepresentable {
        @Binding var viewWrapper: PostHogSensitiveViewWrapper?

        func makeUIView(context _: Context) -> PostHogSensitiveViewWrapper {
            let wrapper = PostHogSensitiveViewWrapper()
            viewWrapper = wrapper
            return wrapper
        }

        func updateUIView(_: PostHogSensitiveViewWrapper, context _: Context) {}
    }

    class PostHogSensitiveViewWrapper: UIView {
        override func didMoveToSuperview() {
            super.didMoveToSuperview()
            if superview != nil {
                PostHogScreenshotMasker.shared.addView(self)
            } else {
                PostHogScreenshotMasker.shared.removeView(self)
            }
        }
    }

    struct PostHogSensitiveModifier: ViewModifier {
        @State private var viewWrapper: PostHogSensitiveViewWrapper?

        func body(content: Content) -> some View {
            content
                .background(PostHogSensitiveViewWrapperRepresentable(viewWrapper: $viewWrapper))
        }
    }

    public extension View {
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

        func postHogMask() -> some View {
            modifier(PostHogSensitiveModifier())
        }
    }

#endif
