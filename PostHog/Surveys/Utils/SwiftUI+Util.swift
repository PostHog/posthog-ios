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
            onChange: @escaping (CGRect) -> Void
        ) -> some View {
            modifier(
                ReadFrameModifier(
                    coordinateSpace: coordinateSpace,
                    onChange: onChange
                )
            )
        }
        
        /// Type-erases a View
        var erasedToAnyView: AnyView {
          AnyView(self)
        }
    }

    private struct ReadFrameModifier: ViewModifier {
        /// Helper for notifying parents for child view frame changes
        struct FramePreferenceKey: PreferenceKey {
            static var defaultValue: CGRect = .zero
            static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
                value = nextValue()
            }
        }

        let coordinateSpace: CoordinateSpace
        let onChange: (CGRect) -> Void

        func body(content: Content) -> some View {
            content
                .background(frameReader)
                .onPreferenceChange(FramePreferenceKey.self, perform: onChange)
        }
        
        private var frameReader: some View {
            GeometryReader { proxy in
                Color.clear
                    .preference(
                        key: FramePreferenceKey.self,
                        value: proxy.frame(in: coordinateSpace)
                    )
            }
        }
    }
#endif
