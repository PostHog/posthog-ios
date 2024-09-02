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
    private var cachedDistinctId = false
    private var anonymousId: String?

    init(_ config: PostHogConfig) {
        storage = PostHogStorage(config)
        idGen = config.getAnonymousId
    }

    public func getAnonymousId() -> String {
        anonLock.withLock {
            if self.anonymousId == nil {
                var anonymousId = storage.getString(forKey: .anonymousId)

                if anonymousId == nil {
                    let uuid = UUID.v7()
                    anonymousId = idGen(uuid).uuidString
                    setAnonId(anonymousId ?? "")
                }
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
        anonymousId = id
        storage.setString(forKey: .anonymousId, contents: id)
    }

    public func getDistinctId() -> String {
        var distinctId: String?
        distinctLock.withLock {
            if self.distinctId == nil {
                // since distinctId is nil until its identified, no need to read from
                // cache every single time, otherwise anon users will never used the
                // cached values
                if !cachedDistinctId {
                    distinctId = storage.getString(forKey: .distinctId)
                    cachedDistinctId = true
                }

                // do this to not assign the AnonymousId to the DistinctId, its just a fallback
                if distinctId == nil {
                    distinctId = getAnonymousId()
                } else {
                    // update the memory value
                    self.distinctId = distinctId
                }
            }
        }
        return distinctId ?? ""
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
            cachedDistinctId = false
        }
        anonLock.withLock {
            storage.remove(key: .anonymousId)
            anonymousId = nil
        }
    }
}
