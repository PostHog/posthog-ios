//
//  PostHogLogger.swift
//  PostHog
//

import Foundation

/// Convenience facade over `PostHogSDK.captureLog`. Each method is a one-liner
/// that calls `captureLog(_:level:attributes:)` with the matching level — kept
/// here only to give callers a `logger.info("...")` shape.
@objc public final class PostHogLogger: NSObject {
    private weak var sdk: PostHogSDK?

    init(sdk: PostHogSDK) {
        self.sdk = sdk
    }

    /// Capture a `.trace` record. Finest-grained detail; usually only enabled
    /// while diagnosing.
    @objc public func trace(_ body: String, attributes: [String: Any]? = nil) {
        sdk?.captureLog(body, level: .trace, attributes: attributes)
    }

    /// Capture a `.debug` record. Diagnostic detail useful during development.
    @objc public func debug(_ body: String, attributes: [String: Any]? = nil) {
        sdk?.captureLog(body, level: .debug, attributes: attributes)
    }

    /// Capture an `.info` record. Default level for regular runtime events.
    @objc public func info(_ body: String, attributes: [String: Any]? = nil) {
        sdk?.captureLog(body, level: .info, attributes: attributes)
    }

    /// Capture a `.warn` record. Something unexpected happened but the operation
    /// continued.
    @objc public func warn(_ body: String, attributes: [String: Any]? = nil) {
        sdk?.captureLog(body, level: .warn, attributes: attributes)
    }

    /// Capture an `.error` record. An operation failed; the app may continue.
    @objc public func error(_ body: String, attributes: [String: Any]? = nil) {
        sdk?.captureLog(body, level: .error, attributes: attributes)
    }

    /// Capture a `.fatal` record. An unrecoverable failure; the app likely
    /// cannot continue.
    @objc public func fatal(_ body: String, attributes: [String: Any]? = nil) {
        sdk?.captureLog(body, level: .fatal, attributes: attributes)
    }
}
