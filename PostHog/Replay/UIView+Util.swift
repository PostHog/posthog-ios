//
//  UIView+Util.swift
//  PostHog
//
//  Created by Manoel Aranda Neto on 21.03.24.
//

#if os(iOS)
    import Foundation
    import UIKit

    extension UIView {
        func isVisible() -> Bool {
            if isHidden || alpha == 0 || frame == .zero {
                return false
            }
            return true
        }

        func isNoCapture() -> Bool {
            containsAccessibilityToken("ph-no-capture")
        }

        /// Whether this view is explicitly marked to be excluded from rage click detection.
        ///
        /// Set the `ph-no-rageclick` token on the view's `accessibilityIdentifier` (or
        /// `accessibilityLabel`) to opt a control out. Because it reads accessibility metadata, this
        /// also works for React Native (`accessibilityLabel`/`nativeID`) and Flutter (`Semantics`)
        /// hosts, which render through this same native SDK.
        func isNoRageClick() -> Bool {
            postHogNoRageClick || containsAccessibilityToken("ph-no-rageclick")
        }

        private func containsAccessibilityToken(_ token: String) -> Bool {
            if let identifier = accessibilityIdentifier, identifier.lowercased().contains(token) {
                return true
            }
            // read accessibilityLabel from the parent's view to skip the RCTRecursiveAccessibilityLabel on RN which is slow and may cause an endless loop
            // see https://github.com/facebook/react-native/issues/33084
            if let label = super.accessibilityLabel, label.lowercased().contains(token) {
                return true
            }
            return false
        }

        /// Backing flag for the SwiftUI `.postHogNoRageClick()` modifier.
        var postHogNoRageClick: Bool {
            get { objc_getAssociatedObject(self, &AssociatedKeys.phNoRageClick) as? Bool ?? false }
            set { objc_setAssociatedObject(self, &AssociatedKeys.phNoRageClick, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC) }
        }

        func toImage() -> UIImage? {
            let bounds = self.bounds
            let size = bounds.size

            if !size.hasSize() {
                return nil
            }

            // Use native screen scale for best drawHierarchy performance.
            // Using a non-native scale can trigger internal rescaling overhead.
            let nativeScale = (self as? UIWindow ?? window)?.screen.scale ?? 1
            let renderer = PostHogGraphicsImageRenderer(size: size, scale: nativeScale)

            return autoreleasepool {
                renderer.image { _ in
                    /// Note: Always `false` for `afterScreenUpdates` since this will cause the screen to flicker when a sensitive text field is visible on screen
                    /// This can potentially affect capturing a snapshot during a screen transition but we want the lesser of the two evils here
                    drawHierarchy(in: bounds, afterScreenUpdates: false)
                }
            }
        }

        // you need this because of SwiftUI otherwise the coordinates always zeroed for some reason
        func toAbsoluteRect(_ window: UIWindow?) -> CGRect {
            convert(bounds, to: window)
        }
    }

    extension CALayer {
        func toAbsoluteRect(_ window: UIWindow?) -> CGRect {
            convert(bounds, to: window?.layer)
        }
    }
#endif
