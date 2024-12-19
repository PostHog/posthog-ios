//
//  PostHogMaskViewModifier.swift
//  PostHog
//
//  Created by Yiannis Josephides on 09/10/2024.
//

#if os(iOS) && canImport(SwiftUI)

    import SwiftUI

    public extension View {
        /**
         Marks a SwiftUI View to be masked in PostHog session replay recordings.

         There are cases where PostHog SDK will unintentionally mask some SwiftUI views.

         Because of the nature of how we intercept SwiftUI view hierarchy (and how it maps to UIKit),
         we can't always be 100% confident that a view should be masked and may accidentally mark a
         sensitive view as non-sensitive instead.

         Use this modifier to explicitly mask sensitive views in session replay recordings.

         For example:
         ```swift
         // This view will be masked in recordings
         SensitiveDataView()
            .postHogMask()

         // Conditionally mask based on a flag
         SensitiveDataView()
            .postHogMask(shouldMask)
         ```

         - Parameter isEnabled: Whether masking should be enabled. Defaults to true.
         - Returns: A modified view that will be masked in session replay recordings when enabled
         */
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
        private weak var maskedView: UIView?
        override func layoutSubviews() {
            super.layoutSubviews()
            // ### Why grandparent view?
            //
            // Because of SwiftUI-to-UIKit view bridging:
            //     OriginalView (SwiftUI) <- we tag here
            //       L PostHogMaskViewTagger (ViewRepresentable)
            //           L PostHogMaskViewTaggerView (UIView) <- we are here
            maskedView = superview?.superview
            superview?.superview?.postHogNoCapture = true
        }

        override func removeFromSuperview() {
            super.removeFromSuperview()
            maskedView?.postHogNoCapture = false
            maskedView = nil
        }
    }

    extension UIView {
        var postHogNoCapture: Bool {
            get { objc_getAssociatedObject(self, &AssociatedKeys.phNoCapture) as? Bool ?? false }
            set { objc_setAssociatedObject(self, &AssociatedKeys.phNoCapture, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC) }
        }
    }
#endif
