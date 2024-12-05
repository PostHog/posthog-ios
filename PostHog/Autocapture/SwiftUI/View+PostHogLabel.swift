//
//  View+PostHogLabel.swift
//  PostHog
//
//  Created by Yiannis Josephides on 04/12/2024.
//

#if os(iOS) || targetEnvironment(macCatalyst)
    import SwiftUI

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
         */
        func postHogLabel(_ label: String?) -> some View {
            modifier(PostHogLabelTaggerViewModifier(label: label))
        }
    }

    private struct PostHogLabelTaggerViewModifier: ViewModifier {
        let label: String?

        func body(content: Content) -> some View {
            content
                .background(PostHogLabelViewTagger(label: label))
        }
    }

    private struct PostHogLabelViewTagger: UIViewRepresentable {
        let label: String?

        func makeUIView(context _: Context) -> PostHogLabelTaggerView {
            PostHogLabelTaggerView(label: label)
        }

        func updateUIView(_: PostHogLabelTaggerView, context _: Context) {
            // nothing
        }
    }

    private class PostHogLabelTaggerView: UIView {
        private let label: String?

        init(label: String?) {
            self.label = label
            super.init(frame: .zero)
        }

        @available(*, unavailable)
        required init?(coder _: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        override func layoutSubviews() {
            super.didMoveToWindow()

            superview?.postHogNoCapture = true
            postHogNoCapture = true

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
            if let view = findCousinView(of: PostHogSwiftUITaggable.self) {
                view.postHogLabel = label
            } else {
                // just tag grandparent view
                //
                // ### Why grandparent view?
                //
                // Because of SwiftUI-to-UIKit view bridging:
                //     OriginalView (SwiftUI) <- we tag here
                //       L PostHogLabelViewTagger (ViewRepresentable)
                //           L PostHogLabelTaggerView (UIView) <- we are here
                //
                superview?.superview?.postHogLabel = label
            }
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
            superview?.subviews.reduce(into: []) { r, c in
                if c !== self { r.append(c) }
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
