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
            if let identifier = accessibilityIdentifier {
                return identifier.lowercased().contains("ph-no-capture")
            }

            return false
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
    }
#endif
