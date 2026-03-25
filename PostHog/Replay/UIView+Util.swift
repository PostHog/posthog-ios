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
            // Check accessibilityIdentifier first (most common way to tag views)
            if let identifier = accessibilityIdentifier,
               identifier.range(of: "ph-no-capture", options: .caseInsensitive) != nil
            {
                return true
            }
            // read accessibilityLabel from the parent's view to skip the RCTRecursiveAccessibilityLabel on RN which is slow and may cause an endless loop
            // see https://github.com/facebook/react-native/issues/33084
            if let label = super.accessibilityLabel,
               label.range(of: "ph-no-capture", options: .caseInsensitive) != nil
            {
                return true
            }
            return false
        }

        func toImage() -> UIImage? {
            let bounds = self.bounds
            let size = bounds.size

            if !size.hasSize() {
                return nil
            }

            // Use native screen scale for best drawHierarchy performance.
            // Per Sentry's findings, using native scale avoids internal rescaling overhead
            // that occurs when drawHierarchy renders at a non-native scale.
            let nativeScale = (self as? UIWindow ?? window)?.screen.scale ?? 1

            // Use custom CGContext-based renderer that bypasses UIGraphicsImageRenderer overhead.
            // PostHogGraphicsImageRenderer is lightweight (just stores size + scale), so creating
            // a new one each time is cheap — the expensive work is inside image().
            let renderer = PostHogGraphicsImageRenderer(size: size, scale: nativeScale)
            return renderer.image { _ in
                /// Note: Always `false` for `afterScreenUpdates` since this will cause the screen to flicker
                drawHierarchy(in: bounds, afterScreenUpdates: false)
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
