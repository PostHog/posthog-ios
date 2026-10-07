//
//  PostHogTriggerPropertyFilters.swift
//  PostHog
//
//  Created on 06.10.26.
//

import CoreFoundation
import Foundation

func matchTriggerPropertyFilters(_ filters: [PostHogTriggerPropertyFilter]?,
                                 _ eventProperties: [String: Any?]?,
                                 _ personProperties: [String: Any?]?) -> Bool {
    guard let filters, !filters.isEmpty else { return true }

    return filters.allSatisfy { filter in
        let source = filter.type == "person" ? personProperties : eventProperties
        let propertyValue = source?[filter.key] ?? nil
        let filterOperator = filter.filterOperator ?? "exact"

        if propertyValue == nil || propertyValue is NSNull {
            return PostHogTriggerPropertyFilters.negativeOperators.contains(filterOperator)
        }

        guard let propertyValue,
              let comparison = PostHogTriggerPropertyFilters.comparisons[filterOperator],
              let filterValue = filter.value
        else { return false }

        return comparison(PostHogTriggerPropertyFilters.stringifiedValues(filterValue),
                          PostHogTriggerPropertyFilters.stringifiedValues(propertyValue))
    }
}

private enum PostHogTriggerPropertyFilters {
    static let negativeOperators: Set<String> = ["is_not", "not_icontains", "not_regex"]

    static let comparisons: [String: ([String], [String]) -> Bool] = [
        "exact": { targets, values in
            values.contains { value in targets.contains(value) }
        },
        "is_not": { targets, values in
            values.allSatisfy { value in targets.allSatisfy { $0 != value } }
        },
        "regex": { targets, values in
            values.contains { value in targets.contains { Self.matchesRegex(value, $0) } }
        },
        "not_regex": { targets, values in
            values.allSatisfy { value in targets.allSatisfy { !Self.matchesRegex(value, $0) } }
        },
        "icontains": { targets, values in
            values.contains { value in
                targets.contains { value.lowercased().contains($0.lowercased()) }
            }
        },
        "not_icontains": { targets, values in
            values.allSatisfy { value in
                targets.allSatisfy { !value.lowercased().contains($0.lowercased()) }
            }
        },
        "gt": { targets, values in
            values.contains { value in
                guard let number = Self.jsParseDouble(value) else { return false }
                return targets.contains { number > (Self.jsParseDouble($0) ?? Double.nan) }
            }
        },
        "lt": { targets, values in
            values.contains { value in
                guard let number = Self.jsParseDouble(value) else { return false }
                return targets.contains { number < (Self.jsParseDouble($0) ?? Double.nan) }
            }
        },
    ]

    private static func matchesRegex(_ value: String, _ pattern: String) -> Bool {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return false }
        return regex.firstMatch(in: value, range: NSRange(value.startIndex..., in: value)) != nil
    }

    static func stringifiedValues(_ value: Any) -> [String] {
        if let array = value as? [Any] {
            return array.map(jsStringValue)
        }
        return [jsStringValue(value)]
    }

    /// JS `String(value)`. Booleans arrive as `NSNumber`, so their CoreFoundation type tells them apart from numbers.
    private static func jsStringValue(_ value: Any) -> String {
        if let string = value as? String { return string }
        if let number = value as? NSNumber {
            if CFGetTypeID(number) == CFBooleanGetTypeID() {
                return number.boolValue ? "true" : "false"
            }
            return jsNumberString(number.doubleValue)
        }
        return String(describing: value)
    }

    private static func jsNumberString(_ value: Double) -> String {
        guard value.isFinite, value == value.rounded(), abs(value) < 1e21 else {
            return String(value)
        }
        if abs(value) <= Double(Int64.max) {
            return String(Int64(value))
        }
        return String(value)
    }

    private static func jsParseDouble(_ value: String) -> Double? {
        let trimmed = value.drop(while: { $0 == " " || $0 == "\t" || $0 == "\n" || $0 == "\r" || $0 == "\u{000B}" || $0 == "\u{000C}" })
        guard let regex = jsNumberPrefixRegex,
              let match = regex.firstMatch(in: String(trimmed), range: NSRange(trimmed.startIndex..., in: trimmed)),
              let range = Range(match.range, in: trimmed)
        else { return nil }
        return Double(trimmed[range])
    }

    private static let jsNumberPrefixRegex = try? NSRegularExpression(
        pattern: "^[+-]?(Infinity|\\d+\\.?\\d*([eE][+-]?\\d+)?|\\.\\d+([eE][+-]?\\d+)?)"
    )
}
