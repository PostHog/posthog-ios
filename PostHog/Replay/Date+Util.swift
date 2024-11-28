//
//  Date+Util.swift
//  PostHog
//
//  Created by Manoel Aranda Neto on 21.03.24.
//

import Foundation

extension Date {
    func toMillis() -> Int64 {
        Int64(timeIntervalSince1970 * 1000)
    }
}

public func dateToMillis(_ date: Date) -> Int64 {
    date.toMillis()
}
