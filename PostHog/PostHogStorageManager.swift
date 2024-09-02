//
//  PostHogStorageManager.swift
//  PostHog
//
//  Created by Ben White on 08.02.23.
//

import Foundation

class PostHogStorageManager {
    private let storage: PostHogStorage!

    private let anonLock = NSLock()
    private let distinctLock = NSLock()
    private let idGen: (UUID) -> UUID

    private var distinctId: String?
    private var anonymousId: String?

    init(_ config: PostHogConfig) {
        storage = PostHogStorage(config)
        idGen = config.getAnonymousId
    }

    public func getAnonymousId() -> String {
        var anonymousId: String?
        anonLock.withLock {
            if self.anonymousId == nil {
                anonymousId = storage.getString(forKey: .anonymousId)
                // update the memory value
                self.anonymousId = anonymousId
            }

            if anonymousId == nil {
                let uuid = UUID.v7()
                anonymousId = idGen(uuid).uuidString
                setAnonId(anonymousId ?? "")
            }
        }

        return self.anonymousId ?? ""
    }

    public func setAnonymousId(_ id: String) {
        anonLock.withLock {
            setAnonId(id)
        }
    }

    private func setAnonId(_ id: String) {
        anonymousId = id
        storage.setString(forKey: .anonymousId, contents: id)
    }

    public func getDistinctId() -> String {
        var distinctId: String?
        distinctLock.withLock {
            if self.distinctId == nil {
                distinctId = storage.getString(forKey: .distinctId) ?? getAnonymousId()
                // update the memory value
                self.distinctId = distinctId
            }
        }
        return self.distinctId ?? ""
    }

    public func setDistinctId(_ id: String) {
        distinctLock.withLock {
            distinctId = id
            storage.setString(forKey: .distinctId, contents: id)
        }
    }

    public func reset() {
        distinctLock.withLock {
            storage.remove(key: .distinctId)
            distinctId = nil
        }
        anonLock.withLock {
            storage.remove(key: .anonymousId)
            anonymousId = nil
        }
    }
}
