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

        func toImage(captureScale: CGFloat = 1) -> UIImage? {
            PostHogViewRenderer.capture(self, scale: captureScale)
        }

        // you need this because of SwiftUI otherwise the coordinates always zeroed for some reason
        func toAbsoluteRect(_ window: UIWindow?) -> CGRect {
            convert(bounds, to: window)
        }
    }
#endif
