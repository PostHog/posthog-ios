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
            var visible = true
            DispatchQueue.main.sync {
                if isHidden || alpha == 0 || frame == .zero {
                    visible = false
                }
            }
            return visible
        }

        func isNoCapture() -> Bool {
            if let identifier = accessibilityIdentifier {
                return identifier.lowercased().contains("ph-no-capture")
            }

            return false
        }
    }
#endif
