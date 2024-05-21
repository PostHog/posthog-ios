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
    private let idGen: (UUID) -> UUID

    init(_ config: PostHogConfig) {
        storage = PostHogStorage(config)
        idGen = config.getAnonymousId
    }

    public func getAnonymousId() -> String {
        var anonymousId: String?
        anonLock.withLock {
            anonymousId = storage.getString(forKey: .anonymousId)

            if anonymousId == nil {
                anonymousId = idGen(UUID()).uuidString
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

    public func reset() {
        distinctLock.withLock {
            storage.remove(key: .distinctId)
        }
        anonLock.withLock {
            storage.remove(key: .anonymousId)
        }
    }
}
