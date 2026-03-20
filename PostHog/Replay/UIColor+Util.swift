//
//  UIColor+Util.swift
//  PostHog
//
//  Created by Manoel Aranda Neto on 21.03.24.
//
#if os(iOS)

    import Foundation
    import UIKit

    extension UIColor {
        func toRGBString() -> String? {
            cgColor.toRGBString()
        }
    }

#elseif os(macOS)

    import AppKit
    import Foundation

    extension NSColor {
        func toRGBString() -> String? {
            // Convert to sRGB color space first to ensure we can access RGB components
            guard let rgbColor = usingColorSpace(.sRGB) else {
                return cgColor.toRGBString()
            }
            return rgbColor.cgColor.toRGBString()
        }
    }

#endif
