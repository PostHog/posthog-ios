//
//  CGColor+Util.swift
//  PostHog
//
//  Created by Manoel Aranda Neto on 21.03.24.
//

#if os(iOS)

    import Foundation
    import UIKit

    // Pre-computed hex character lookup for fast color string formatting
    private let hexChars: [Character] = Array("0123456789ABCDEF")

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

            let r = min(255, max(0, Int(components[0] * 255)))
            let g = min(255, max(0, Int(components[1] * 255)))
            let b = min(255, max(0, Int(components[2] * 255)))

            // Build hex string directly — avoids String(format:) overhead
            return String([
                "#",
                hexChars[r >> 4], hexChars[r & 0xF],
                hexChars[g >> 4], hexChars[g & 0xF],
                hexChars[b >> 4], hexChars[b & 0xF],
            ])
        }
    }
#endif
