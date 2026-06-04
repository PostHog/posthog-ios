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

/// Converts a date to milliseconds since the Unix epoch.
///
/// - Parameter date: Date to convert.
/// - Returns: Milliseconds since 1970-01-01 00:00:00 UTC.
public func dateToMillis(_ date: Date) -> Int64 {
    date.toMillis()
}
