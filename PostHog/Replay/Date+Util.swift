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
@available(*, deprecated, message: "dateToMillis(_:) becomes SDK-internal in PostHog 4.0. Use Int64(date.timeIntervalSince1970 * 1000) instead. From 4.0, wrapper SDKs must import PostHog with @_spi(PostHogInternal) to use it.")
public func dateToMillis(_ date: Date) -> Int64 {
    date.toMillis()
}
