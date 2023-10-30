//
//  DateUtils.swift
//  PostHog
//
//  Created by Manoel Aranda Neto on 27.10.23.
//

import Foundation

public func toISO8601String(_ date: Date) -> String {
    let dateFormatter = DateFormatter()
    dateFormatter.dateFormat = "yyyy'-'MM'-'dd'T'HH':'mm':'ss.SSS'Z'"
    return dateFormatter.string(from: date)
}

public func toISO8601Date(_ date: String) -> Date? {
    let dateFormatter = DateFormatter()
    dateFormatter.dateFormat = "yyyy'-'MM'-'dd'T'HH':'mm':'ss.SSS'Z'"
    return dateFormatter.date(from: date)
}
