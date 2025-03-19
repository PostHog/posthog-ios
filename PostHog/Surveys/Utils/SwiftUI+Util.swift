//
//  SwiftUI+Util.swift
//  PostHog
//
//  Created by Ioannis Josephides on 10/03/2025.
//

#if canImport(SwiftUI)
    import SwiftUI

    extension View {
        /// Reads frame changes of current view in a coordinate space (default global)
        func readFrame(
            in coordinateSpace: CoordinateSpace = .global,
            onFrame: @escaping (CGRect) -> Void
        ) -> some View {
            modifier(
                ReadFrameModifier(
                    coordinateSpace: coordinateSpace,
                    onFrame: onFrame
                )
            )
        }

        func readSafeAreaInsets(
            onSafeAreaInsets: @escaping (EdgeInsets) -> Void
        ) -> some View {
            modifier(
                ReadSafeAreaInsetsModifier(
                    onSafeAreaInsets: onSafeAreaInsets
                )
            )
        }

        /// Type-erases a View
        var erasedToAnyView: AnyView {
            AnyView(self)
        }
    }

    struct ViewFrameInfo: Equatable {
        var frame: CGRect = .zero
        var safeAreaInsets: EdgeInsets = .init()
    }

    private struct ReadFrameModifier: ViewModifier {
        /// Helper for notifying parents for child view frame changes
        struct FramePreferenceKey: PreferenceKey {
            static var defaultValue: CGRect = .zero
            static func reduce(value _: inout CGRect, nextValue _: () -> CGRect) {
                // nothing
            }
        }

        let coordinateSpace: CoordinateSpace
        let onFrame: (CGRect) -> Void

        func body(content: Content) -> some View {
            content
                .background(
                    GeometryReader { proxy in
                        Color.clear
                            .preference(
                                key: FramePreferenceKey.self,
                                value: proxy.frame(in: coordinateSpace)
                            )
                    }
                )
                .onPreferenceChange(FramePreferenceKey.self, perform: onFrame)
        }
    }

    private struct ReadSafeAreaInsetsModifier: ViewModifier {
        /// Helper for notifying parents for child view frame changes
        struct SafeAreaInsetsPreferenceKey: PreferenceKey {
            static var defaultValue: EdgeInsets = .init()
            static func reduce(value _: inout EdgeInsets, nextValue _: () -> EdgeInsets) {
                // nothing
            }
        }

        let onSafeAreaInsets: (EdgeInsets) -> Void

        func body(content: Content) -> some View {
            content
                .background(
                    GeometryReader { proxy in
                        Color.clear
                            .preference(
                                key: SafeAreaInsetsPreferenceKey.self,
                                value: proxy.safeAreaInsets
                            )
                    }
                )
                .onPreferenceChange(SafeAreaInsetsPreferenceKey.self, perform: onSafeAreaInsets)
        }
    }
#endif
