//
//  Float+Util.swift
//  PostHog
//
//  Created by Yiannis Josephides on 07/02/2025.
//

import Foundation

extension BinaryFloatingPoint {
    func toInt() -> Int? {
        guard isFinite else { return nil }
        guard self >= Self(Int.min), self <= Self(Int.max) else { return nil }
        // Since this is used primarily for UI size & position, rounding vs truncating makes sense
        return Int(rounded())
    }
}
