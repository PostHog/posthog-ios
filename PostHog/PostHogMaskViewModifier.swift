//
//  PostHogMaskViewModifier.swift
//  PostHog
//
//  Created by Yiannis Josephides on 09/10/2024.
//

#if os(iOS) && canImport(SwiftUI)

    import SwiftUI

    public extension View {
        func postHogMask(_ isEnabled: Bool = true) -> some View {
            modifier(PostHogMaskViewModifier(enabled: isEnabled))
        }
    }

    private struct PostHogMaskViewTagger: UIViewRepresentable {
        func makeUIView(context _: Context) -> PostHogMaskViewTaggerView {
            PostHogMaskViewTaggerView()
        }

        func updateUIView(_: PostHogMaskViewTaggerView, context _: Context) {
            // nothing
        }
    }

    private struct PostHogMaskViewModifier: ViewModifier {
        let enabled: Bool

        func body(content: Content) -> some View {
            content.background(viewTagger)
        }

        @ViewBuilder
        private var viewTagger: some View {
            if enabled {
                PostHogMaskViewTagger()
            }
        }
    }

    private class PostHogMaskViewTaggerView: UIView {
        override func didMoveToSuperview() {
            super.didMoveToSuperview()
            // ### Why grandparent view?
            //
            // Because of SwiftUI-to-UIKit view bridging:
            //     OriginalView (SwiftUI) <- we tag here
            //       L PostHogMaskViewTagger (ViewRepresentable)
            //           L PostHogMaskViewTaggerView (UIView) <- we are here
            superview?.superview?.postHogNoCapture = true
        }
    }

    extension UIView {
        var postHogNoCapture: Bool {
            get { objc_getAssociatedObject(self, &AssociatedKeys.phNoCapture) as? Bool ?? false }
            set { objc_setAssociatedObject(self, &AssociatedKeys.phNoCapture, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC) }
        }
    }
#endif
