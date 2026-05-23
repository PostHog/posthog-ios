//
//  PostHogScreenNameSanitizer.swift
//  PostHog
//

import Foundation

enum PostHogScreenNameSanitizer {
    /// Strips SwiftUI's `UIHostingController` / `ModifiedContent` wrappers to
    /// surface the user's actual view type. Empty inputs always return `nil`.
    /// An `AnyView` result is dropped only when it surfaced from stripping
    /// (auto-capture noise from `body: some View` erasure); a caller who
    /// manually passes `"AnyView"` is honored as-is.
    static func sanitize(rawScreenName name: String) -> String? {
        var current = name
        var didStrip = false
        if let inner = stripGeneric(current, wrapper: "UIHostingController") {
            current = inner
            didStrip = true
        }
        while let inner = stripGeneric(current, wrapper: "ModifiedContent"),
              let firstArg = firstGenericArgument(inner)
        {
            current = firstArg
            didStrip = true
        }
        if current.isEmpty { return nil }
        if didStrip, current == "AnyView" { return nil }
        return current
    }

    /// Returns the body of `wrapper<…>` if `string` matches that exact shape
    /// (no trailing junk after the closing `>`). nil otherwise.
    private static func stripGeneric(_ string: String, wrapper: String) -> String? {
        let prefix = wrapper + "<"
        guard string.hasPrefix(prefix), string.hasSuffix(">") else { return nil }
        let start = string.index(string.startIndex, offsetBy: prefix.count)
        let end = string.index(before: string.endIndex)
        return String(string[start ..< end])
    }

    /// Returns the first comma-separated generic argument from a body string,
    /// respecting nested `<…>` so `ModifiedContent<X, Y>, B` splits at the
    /// outer comma. Returns the input trimmed if there's no top-level comma.
    private static func firstGenericArgument(_ string: String) -> String? {
        var depth = 0
        for (offset, char) in string.enumerated() {
            if char == "<" {
                depth += 1
            } else if char == ">" {
                depth -= 1
            } else if char == ",", depth == 0 {
                let idx = string.index(string.startIndex, offsetBy: offset)
                return String(string[..<idx]).trimmingCharacters(in: .whitespaces)
            }
        }
        let trimmed = string.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? nil : trimmed
    }
}
