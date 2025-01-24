//
//  PostHogSessionManager.swift
//  PostHog
//
//  Created by Manoel Aranda Neto on 28.08.24.
//

import Foundation

// only for internal use
// Do we need to expose this as public API? Could be internal static instead?
@objc public class PostHogSessionManager: NSObject {
    enum SessionIDChangeReason: String {
        case sessionIdEmpty = "Session id was empty"
        case sessionStart = "Session started"
        case sessionEnd = "Session ended"
        case sessionReset = "Session was reset"
        case sessionTimeout = "Session timed out"
        case sessionPastMaximumLength = "Session past maximum length"
        case customSessionId = "Custom session set"
    }

    @objc public static var shared: PostHogSessionManager {
        DI.main.sessionManager
    }

    // Private initializer to prevent multiple instances
    override init() {
        super.init()
        registerNotifications()
        registerApplicationSendEvent()
    }

    private var sessionId: String?
    private var sessionStartTimestamp: TimeInterval?
    private var sessionActivityTimestamp: TimeInterval?
    private let sessionLock = NSLock()
    private var isAppInBackground = true
    // 30 minutes in seconds
    private let sessionActivityThreshold: TimeInterval = 60 * 30
    // 24 hours in seconds
    private let sessionMaxLengthThreshold: TimeInterval = 24 * 60 * 60
    // Called when session id is cleared or changes
    var onSessionIdChanged: () -> Void = {}

    @objc public func setSessionId(_ sessionId: String) {
        setSessionIdInternal(sessionId, at: now(), reason: .customSessionId)
    }

    private func isNotReactNative() -> Bool {
        // for the RN SDK, the session is handled by the RN SDK itself
        postHogSdkName != "posthog-react-native"
    }

    /**
     Returns the current session id, and manages id rotation logic

     In addition, this method handles core session cycling logic including:
        - Creates a new session id when none exists (but only if app is foregrounded)
        - if `readOnly` is false
            - Rotates session after *30 minutes* of inactivity
            - Clears session after *30 minutes* of inactivity (when app is backgrounded)
        - Enforces a maximum session duration of *24 hours*

     - Parameters:
        - timeNow: Reference timestamp used for evaluating session expiry rules.
                  Defaults to current system time.
        - readOnly: When true, bypasses all session management logic and returns
                   the current session id without modifications.
                   Defaults to false.

     - Returns: Returns the existing session id, or a new one after performing validity checks
     */
    func getSessionId(
        at timeNow: Date = now(),
        readOnly: Bool = false
    ) -> String? {
        let timestamp = timeNow.timeIntervalSince1970
        let (currentSessionId, lastActive, sessionStart, isBackgrounded) = sessionLock.withLock {
            (sessionId, sessionActivityTimestamp, sessionStartTimestamp, isAppInBackground)
        }

        // RN manages its own session, just return session id
        guard isNotReactNative(), !readOnly else {
            return currentSessionId
        }

        // Create a new session id if empty
        if currentSessionId.isNilOrEmpty, !isBackgrounded {
            return rotateSession(force: true, at: timeNow, reason: .sessionIdEmpty)
        }

        // Check if session has passed maximum inactivity length
        if let lastActive, isExpired(timestamp, lastActive, sessionActivityThreshold) {
            return isBackgrounded
                ? clearSession(reason: .sessionTimeout)
                : rotateSession(at: timeNow, reason: .sessionTimeout)
        }

        // Check if session has passed maximum session length
        if let sessionStart, isExpired(timestamp, sessionStart, sessionMaxLengthThreshold) {
            return isBackgrounded
                ? clearSession(reason: .sessionPastMaximumLength)
                : rotateSession(at: timeNow, reason: .sessionPastMaximumLength)
        }

        return currentSessionId
    }

    func getNextSessionId() -> String? {
        // if this is RN, return the current session id
        guard isNotReactNative() else {
            return sessionLock.withLock { sessionId }
        }

        return rotateSession(force: true, at: now(), reason: .sessionStart)
    }

    /// Creates a new session id and sets timestamps
    func startSession(_ completion: (() -> Void)? = nil) {
        guard isNotReactNative() else { return }

        rotateSession(force: true, at: now(), reason: .sessionStart)
        completion?()
    }

    /// Clears current session id and timestamps
    func endSession(_ completion: (() -> Void)? = nil) {
        guard isNotReactNative() else { return }

        clearSession(reason: .sessionEnd)
        completion?()
    }

    /// Resets current session id and timestamps
    func resetSession() {
        guard isNotReactNative() else { return }

        rotateSession(force: true, at: now(), reason: .sessionReset)
    }

    /// Call this method to mark any user activity on this session
    func touchSession() {
        guard isNotReactNative() else { return }

        let timestamp = now().timeIntervalSince1970
        sessionLock.withLock {
            if sessionId != nil {
                sessionActivityTimestamp = timestamp
            }
        }
    }

    /**
     Rotates the current session id

     - Parameters:
     - force: When true, creates a new session ID if current one is empty
     - reason: The underlying reason behind this session ID rotation
     - Returns: a new session id
     */
    @discardableResult private func rotateSession(force: Bool = false, at timestamp: Date, reason: SessionIDChangeReason) -> String? {
        // only rotate when session is empty
        if !force {
            let currentSessionId = sessionLock.withLock { sessionId }
            if currentSessionId.isNilOrEmpty {
                return currentSessionId
            }
        }

        let newSessionId = UUID.v7().uuidString
        setSessionIdInternal(newSessionId, at: timestamp, reason: reason)
        return newSessionId
    }

    @discardableResult private func clearSession(reason: SessionIDChangeReason) -> String? {
        setSessionIdInternal(nil, at: nil, reason: reason)
        return nil
    }

    private func setSessionIdInternal(_ sessionId: String?, at timestamp: Date?, reason: SessionIDChangeReason) {
        let timestamp = timestamp?.timeIntervalSince1970

        sessionLock.withLock {
            self.sessionId = sessionId
            self.sessionStartTimestamp = timestamp
            self.sessionActivityTimestamp = timestamp
        }

        onSessionIdChanged()

        if let sessionId {
            hedgeLog("New session id created \(sessionId) (\(reason))")
        } else {
            hedgeLog("Session id cleared - reason: (\(reason))")
        }
    }

    private var didBecomeActiveToken: RegistrationToken?
    private var didEnterBackgroundToken: RegistrationToken?

    private func registerNotifications() {
        let lifecyclePublisher = DI.main.appLifecyclePublisher
        didBecomeActiveToken = lifecyclePublisher.onDidBecomeActive { [weak self] in
            guard let self, sessionLock.withLock({ self.isAppInBackground }) else {
                return
            }

            // we consider foregrounding an app an activity on the current session
            touchSession()
            sessionLock.withLock { self.isAppInBackground = false }
        }
        didEnterBackgroundToken = lifecyclePublisher.onDidEnterBackground { [weak self] in
            guard let self, !sessionLock.withLock({ self.isAppInBackground }) else {
                return
            }

            // we consider backgrounding the app an activity on the current session
            touchSession()
            sessionLock.withLock { self.isAppInBackground = true }
        }
    }

    private var applicationEventToken: RegistrationToken?

    private func registerApplicationSendEvent() {
        #if os(iOS) || os(tvOS)
            let applicationEventPublisher = DI.main.applicationEventPublisher
            applicationEventToken = applicationEventPublisher.onApplicationEvent { [weak self] _, _ in
                // update "last active" session
                // we want to keep track of the idle time, so we need to maintain a timestamp on the last interactions of the user with the app. UIEvents are a good place to do so since it means that the user is actively interacting with the app (e.g not just noise background activity)
                self?.touchSession()
            }
        #endif
    }

    private func isExpired(_ timeNow: TimeInterval, _ timeThen: TimeInterval, _ threshold: TimeInterval) -> Bool {
        max(timeNow - timeThen, 0) > threshold
    }
}
