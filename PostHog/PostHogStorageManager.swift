//
//  PostHogStorageManager.swift
//  PostHog
//
//  Created by Ben White on 08.02.23.
//

import Foundation

// Internal class to manage the storage metadata of the PostHog SDK
public class PostHogStorageManager {
    private let storage: PostHogStorage!

    private let anonLock = NSLock()
    private let distinctLock = NSLock()
    private let identifiedLock = NSLock()
    private let personProcessingLock = NSLock()
    private let idGen: (UUID) -> UUID

    private var distinctId: String?
    private var cachedDistinctId = false
    private var anonymousId: String?
    private var isIdentifiedValue: Bool?
    private var personProcessingEnabled: Bool?

    init(_ config: PostHogConfig) {
        storage = PostHogStorage(config)
        idGen = config.getAnonymousId
    }

    public func getAnonymousId() -> String {
        anonLock.withLock {
            if anonymousId == nil {
                var anonymousId = storage.getString(forKey: .anonymousId)

                if anonymousId == nil {
                    let uuid = UUID.v7()
                    anonymousId = idGen(uuid).uuidString
                    setAnonId(anonymousId ?? "")
                } else {
                    // update the memory value
                    self.anonymousId = anonymousId
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
            } else {
                // read from memory
                distinctId = self.distinctId
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

    public func isIdentified() -> Bool {
        identifiedLock.withLock {
            if isIdentifiedValue == nil {
                isIdentifiedValue = storage.getBool(forKey: .isIdentified) ?? (getDistinctId() != getAnonymousId())
            }
        }
        return isIdentifiedValue ?? false
    }

    public func setIdentified(_ isIdentified: Bool) {
        identifiedLock.withLock {
            isIdentifiedValue = isIdentified
            storage.setBool(forKey: .isIdentified, contents: isIdentified)
        }
    }

    public func isPersonProcessing() -> Bool {
        personProcessingLock.withLock {
            if personProcessingEnabled == nil {
                personProcessingEnabled = storage.getBool(forKey: .personProcessingEnabled) ?? false
            }
        }
        return personProcessingEnabled ?? false
    }

    public func setPersonProcessing(_ enable: Bool) {
        personProcessingLock.withLock {
            // only set if its different to avoid IO since this is called more often
            if self.personProcessingEnabled != enable {
                self.personProcessingEnabled = enable
                storage.setBool(forKey: .personProcessingEnabled, contents: enable)
            }
        }
    }

    public func reset(_ resetStorage: Bool = false) {
        // resetStorage is only used for testing, when the reset method is called,
        // the storage is also cleared, so we dont do here to not do it twice.
        distinctLock.withLock {
            distinctId = nil
            cachedDistinctId = false
            if resetStorage {
                storage.remove(key: .distinctId)
            }
        }
        anonLock.withLock {
            anonymousId = nil
            if resetStorage {
                storage.remove(key: .anonymousId)
            }
        }
        identifiedLock.withLock {
            isIdentifiedValue = nil
            if resetStorage {
                storage.remove(key: .isIdentified)
            }
        }
        personProcessingLock.withLock {
            personProcessingEnabled = nil
            if resetStorage {
                storage.remove(key: .personProcessingEnabled)
            }
        }
    }
}
