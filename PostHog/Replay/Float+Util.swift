//
//  Float+Util.swift
//  PostHog
//
//  Created by Yiannis Josephides on 07/02/2025.
//

import Foundation

extension CGFloat {
    func toInt() -> Int {
        NSNumber(value: rounded()).intValue
    }
}

extension Double {
    func toInt() -> Int {
        NSNumber(value: rounded()).intValue
    }
}
