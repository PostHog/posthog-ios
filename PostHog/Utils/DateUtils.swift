//
//  DateUtils.swift
//  PostHog
//
//  Created by Manoel Aranda Neto on 27.10.23.
//

import Foundation

private func newDateFormatter() -> DateFormatter {
    let dateFormatter = DateFormatter()
    dateFormatter.locale = Locale(identifier: "en_US_POSIX")
    dateFormatter.timeZone = TimeZone(abbreviation: "UTC")

    dateFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSS'Z'"
    return dateFormatter
}

public func toISO8601String(_ date: Date) -> String {
    let dateFormatter = newDateFormatter()
    return dateFormatter.string(from: date)
}

public func toISO8601Date(_ date: String) -> Date? {
    let dateFormatter = newDateFormatter()
    return dateFormatter.date(from: date)
}

var now: () -> Date = { Date() }
