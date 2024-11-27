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
            var isNoCapture = false
            if let identifier = accessibilityIdentifier {
                isNoCapture = checkLabel(identifier)
            }
            // read accessibilityLabel from the parent's view to skip the RCTRecursiveAccessibilityLabel on RN which is slow and may cause an endless loop
            // see https://github.com/facebook/react-native/issues/33084
            if let label = super.accessibilityLabel, !isNoCapture {
                isNoCapture = checkLabel(label)
            }

            return isNoCapture
        }

        private func checkLabel(_ label: String) -> Bool {
            label.lowercased().contains("ph-no-capture")
        }

        func toImage() -> UIImage? {
            // Avoid Rendering Offscreen Views
            let bounds = superview?.bounds ?? bounds
            let size = bounds.intersection(bounds).size

            if !size.hasSize() {
                return nil
            }

            let rendererFormat = UIGraphicsImageRendererFormat.default()

            // This can significantly improve rendering performance because the renderer won't need to
            // process transparency.
            rendererFormat.opaque = isOpaque
            // Another way to improve rendering performance is to scale the renderer's content.
            // rendererFormat.scale = 0.5
            let renderer = UIGraphicsImageRenderer(size: size, format: rendererFormat)

            let image = renderer.image { _ in
                // true for afterScreenUpdates so that we capture view *after* any pending animations are committed
                // As a side effect, we need to pause view tracker temporarily to avoid recursive calls since this option will cause subviews to layout, which will then trigger another capture
                ViewLayoutTracker.paused = true
                drawHierarchy(in: bounds, afterScreenUpdates: true)
                ViewLayoutTracker.paused = false
            }

            return image
        }

        // you need this because of SwiftUI otherwise the coordinates always zeroed for some reason
        func toAbsoluteRect(_ window: UIWindow?) -> CGRect {
            convert(bounds, to: window)
        }
    }
#endif
