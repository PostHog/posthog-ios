//
//  View+PostHogLabel.swift
//  PostHog
//
//  Created by Yiannis Josephides on 04/12/2024.
//

#if os(iOS) || targetEnvironment(macCatalyst)
    import SwiftUI

    /// SwiftUI autocapture labeling helpers.
    public extension View {
        /**
         Adds a custom label to this view for use with PostHog's auto-capture functionality.

         By setting a custom label, you can easily identify and filter interactions with this specific element in your analytics data.

         ### Usage
         ```swift
         struct ContentView: View {
            var body: some View {
                Button("Login") {
                    ...
                }
                .postHogLabel("loginButton")
              }
         }
         ```

         - Parameter label: A custom label that uniquely identifies the element for analytics purposes.
         - Returns: A modified view that applies the label to the underlying UIKit view when possible.
         */
        func postHogLabel(_ label: String?) -> some View {
            modifier(PostHogLabelTaggerViewModifier(label: label))
        }
    }

    private struct PostHogLabelTaggerViewModifier: ViewModifier {
        let label: String?

        func body(content: Content) -> some View {
            content
                .background(viewTagger)
        }

        @ViewBuilder
        private var viewTagger: some View {
            if let label {
                PostHogLabelViewTagger(label: label)
            }
        }
    }

    private struct PostHogLabelViewTagger: UIViewRepresentable {
        let label: String

        func makeUIView(context _: Context) -> PostHogLabelTaggerView {
            PostHogLabelTaggerView(label: label)
        }

        func updateUIView(_ view: PostHogLabelTaggerView, context _: Context) {
            view.label = label
            view.setNeedsLayout()
        }
    }

    final class PostHogLabelTaggerView: UIView {
        var label: String
        weak var taggedView: UIView?

        init(label: String) {
            self.label = label
            super.init(frame: .zero)
            isUserInteractionEnabled = false
            accessibilityElementsHidden = true
        }

        @available(*, unavailable)
        required init?(coder _: NSCoder) {
            label = ""
            super.init(frame: .zero)
            isUserInteractionEnabled = false
            accessibilityElementsHidden = true
        }

        override func layoutSubviews() {
            super.layoutSubviews()

            // try to find a "taggable" cousin view in hierarchy
            //
            // ### Why cousin view?
            //
            // Because of SwiftUI-to-UIKit view bridging:
            //
            //     OriginalView (SwiftUI)
            //       L SwiftUITextFieldRepresentable (ViewRepresentable)
            //           L UITextField (UIControl) <- we tag here
            //       L PostHogLabelViewTagger (ViewRepresentable)
            //           L PostHogLabelTaggerView (UIView) <- we are here
            //
            if let view = findCousinView(of: PostHogSwiftUITaggable.self),
               let window,
               !bounds.isEmpty,
               window.convert(bounds, from: self).insetBy(dx: -1, dy: -1).contains(window.convert(view.bounds, from: view)),
               window.convert(view.bounds, from: view).insetBy(dx: -1, dy: -1).contains(window.convert(bounds, from: self))
            {
                taggedView = view
                view.postHogLabel = label
            }
            // Pure SwiftUI elements use this marker's live bounds during tap resolution.
            // Do not tag a shared hosting ancestor: it can contain many labeled controls.
        }

        override func removeFromSuperview() {
            super.removeFromSuperview()
            // remove custom label when removed from hierarchy
            taggedView?.postHogLabel = nil
            taggedView = nil
        }

        private func findCousinView<T>(of _: T.Type) -> T? {
            for sibling in superview?.siblings() ?? [] {
                if let match = sibling.child(of: T.self) {
                    return match
                }
            }
            return nil
        }
    }

    // MARK: - Helpers

    private extension UIView {
        func siblings() -> [UIView] {
            superview?.subviews.reduce(into: []) { result, current in
                if current !== self { result.append(current) }
            } ?? []
        }

        func child<T>(of type: T.Type) -> T? {
            for child in subviews {
                if let curT = child as? T ?? child.child(of: type) {
                    return curT
                }
            }
            return nil
        }
    }

    protocol PostHogSwiftUITaggable: UIView { /**/ }

    extension UIControl: PostHogSwiftUITaggable { /**/ }
    extension UIPickerView: PostHogSwiftUITaggable { /**/ }
    extension UITextView: PostHogSwiftUITaggable { /**/ }
    extension UICollectionView: PostHogSwiftUITaggable { /**/ }
    extension UITableView: PostHogSwiftUITaggable { /**/ }

#endif
