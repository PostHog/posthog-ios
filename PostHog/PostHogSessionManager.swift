//
//  PostHogSessionManager.swift
//  PostHog
//
//  Created by Manoel Aranda Neto on 28.08.24.
//

import Foundation

/// Manages the active PostHog session ID and session rotation state.
///
/// - Warning: This class is public for backwards compatibility, but is intended for
///   SDK-internal use only. Application code should use `PostHogSDK.getSessionId()`,
///   `startSession()`, and `endSession()` instead of interacting with this manager directly.
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

    /// Session manager used by `PostHogSDK.shared`.
    @objc public static var shared: PostHogSessionManager {
        PostHogSDK.shared.sessionManager
    }

    private var config: PostHogConfig?
    private var storage: PostHogStorage?

    override init() {
        super.init()
    }

    func setup(config: PostHogConfig, storage: PostHogStorage) {
        self.config = config
        self.storage = storage
        didBecomeActiveToken = nil
        didEnterBackgroundToken = nil
        applicationEventToken = nil
        // Seed from the publisher rather than relying on a future
        // didBecomeActive — NotificationCenter doesn't replay past events,
        // so a late setup() would otherwise stay stuck at the initial
        // `true` until the next foreground/background transition.
        let backgrounded = DI.main.appLifecyclePublisher.isInBackground
        sessionLock.withLock { isAppInBackground = backgrounded }
        restorePersistedSession()
        registerNotifications()
        registerApplicationSendEvent()
    }

    func reset() {
        resetSession()
        didBecomeActiveToken = nil
        didEnterBackgroundToken = nil
        applicationEventToken = nil
    }

    private let queue = DispatchQueue(label: "com.posthog.PostHogSessionManager", target: .global(qos: .utility))
    private var sessionId: String?
    private var sessionStartTimestamp: TimeInterval?
    private var sessionActivityTimestamp: TimeInterval?
    private let sessionLock = NSLock()
    private var isAppInBackground = true
    // 30 minutes in seconds
    private let sessionActivityThreshold: TimeInterval = 60 * 30
    // 24 hours in seconds
    private let sessionMaxLengthThreshold: TimeInterval = 24 * 60 * 60
    // Activity marks arrive on every UI event, so the persisted activity timestamp is
    // only rewritten this often. The idle window is 30 minutes, so a lag of a few
    // seconds cannot change whether a restored session is still alive.
    private let sessionPersistInterval: TimeInterval = 10
    private var lastPersistedActivityTimestamp: TimeInterval = 0
    /// callback for session ID changes
    var onSessionIdChanged = PostHogMulticastCallback<Void>()

    /// Overrides the current session ID.
    ///
    /// Use with care: changing the session ID affects analytics session attribution and session replay.
    ///
    /// - Parameter sessionId: Session ID to use for subsequent events.
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

    /// Thread-safe snapshot of the cached app-background flag. Safe to read
    /// from any thread.
    var isAppInBackgroundSnapshot: Bool {
        sessionLock.withLock { isAppInBackground }
    }

    func getNextSessionId() -> String? {
        // if this is RN, return the current session id
        guard isNotReactNative() else {
            return sessionLock.withLock { sessionId }
        }

        return rotateSession(force: true, at: now(), reason: .sessionStart)
    }

    /// Resumes the current session when it is still live, or creates a new session id
    func startSession(_ completion: (() -> Void)? = nil) {
        guard isNotReactNative() else { return }

        // A live session must survive an extra setup() or a background launch, so this only
        // creates an id when there is no live session. A session that is past its idle or
        // maximum length window is not live, so it is replaced instead of resumed.
        let timeNow = now()
        if !hasLiveSession(at: timeNow) {
            rotateSession(force: true, at: timeNow, reason: .sessionStart)
        }
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

        let (currentSessionId, lastActive) = sessionLock.withLock {
            (sessionId, sessionActivityTimestamp)
        }

        guard currentSessionId != nil else { return }

        let timeNow = now()
        let timestamp = timeNow.timeIntervalSince1970

        // Check if session has passed maximum inactivity length between user activity marks
        if let lastActive, isExpired(timestamp, lastActive, sessionActivityThreshold) {
            rotateSession(at: timeNow, reason: .sessionTimeout)
        } else {
            let needsPersist = sessionLock.withLock {
                sessionActivityTimestamp = timestamp
                return timestamp - lastPersistedActivityTimestamp >= sessionPersistInterval
            }
            if needsPersist {
                persistSession()
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

        let newSessionId = UUID.v7String()
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

        persistSession()
        onSessionIdChanged.invoke(())

        if let sessionId {
            hedgeLog("New session id created \(sessionId) (\(reason))")
        } else {
            hedgeLog("Session id cleared - reason: (\(reason))")
        }
    }

    // MARK: - Persistence

    private enum SessionStorageKey {
        static let sessionId = "sessionId"
        static let startTimestamp = "sessionStartTimestamp"
        static let activityTimestamp = "sessionActivityTimestamp"
    }

    /// Reads back the session left behind by the previous process and keeps it when it is
    /// still inside the idle and maximum length windows. Without this, every process launch
    /// starts a new session, however short the time away was.
    private func restorePersistedSession() {
        guard isNotReactNative(), let storage else { return }

        guard let stored = storage.getDictionary(forKey: .session),
              let storedSessionId = stored[SessionStorageKey.sessionId] as? String,
              !storedSessionId.isEmpty,
              let storedStart = stored[SessionStorageKey.startTimestamp] as? Double,
              let storedActivity = stored[SessionStorageKey.activityTimestamp] as? Double
        else {
            return
        }

        let timestamp = now().timeIntervalSince1970
        guard isWithinSessionWindows(timestamp, lastActive: storedActivity, sessionStart: storedStart) else {
            storage.remove(key: .session)
            return
        }

        sessionLock.withLock {
            sessionId = storedSessionId
            sessionStartTimestamp = storedStart
            sessionActivityTimestamp = storedActivity
            lastPersistedActivityTimestamp = storedActivity
        }

        hedgeLog("Restored session id \(storedSessionId) from storage")
    }

    /// Writes the current session to disk, or removes it when there is no active session.
    ///
    /// Holds `sessionLock` across the storage write, the same way `PostHogStorageManager` guards
    /// its own persisted values. Writing after the lock is released lets a concurrent
    /// `endSession()` or rotation land in between, so a stale record could survive on disk and be
    /// restored at the next launch. Callers must therefore not already hold the lock.
    private func persistSession() {
        guard let storage else { return }

        sessionLock.withLock {
            guard let currentSessionId = sessionId,
                  let start = sessionStartTimestamp,
                  let activity = sessionActivityTimestamp
            else {
                lastPersistedActivityTimestamp = 0
                storage.remove(key: .session)
                return
            }

            let contents: [String: Any] = [
                SessionStorageKey.sessionId: currentSessionId,
                SessionStorageKey.startTimestamp: start,
                SessionStorageKey.activityTimestamp: activity,
            ]
            lastPersistedActivityTimestamp = activity
            storage.setDictionary(forKey: .session, contents: contents)
        }
    }

    private var didBecomeActiveToken: RegistrationToken?
    private var didEnterBackgroundToken: RegistrationToken?

    private func registerNotifications() {
        let lifecyclePublisher = DI.main.appLifecyclePublisher
        didBecomeActiveToken = lifecyclePublisher.onDidBecomeActive.subscribe { [weak self] in
            guard let self, sessionLock.withLock({ self.isAppInBackground }) else {
                return
            }

            // we consider foregrounding an app an activity on the current session
            touchSession()
            sessionLock.withLock { self.isAppInBackground = false }
        }
        didEnterBackgroundToken = lifecyclePublisher.onDidEnterBackground.subscribe { [weak self] in
            guard let self, !sessionLock.withLock({ self.isAppInBackground }) else {
                return
            }

            // we consider backgrounding the app an activity on the current session
            touchSession()
            // The process can be killed while suspended, so flush the throttled activity
            // timestamp now rather than waiting for the next mark.
            persistSession()
            sessionLock.withLock { self.isAppInBackground = true }
        }
    }

    private var applicationEventToken: RegistrationToken?

    private func registerApplicationSendEvent() {
        #if os(iOS) || os(tvOS)
            guard let config, config.enableSwizzling else {
                return
            }
            applicationEventToken = DI.main.applicationEventPublisher.onApplicationEvent.subscribe { [weak self] _, _ in
                // update "last active" session
                // we want to keep track of the idle time, so we need to maintain a timestamp on the last interactions of the user with the app. UIEvents are a good place to do so since it means that the user is actively interacting with the app (e.g not just noise background activity)
                self?.queue.async {
                    self?.touchSession()
                }
            }
        #endif
    }

    private func isExpired(_ timeNow: TimeInterval, _ timeThen: TimeInterval, _ threshold: TimeInterval) -> Bool {
        max(timeNow - timeThen, 0) > threshold
    }

    /// True when a session with these timestamps is still inside both the idle window and the
    /// maximum length window. Shared by `startSession()` and the restore on `setup()`, so both
    /// judge a session by the same rules as `getSessionId(at:)`.
    private func isWithinSessionWindows(_ timeNow: TimeInterval, lastActive: TimeInterval, sessionStart: TimeInterval) -> Bool {
        !isExpired(timeNow, lastActive, sessionActivityThreshold)
            && !isExpired(timeNow, sessionStart, sessionMaxLengthThreshold)
    }

    /// True when there is a session id and it is still inside both session windows
    private func hasLiveSession(at timeNow: Date) -> Bool {
        let timestamp = timeNow.timeIntervalSince1970
        let (currentSessionId, lastActive, sessionStart) = sessionLock.withLock {
            (sessionId, sessionActivityTimestamp, sessionStartTimestamp)
        }

        guard !currentSessionId.isNilOrEmpty, let lastActive, let sessionStart else {
            return false
        }

        return isWithinSessionWindows(timestamp, lastActive: lastActive, sessionStart: sessionStart)
    }
}
