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
            // Begin image context
            UIGraphicsBeginImageContextWithOptions(bounds.size, isOpaque, 0.0)

            // Render the view's layer into the current context
            guard let context = UIGraphicsGetCurrentContext() else {
                UIGraphicsEndImageContext()
                return UIImage()
            }
            layer.render(in: context)

            // Capture the image from the current context
            let image = UIGraphicsGetImageFromCurrentImageContext()

            // End the image context
            UIGraphicsEndImageContext()

            return image
        }

        // you need this because of SwiftUI otherwise the coordinates always zeroed for some reason
        func toAbsoluteRect(_ parent: UIView) -> CGRect {
            convert(bounds, to: parent)
        }
    }
#endif
