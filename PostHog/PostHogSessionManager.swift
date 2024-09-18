//
//  PostHogSessionManager.swift
//  PostHog
//
//  Created by Manoel Aranda Neto on 28.08.24.
//

import Foundation

// only for internal use
@objc public class PostHogSessionManager: NSObject {
    @objc public static let shared = PostHogSessionManager()

    // Private initializer to prevent multiple instances
    override private init() {}

    private var sessionId: String?
    private var sessionLastTimestamp: TimeInterval?
    private let sessionLock = NSLock()
    // 30 minutes in seconds
    private let sessionChangeThreshold: TimeInterval = 60 * 30

    func getSessionId() -> String? {
        var tempSessionId: String?
        sessionLock.withLock {
            tempSessionId = sessionId
        }
        return tempSessionId
    }

    @objc public func setSessionId(_ sessionId: String) {
        sessionLock.withLock {
            self.sessionId = sessionId
        }
    }

    func endSession(_ completion: () -> Void) {
        sessionLock.withLock {
            sessionId = nil
            sessionLastTimestamp = nil
            completion()
        }
    }

    private func isExpired(_ timeNow: TimeInterval, _ sessionLastTimestamp: TimeInterval) -> Bool {
        timeNow - sessionLastTimestamp > sessionChangeThreshold
    }

    func resetSessionIfExpired(_ completion: () -> Void) {
        sessionLock.withLock {
            let timeNow = now().timeIntervalSince1970
            if sessionId != nil,
               let sessionLastTimestamp = sessionLastTimestamp,
               isExpired(timeNow, sessionLastTimestamp)
            {
                sessionId = nil
                completion()
            }
        }
    }

    private func rotateSession(_ completion: (() -> Void)?) {
        let newSessionId = UUID.v7().uuidString
        let newSessionLastTimestamp = now().timeIntervalSince1970

        sessionId = newSessionId
        sessionLastTimestamp = newSessionLastTimestamp
        completion?()
    }

    func startSession(_ completion: (() -> Void)? = nil) {
        sessionLock.withLock {
            // only start if there is no session
            if sessionId != nil {
                return
            }
            rotateSession(completion)
        }
    }

    func rotateSessionIdIfRequired(_ completion: @escaping (() -> Void)) {
        sessionLock.withLock {
            let timeNow = now().timeIntervalSince1970

            guard sessionId != nil, let sessionLastTimestamp = sessionLastTimestamp else {
                rotateSession(completion)
                return
            }

            if isExpired(timeNow, sessionLastTimestamp) {
                rotateSession(completion)
            }
        }
    }

    func updateSessionLastTime() {
        sessionLock.withLock {
            sessionLastTimestamp = now().timeIntervalSince1970
        }
    }

    func isSessionActive() -> Bool {
        getSessionId() != nil
    }
}
