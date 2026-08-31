//
//  SwiftUI+Util.swift
//  PostHog
//
//  Created by Ioannis Josephides on 10/03/2025.
//

#if os(iOS)
    import SwiftUI

    extension View {
        /// Reads frame changes of current view in a coordinate space (default global)
        @available(iOS 14.0, *)
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

        /// Reads current view's safe area insets
        @available(iOS 14.0, *)
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

    @available(iOS 14.0, *)
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

    @available(iOS 14.0, *)
    private struct ReadSafeAreaInsetsModifier: ViewModifier {
        /// Helper for notifying parents for child view's safe area insets
        struct SafeAreaInsetsPreferenceKey: PreferenceKey {
            static var defaultValue: EdgeInsets = .init()
            static func reduce(value _: inout EdgeInsets, nextValue _: () -> EdgeInsets) {
                // nothing
            }
        }

        let onSafeAreaInsets: (EdgeInsets) -> Void

        @State private var safeAreaInsets: EdgeInsets = .init()

        func body(content: Content) -> some View {
            ZStack {
                content
                    .background(
                        GeometryReader { proxy in
                            Color.clear
                                .onChange(of: proxy.safeAreaInsets) { size in
                                    safeAreaInsets = size
                                }
                                .preference(
                                    key: SafeAreaInsetsPreferenceKey.self,
                                    value: safeAreaInsets
                                )
                        }
                    )
            }
            .onPreferenceChange(SafeAreaInsetsPreferenceKey.self, perform: onSafeAreaInsets)
        }
    }
#endif
