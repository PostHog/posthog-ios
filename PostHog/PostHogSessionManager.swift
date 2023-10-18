//
//  PostHogSessionManager.swift
//  PostHog
//
//  Created by Ben White on 08.02.23.
//

import Foundation

class PostHogSessionManager {
    private let storage: PostHogStorage!

    private let anonLock = NSLock()
    private let distinctLock = NSLock()
    private let sessionLock = NSLock()

    init(config: PostHogConfig) {
        storage = PostHogStorage(config)
    }

    let sessionChangeThreshold: Double = 1800

    public func getAnonymousId() -> String {
        var anonymousId: String?
        anonLock.withLock {
            anonymousId = storage.getString(forKey: .anonymousId)

            if anonymousId == nil {
                anonymousId = UUID().uuidString
                setAnonId(anonymousId ?? "")
            }
        }

        return anonymousId ?? ""
    }

    public func setAnonymousId(_ id: String) {
        anonLock.withLock {
            setAnonId(id)
        }
    }

    private func setAnonId(_ id: String) {
        storage.setString(forKey: .anonymousId, contents: id)
    }

    public func getDistinctId() -> String {
        var distinctId: String?
        distinctLock.withLock {
            distinctId = storage.getString(forKey: .distinctId) ?? getAnonymousId()
        }
        return distinctId ?? ""
    }

    public func setDistinctId(_ id: String) {
        distinctLock.withLock {
            storage.setString(forKey: .distinctId, contents: id)
        }
    }

    public func getSessionId() -> String {
        var sessionId: String?
        sessionLock.withLock {
            sessionId = getSesssionId()
        }
        return sessionId ?? ""
    }

    // Load the sessionId, ensuring it is rotated if expired
    private func getSesssionId(timestamp: TimeInterval? = nil) -> String {
        var sessionId = storage.getString(forKey: .sessionId)
        let sessionLastTimestamp = storage.getNumber(forKey: .sessionlastTimestamp) ?? 0
        let newTimestamp = Double(timestamp ?? Date().timeIntervalSince1970)

        if sessionId == nil || sessionLastTimestamp == 0 || (newTimestamp - sessionLastTimestamp) > sessionChangeThreshold {
            sessionId = UUID().uuidString
            storage.setString(forKey: .sessionId, contents: sessionId!)
            storage.setNumber(forKey: .sessionlastTimestamp, contents: newTimestamp)

            hedgeLog("Session expired - creating new session '\(sessionId!)'")
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: PostHog.didResetSessionNotification, object: sessionId)
            }
        }

        return sessionId ?? ""
    }

    public func resetSession() {
        sessionLock.withLock {
            storage.remove(key: .sessionId)
            storage.remove(key: .sessionlastTimestamp)
        }
    }
}
