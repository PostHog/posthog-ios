//
//  PostHogSessionManager.swift
//  PostHog
//
//  Created by Manoel Aranda Neto on 28.08.24.
//

import Foundation

class PostHogSessionManager {
    static let shared = PostHogSessionManager()

    // Private initializer to prevent multiple instances
    private init() {}

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

    func setSessionId(sessionId: String) {
        sessionLock.withLock {
            self.sessionId = sessionId
        }
    }

    func endSession() {
        sessionLock.withLock {
            sessionId = nil
            sessionLastTimestamp = nil
        }
    }

    private func isExpired(_ timeNow: TimeInterval, _ sessionLastTimestamp: TimeInterval) -> Bool {
        timeNow - sessionLastTimestamp > sessionChangeThreshold
    }

    func resetSessionIfExpired() {
        sessionLock.withLock {
            let timeNow = now().timeIntervalSince1970
            if sessionId != nil,
               let sessionLastTimestamp = sessionLastTimestamp,
               isExpired(timeNow, sessionLastTimestamp)
            {
                sessionId = nil
            }
        }
    }

    private func rotateSession() {
        let newSessionId = UUID.v7().uuidString
        let newSessionLastTimestamp = now().timeIntervalSince1970

        sessionId = newSessionId
        sessionLastTimestamp = newSessionLastTimestamp
    }

    func startSession() {
        sessionLock.withLock {
            // only start if there is no session
            if sessionId != nil {
                return
            }
            rotateSession()
        }
    }

    func rotateSessionIdIfRequired() {
        sessionLock.withLock {
            let timeNow = now().timeIntervalSince1970

            guard sessionId != nil, let sessionLastTimestamp = sessionLastTimestamp else {
                rotateSession()
                return
            }

            if isExpired(timeNow, sessionLastTimestamp) {
                rotateSession()
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
