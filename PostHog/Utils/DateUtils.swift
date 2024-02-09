//
//  DateUtils.swift
//  PostHog
//
//  Created by Manoel Aranda Neto on 27.10.23.
//

import Foundation

// returns 2024-02-09T10:53:53.781Z
public func toISO8601String(_ date: Date) -> String {
    let formatter = ISO8601DateFormatter()
//    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
//    formatter.string(from: date)
    
    let dateFormatter = DateFormatter()
    dateFormatter.locale = Locale(identifier: "en_US_POSIX")
    
    dateFormatter.dateFormat = "yyyy'-'MM'-'dd'T'HH':'mm':'ss.SSS'Z'"
    return dateFormatter.string(from: date)
}

public func toISO8601Date(_ date: String) -> Date? {
    let dateFormatter = DateFormatter()
    dateFormatter.dateFormat = "yyyy'-'MM'-'dd'T'HH':'mm':'ss.SSS'Z'"
    return dateFormatter.date(from: date)
}
