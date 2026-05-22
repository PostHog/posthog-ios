//
//  PostHogLogger.swift
//  PostHog
//

import Foundation

/// Convenience facade for capturing log records. Use `PostHogSDK.shared.logger`
/// to call `trace`, `debug`, `info`, `warn`, `error`, or `fatal`.
@objc public final class PostHogLogger: NSObject {
    private weak var sdk: PostHogSDK?

    /// Latest reported screen name. Delegates to `PostHogSDK.lastScreenName`,
    /// which is sanitized in `screen()` before being cached.
    var lastScreenName: String? {
        sdk?.lastScreenName
    }

    init(sdk: PostHogSDK) {
        self.sdk = sdk
        super.init()
    }

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

    /// Capture a `.trace` record. Finest-grained detail; usually only enabled
    /// while diagnosing.
    @objc(traceWithBody:) public func trace(_ body: String) {
        sdk?.captureLog(body, level: .trace, attributes: nil)
    }

    /// Capture a `.trace` record with structured attributes.
    @objc(traceWithBody:attributes:) public func trace(_ body: String, attributes: [String: Any]? = nil) {
        sdk?.captureLog(body, level: .trace, attributes: attributes)
    }

    /// Capture a `.debug` record. Diagnostic detail useful during development.
    @objc(debugWithBody:) public func debug(_ body: String) {
        sdk?.captureLog(body, level: .debug, attributes: nil)
    }

    /// Capture a `.debug` record with structured attributes.
    @objc(debugWithBody:attributes:) public func debug(_ body: String, attributes: [String: Any]? = nil) {
        sdk?.captureLog(body, level: .debug, attributes: attributes)
    }

    /// Capture an `.info` record. Default level for regular runtime events.
    @objc(infoWithBody:) public func info(_ body: String) {
        sdk?.captureLog(body, level: .info, attributes: nil)
    }

    /// Capture an `.info` record with structured attributes.
    @objc(infoWithBody:attributes:) public func info(_ body: String, attributes: [String: Any]? = nil) {
        sdk?.captureLog(body, level: .info, attributes: attributes)
    }

    /// Capture a `.warn` record. Something unexpected happened but the operation
    /// continued.
    @objc(warnWithBody:) public func warn(_ body: String) {
        sdk?.captureLog(body, level: .warn, attributes: nil)
    }

    /// Capture a `.warn` record with structured attributes.
    @objc(warnWithBody:attributes:) public func warn(_ body: String, attributes: [String: Any]? = nil) {
        sdk?.captureLog(body, level: .warn, attributes: attributes)
    }

    /// Capture an `.error` record. An operation failed; the app may continue.
    @objc(errorWithBody:) public func error(_ body: String) {
        sdk?.captureLog(body, level: .error, attributes: nil)
    }

    /// Capture an `.error` record with structured attributes.
    @objc(errorWithBody:attributes:) public func error(_ body: String, attributes: [String: Any]? = nil) {
        sdk?.captureLog(body, level: .error, attributes: attributes)
    }

    /// Capture a `.fatal` record. An unrecoverable failure; the app likely
    /// cannot continue.
    @objc(fatalWithBody:) public func fatal(_ body: String) {
        sdk?.captureLog(body, level: .fatal, attributes: nil)
    }

    /// Capture a `.fatal` record with structured attributes.
    @objc(fatalWithBody:attributes:) public func fatal(_ body: String, attributes: [String: Any]? = nil) {
        sdk?.captureLog(body, level: .fatal, attributes: attributes)
    }
}
