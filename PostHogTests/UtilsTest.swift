//
//  UtilsTest.swift
//  PostHog
//
//  Created by Yiannis Josephides on 07/02/2025.
//

import Foundation
@testable import PostHog
import Testing

#if os(iOS)
    import UIKit
#endif

@Suite("UtilsTest")
struct UtilsTest {
    @Suite("CGFloat Tests")
    struct CGFloatTests {
        @Test("safely handles NaN value")
        func safelyConvertsNanToInt() {
            let nanNumber = CGFloat.nan
            #expect(nanNumber.toInt() == nil)
        }

        @Test("safely handles Max values")
        func safelyConvertsMaxToIntAndDealsWithOverflow() {
            let gfmNumber = CGFloat.greatestFiniteMagnitude
            #expect(gfmNumber.toInt() == nil)
        }

        @Test("safely handles infinity")
        func safelyHandlesInfinity() {
            let infNumber = CGFloat.infinity
            #expect(infNumber.toInt() == nil)
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
            #expect(nanNumber.toInt() == nil)
        }

        @Test("safely converts Max to Int and deals with overflow")
        func safelyConvertsMaxToIntAndDealsWithOverflow() {
            let gfmNumber = Double.greatestFiniteMagnitude
            #expect(gfmNumber.toInt() == nil)
        }

        @Test("safely handles infinity")
        func safelyHandlesInfinity() {
            let infNumber = Double.infinity
            #expect(infNumber.toInt() == nil)
        }

        @Test("safely converts to Int and rounds value")
        func safelyConvertsToIntAndRoundsValue() {
            let frNumber = 1234567890.5
            #expect(frNumber.toInt() == 1234567891)
        }
    }

    @Suite("Float Tests")
    struct FloatTests {
        @Test("safely converts NaN to Int")
        func safelyConvertsNanToInt() {
            let nanNumber = Float.nan
            #expect(nanNumber.toInt() == nil)
        }

        @Test("safely converts Max to Int and deals with overflow")
        func safelyConvertsMaxToIntAndDealsWithOverflow() {
            let gfmNumber = Float.greatestFiniteMagnitude
            #expect(gfmNumber.toInt() == nil)
        }

        @Test("safely handles infinity")
        func safelyHandlesInfinity() {
            let infNumber = Float.infinity
            #expect(infNumber.toInt() == nil)
        }

        @Test("safely converts to Int and rounds value")
        func safelyConvertsToIntAndRoundsValue() {
            let frNumber: Float = 123456.5
            #expect(frNumber.toInt() == 123457)
        }
    }

    #if os(iOS)
        @Suite("Survey color tests")
        struct SurveyColorTests {
            @Test(
                "hex colors are normalized by length",
                arguments: [
                    (hex: "#", expected: "000000ff"),
                    (hex: "#1", expected: "000001ff"),
                    (hex: "#12", expected: "000012ff"),
                    (hex: "#123", expected: "112233ff"),
                    (hex: "#1234", expected: "11223344"),
                    (hex: "#12345", expected: "012345ff"),
                    (hex: "#123456", expected: "123456ff"),
                    (hex: "#1234567", expected: "12345670"),
                    (hex: "#12345678", expected: "12345678"),
                    (hex: "#123456789", expected: "12345678"),
                    (hex: "#123456789abcdef", expected: "12345678"),
                ]
            )
            func normalizesHexColorsByLength(hex: String, expected: String) {
                let color = UIColor(hex: hex)

                #expect(color.hexDescription(true) == expected)
            }
        }
    #endif

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

    @Suite("Property sanitizing")
    struct SanitizeDictionaryTests {
        private let date = Date(timeIntervalSince1970: 1_700_000_000)

        private var dateString: String {
            ISO8601DateFormatter().string(from: date)
        }

        @Test("converts a top-level date and drops a value that cannot be serialized")
        func convertsTopLevelDateAndDropsUUID() {
            let sanitized = sanitizeDictionary([
                "when": date,
                "id": UUID(),
                "name": "ada",
            ])

            #expect(sanitized?["when"] as? String == dateString)
            #expect(sanitized?["name"] as? String == "ada")
            #expect(sanitized?["id"] == nil)
        }

        @Test("converts dates and URLs inside nested dictionaries and arrays")
        func convertsNestedDatesAndURLs() {
            let sanitized = sanitizeDictionary([
                "user": [
                    "name": "ada",
                    "joined": date,
                    "site": URL(string: "https://posthog.com")!,
                ] as [String: Any],
                "events": ["launch", date, true] as [Any],
            ])

            let user = sanitized?["user"] as? [String: Any]
            #expect(user?["name"] as? String == "ada")
            #expect(user?["joined"] as? String == dateString)
            #expect(user?["site"] as? String == "https://posthog.com")

            let events = sanitized?["events"] as? [Any]
            #expect(events?.count == 3)
            #expect(events?[0] as? String == "launch")
            #expect(events?[1] as? String == dateString)
            #expect(events?[2] as? Bool == true)
        }

        @Test("keeps an empty nested dictionary when every nested value is dropped")
        func keepsEmptyNestedDictionaryForWebParity() {
            let sanitized = sanitizeDictionary([
                "user": ["id": UUID()] as [String: Any],
                "name": "ada",
            ])

            let user = sanitized?["user"] as? [String: Any]
            #expect(user?.isEmpty == true)
            #expect(sanitized?["name"] as? String == "ada")
        }

        @Test("drops a nested array key when every item is non-serializable")
        func omitsNestedArrayWhenAllItemsDropped() {
            let sanitized = sanitizeDictionary([
                "tags": [UUID()] as [Any],
                "name": "ada",
            ])

            #expect(sanitized?["tags"] == nil)
            #expect(sanitized?["name"] as? String == "ada")
        }

        @Test("sanitizes mixed array items and drops non-serializable entries")
        func sanitizesMixedArrayItems() {
            let sanitized = sanitizeDictionary([
                "items": ["a", UUID(), date] as [Any],
            ])

            let items = sanitized?["items"] as? [Any]
            #expect(items?.count == 2)
            #expect(items?[0] as? String == "a")
            #expect(items?[1] as? String == dateString)
        }
    }
}
