//
//  DateUtils.swift
//  PostHog
//
//  Created by Manoel Aranda Neto on 27.10.23.
//

import Foundation

final class PostHogAPIDateFormatter {
    private static func getFormatter(with format: String) -> DateFormatter {
        let dateFormatter = DateFormatter()
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        dateFormatter.timeZone = TimeZone(abbreviation: "UTC")
        dateFormatter.dateFormat = format
        return dateFormatter
    }

    private let dateFormatterWithMilliseconds = getFormatter(with: "yyyy-MM-dd'T'HH:mm:ss.SSS'Z'")

    private let dateFormatterWithSeconds = getFormatter(with: "yyyy-MM-dd'T'HH:mm:ss'Z'")

    func string(from date: Date) -> String {
        dateFormatterWithMilliseconds.string(from: date)
    }

    func date(from string: String) -> Date? {
        dateFormatterWithMilliseconds.date(from: string)
            ?? dateFormatterWithSeconds.date(from: string)
    }
}

let apiDateFormatter = PostHogAPIDateFormatter()

/// Formats a date using the SDK's API timestamp format in UTC.
///
/// - Parameter date: Date to format.
/// - Returns: An ISO-8601-like timestamp string with milliseconds.
public func toISO8601String(_ date: Date) -> String {
    apiDateFormatter.string(from: date)
}

/// Parses a date string in the SDK's API timestamp format.
///
/// - Parameter date: Timestamp string with optional milliseconds.
/// - Returns: A parsed `Date`, or `nil` when the string is invalid.
public func toISO8601Date(_ date: String) -> Date? {
    apiDateFormatter.date(from: date)
}

let secondsPerDay: Double = 86400

var now: () -> Date = { Date() }

/// Current wall clock as a uint64 nanosecond string. OTLP/JSON encodes
/// uint64 as a string because JSON numbers cannot represent uint64 precisely.
func nanosNow() -> String {
    let secs = now().timeIntervalSince1970
    // Avoid Double precision loss at large magnitudes by splitting into
    // whole seconds + nanos within the second.
    let whole = UInt64(secs)
    let frac = secs - Double(whole)
    let nanosInSecond = UInt64(frac * 1_000_000_000)
    return "\(whole * 1_000_000_000 + nanosInSecond)"
}
