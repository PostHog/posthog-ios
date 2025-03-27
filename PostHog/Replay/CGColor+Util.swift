//
//  CGColor+Util.swift
//  PostHog
//
//  Created by Manoel Aranda Neto on 21.03.24.
//

#if os(iOS)

    import Foundation
    import UIKit

    extension CGColor {
        func toRGBString() -> String? {
            // see dicussion: https://github.com/PostHog/posthog-ios/issues/226
            // Allow only CGColors with an intiialized value of `numberOfComponents` with a value in 3...4 range
            // Loading dynamic colors from storyboard sometimes leads to some random values for numberOfComponents like `105553118884896` which crashes the app
            guard
                3 ... 4 ~= numberOfComponents, // check range
                let components = components, // we now assume it's safe to access `components`
                components.count >= 3
            else {
                return nil
            }

            let red = Int(components[0] * 255)
            let green = Int(components[1] * 255)
            let blue = Int(components[2] * 255)

            return String(format: "#%02X%02X%02X", red, green, blue)
        }
    }
#endif
