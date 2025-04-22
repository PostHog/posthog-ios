//
//  UtilsTest.swift
//  PostHog
//
//  Created by Yiannis Josephides on 07/02/2025.
//

import Foundation
import Testing

@testable import PostHog

@Suite("UtilsTest")
struct UtilsTest {
    @Suite("CGFloat Tests")
    struct CGFloatTests {
        @Test("safely converts NaN to Int")
        func safelyConvertsNanToInt() {
            let nanNumber = CGFloat.nan
            #expect(nanNumber.toInt() == 0)
        }

        @Test("safely converts Max to Int and deals with overflow")
        func safelyConvertsMaxToIntAndDealsWithOverflow() {
            let gfmNumber = CGFloat.greatestFiniteMagnitude
            #expect(gfmNumber.toInt() == Int.max)
        }

        @Test("safely converts to Int and rounds value")
        func safelyConvertsToIntAndRoundsValue() {
            let frNumber: CGFloat = 1234567890.5
            #expect(frNumber.toInt() == 1234567891)
        }
    }

    @Suite("Double Tests")
    struct DoubleTests {
        @Test("safely converts NaN to Int")
        func safelyConvertsNanToInt() {
            let nanNumber = Double.nan
            #expect(nanNumber.toInt() == 0)
        }

        @Test("safely converts Max to Int and deals with overflow")
        func safelyConvertsMaxToIntAndDealsWithOverflow() {
            let gfmNumber = Double.greatestFiniteMagnitude
            #expect(gfmNumber.toInt() == Int.max)
        }

        @Test("safely converts to Int and rounds value")
        func safelyConvertsToIntAndRoundsValue() {
            let frNumber = 1234567890.5
            #expect(frNumber.toInt() == 1234567891)
        }
    }

    @Suite("Date format tests")
    struct DateTests {
        @Test("can parse ISO8601 date with microsecond precision")
        func canParseISO8601DateWithMicroseconds() {
            let dateString = "2024-12-17T16:51:06.952123Z"
            let date = toISO8601Date(dateString)
            #expect(date != nil)
            let backToString = toISO8601String(date!)
            #expect(backToString == "2024-12-17T16:51:06.952Z")
        }

        @Test("can parse ISO8601 date with milliseconds precision")
        func canParseISO8601DateWithMilliseconds() {
            let dateString = "2024-12-17T16:51:06.952Z"
            let date = toISO8601Date(dateString)
            #expect(date != nil)
            let backToString = toISO8601String(date!)
            #expect(backToString == "2024-12-17T16:51:06.952Z")
        }

        @Test("can parse ISO8601 date with seconds precision")
        func canParseISO8601DateWithSeconds() {
            let dateString = "2024-12-12T18:58:22Z"
            let date = toISO8601Date(dateString)
            #expect(date != nil)
            let backToString = toISO8601String(date!)
            #expect(backToString == "2024-12-12T18:58:22.000Z")
        }

        @Test("converts date to ISO8601 string consistently")
        func convertsDateToISO8601StringConsistently() {
            let date = Date(timeIntervalSince1970: 1703174400) // 2023-12-21T16:00:00Z
            let dateString = toISO8601String(date)
            #expect(dateString == "2023-12-21T16:00:00.000Z")
        }
    }
}
