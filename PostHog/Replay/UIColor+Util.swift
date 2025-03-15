//
//  UIColor+Util.swift
//  PostHog
//
//  Created by Manoel Aranda Neto on 21.03.24.
//
#if os(iOS) || os(visionOS)

    import Foundation
    import UIKit

    extension UIColor {
        func toRGBString() -> String? {
            cgColor.toRGBString()
        }
    }
#endif
