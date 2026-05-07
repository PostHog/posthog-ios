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
            self.lastScreenLock.withLock { self._lastScreenName = name }
        }
    }

    /// Releases the screen-view subscription and clears the cache.
    func detach() {
        screenViewToken = nil
        lastScreenLock.withLock { _lastScreenName = nil }
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
