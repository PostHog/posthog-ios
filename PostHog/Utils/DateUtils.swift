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

public func toISO8601String(_ date: Date) -> String {
    apiDateFormatter.string(from: date)
}

public func toISO8601Date(_ date: String) -> Date? {
    apiDateFormatter.date(from: date)
}

var now: () -> Date = { Date() }
