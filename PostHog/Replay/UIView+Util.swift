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
            if let label = accessibilityLabel, !isNoCapture {
                isNoCapture = checkLabel(label)
            }

            return isNoCapture
        }

        private func checkLabel(_ label: String) -> Bool {
            label.lowercased().contains("ph-no-capture")
        }

        func toImage() -> UIImage? {
            // Avoid Rendering Offscreen Views
            let size = bounds.intersection(superview?.bounds ?? bounds).size

            if !size.hasSize() {
                return nil
            }

            let rendererFormat = UIGraphicsImageRendererFormat.default()
            // This can significantly improve rendering performance because the renderer won't need to
            // process transparency.
            rendererFormat.opaque = isOpaque
            rendererFormat.scale = 0.5
            let renderer = UIGraphicsImageRenderer(size: size, format: rendererFormat)

            let image = renderer.image { context in
                // Render the view's layer into the current context
                layer.render(in: context.cgContext)
            }

            return image
        }

        // you need this because of SwiftUI otherwise the coordinates always zeroed for some reason
        func toAbsoluteRect(_ parent: UIView) -> CGRect {
            convert(bounds, to: parent)
        }
    }
#endif
