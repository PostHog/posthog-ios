//
//  PostHogMaskViewModifier.swift
//  PostHog
//
//  Created by Yiannis Josephides on 09/10/2024.
//

#if os(iOS) && canImport(SwiftUI)

    import SwiftUI

    public extension View {
        func postHogMask(_ value: Bool = true) -> some View {
            modifier(PostHogMaskViewModifier(enabled: value))
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
            superview?.phIsManuallyMasked = true
        }
    }

    private var phIsManuallyMaskedKey: UInt8 = 0
    extension UIView {
        var phIsManuallyMasked: Bool {
            get {
                objc_getAssociatedObject(self, &phIsManuallyMaskedKey) as? Bool ?? false
            }

            set {
                objc_setAssociatedObject(
                    self,
                    &phIsManuallyMaskedKey,
                    newValue as Bool?,
                    .OBJC_ASSOCIATION_RETAIN_NONATOMIC
                )
            }
        }
    }
#endif
