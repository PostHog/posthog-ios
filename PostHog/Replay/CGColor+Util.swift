//
//  CGColor+Util.swift
//  PostHog
//
//  Created by Manoel Aranda Neto on 21.03.24.
//

#if os(iOS) || os(tvOS)

    import Foundation
    import UIKit

    extension CGColor {
        func toRGBString() -> String? {
            guard let components = components, components.count >= 3 else {
                return nil
            }

            let r = Int(components[0] * 255)
            let g = Int(components[1] * 255)
            let b = Int(components[2] * 255)

            return String(format: "#%02X%02X%02X", r, g, b)
        }
    }
#endif
