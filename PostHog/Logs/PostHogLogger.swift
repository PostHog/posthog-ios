//
//  PostHogLogger.swift
//  PostHog
//

import Foundation

/// Convenience facade for capturing log records. Use `PostHogSDK.shared.logger`
/// to call `trace`, `debug`, `info`, `warn`, `error`, or `fatal`.
@objc public final class PostHogLogger: NSObject {
    private weak var sdk: PostHogSDK?
    private let lastScreenLock = NSLock()
    private var _lastScreenName: String?
    private var screenViewToken: RegistrationToken?

    /// Latest reported screen name, populated by the screen-view publisher.
    /// `nil` until the first navigation after SDK setup.
    var lastScreenName: String? {
        lastScreenLock.withLock { _lastScreenName }
    }

    init(sdk: PostHogSDK) {
        self.sdk = sdk
        super.init()
        screenViewToken = DI.main.screenViewPublisher.onScreenView.subscribe { [weak self] name in
            guard let self else { return }
            // Only overwrite when the sanitizer recovers something meaningful;
            // preserves the last useful name across noisy intermediate
            // viewDidAppears (e.g. the AnyView-wrapped HostingControllers
            // SwiftUI emits during initial layout).
            guard let cleaned = Self.sanitize(rawScreenName: name) else { return }
            self.lastScreenLock.withLock { self._lastScreenName = cleaned }
        }
    }

    /// Releases the screen-view subscription and clears the cache.
    func detach() {
        screenViewToken = nil
        lastScreenLock.withLock { _lastScreenName = nil }
    }

    /// Strips SwiftUI's `UIHostingController` / `ModifiedContent` wrappers to
    /// surface the user's actual view type. Returns `nil` when the inner type
    /// was erased to `AnyView` (no useful name to surface). UIKit class names
    /// pass through unchanged.
    static func sanitize(rawScreenName name: String) -> String? {
        var current = name
        if let inner = stripGeneric(current, wrapper: "UIHostingController") {
            current = inner
        }
        while let inner = stripGeneric(current, wrapper: "ModifiedContent"),
              let firstArg = firstGenericArgument(inner)
        {
            current = firstArg
        }
        if current.isEmpty || current == "AnyView" { return nil }
        return current
    }

    /// Returns the body of `wrapper<…>` if `s` matches that exact shape (no
    /// trailing junk after the closing `>`). nil otherwise.
    private static func stripGeneric(_ s: String, wrapper: String) -> String? {
        let prefix = wrapper + "<"
        guard s.hasPrefix(prefix), s.hasSuffix(">") else { return nil }
        let start = s.index(s.startIndex, offsetBy: prefix.count)
        let end = s.index(before: s.endIndex)
        return String(s[start ..< end])
    }

    /// Returns the first comma-separated generic argument from a body string,
    /// respecting nested `<…>` so `ModifiedContent<X, Y>, B` splits at the
    /// outer comma. Returns `s` trimmed if there's no top-level comma.
    private static func firstGenericArgument(_ s: String) -> String? {
        var depth = 0
        for (offset, ch) in s.enumerated() {
            if ch == "<" {
                depth += 1
            } else if ch == ">" {
                depth -= 1
            } else if ch == "," && depth == 0 {
                let idx = s.index(s.startIndex, offsetBy: offset)
                return String(s[..<idx]).trimmingCharacters(in: .whitespaces)
            }
        }
        let trimmed = s.trimmingCharacters(in: .whitespaces)
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
