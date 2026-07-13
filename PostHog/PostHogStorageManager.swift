//
//  PostHogStorageManager.swift
//  PostHog
//
//  Created by Ben White on 08.02.23.
//

import Foundation

/// Manages persisted identity metadata for a PostHog SDK instance.
///
/// - Warning: This class is public for backwards compatibility, but is intended for
///   SDK-internal use only. Application code should use `PostHogSDK` identity APIs
///   instead of interacting with storage directly.
public class PostHogStorageManager {
    private let storage: PostHogStorage!

    private let anonLock = NSLock()
    private let distinctLock = NSLock()
    private let deviceIdLock = NSLock()
    private let identifiedLock = NSLock()
    private let personProcessingLock = NSLock()
    private let idGen: (UUID) -> UUID

    private var distinctId: String?
    private var cachedDistinctId = false
    private var anonymousId: String?
    private var deviceId: String?
    private var isIdentifiedValue: Bool?
    private var personProcessingEnabled: Bool?

    init(_ config: PostHogConfig) {
        storage = PostHogStorage(config)
        idGen = config.getAnonymousId
        applyBootstrapIfNeeded(config.bootstrap)
    }

    /// Persists the bootstrap distinct ID exactly once, on the very first launch with no
    /// per-device state. Skipped when the device already has an anonymous ID on disk,
    /// when the user is already identified, or when the caller did not supply one.
    ///
    /// When `bootstrap.isIdentifiedID` is `true`, the value is treated as the
    /// already-identified distinct ID — both `.anonymousId` and `.distinctId` are seeded
    /// to the same value and `isIdentified` is set, so subsequent events are emitted on
    /// the identified person without an `$identify` merge.
    private func applyBootstrapIfNeeded(_ bootstrap: PostHogBootstrap?) {
        guard let bootstrap, let bootstrapId = bootstrap.distinctID, !bootstrapId.isEmpty else {
            return
        }
        // Persisted state wins — never override an existing anonymous ID, and never
        // re-link traffic across a previous anon→identified merge.
        if storage.getString(forKey: .anonymousId) != nil { return }
        if storage.getBool(forKey: .isIdentified) == true { return }

        setAnonymousId(bootstrapId)

        if bootstrap.isIdentifiedID {
            setDistinctId(bootstrapId)
            setIdentified(true)
        }
    }

    /// Returns the persisted anonymous ID, creating one if needed.
    ///
    /// - Returns: The anonymous ID for this install.
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

    /// Persists an anonymous ID.
    ///
    /// - Parameter id: Anonymous ID to store.
    public func setAnonymousId(_ id: String) {
        anonLock.withLock {
            setAnonId(id)
        }
    }

    private func setAnonId(_ id: String) {
        anonymousId = id
        storage.setString(forKey: .anonymousId, contents: id)
    }

    /// Returns the stable device identifier used for device-level feature flag bucketing.
    ///
    /// This ID persists across `identify()` and `reset()` calls, only changing on a fresh
    /// app install or manual cache clearing.
    ///
    /// - Returns: The stable device ID for this install.
    public func getDeviceId() -> String {
        deviceIdLock.withLock {
            if deviceId == nil {
                deviceId = storage.getString(forKey: .deviceId)

                if deviceId == nil {
                    // Lazy init for upgrades: existing installs won't have a device_id yet,
                    // so seed it from the current anonymous ID.
                    let anonId = getAnonymousId()
                    deviceId = anonId
                    storage.setString(forKey: .deviceId, contents: anonId)
                }
            }
        }
        return deviceId ?? ""
    }

    /// Returns the persisted distinct ID, falling back to the anonymous ID.
    ///
    /// - Returns: The current distinct ID.
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

    /// Persists the current distinct ID.
    ///
    /// - Parameter id: Distinct ID to store.
    public func setDistinctId(_ id: String) {
        distinctLock.withLock {
            distinctId = id
            storage.setString(forKey: .distinctId, contents: id)
        }
    }

    /// Returns whether the current distinct ID is identified.
    ///
    /// - Returns: `true` after a successful identify flow, otherwise `false`.
    public func isIdentified() -> Bool {
        identifiedLock.withLock {
            if isIdentifiedValue == nil {
                isIdentifiedValue = storage.getBool(forKey: .isIdentified) ?? (getDistinctId() != getAnonymousId())
            }
        }
        return isIdentifiedValue ?? false
    }

    /// Persists whether the current distinct ID is identified.
    ///
    /// - Parameter isIdentified: New identified state.
    public func setIdentified(_ isIdentified: Bool) {
        identifiedLock.withLock {
            isIdentifiedValue = isIdentified
            storage.setBool(forKey: .isIdentified, contents: isIdentified)
        }
    }

    /// Returns whether person profile processing has been enabled locally.
    ///
    /// - Returns: `true` when identified/person processing has been activated.
    public func isPersonProcessing() -> Bool {
        personProcessingLock.withLock {
            if personProcessingEnabled == nil {
                personProcessingEnabled = storage.getBool(forKey: .personProcessingEnabled) ?? false
            }
        }
        return personProcessingEnabled ?? false
    }

    /// Persists whether person profile processing is enabled locally.
    ///
    /// - Parameter enable: New person-processing state.
    public func setPersonProcessing(_ enable: Bool) {
        personProcessingLock.withLock {
            // only set if its different to avoid IO since this is called more often
            if self.personProcessingEnabled != enable {
                self.personProcessingEnabled = enable
                storage.setBool(forKey: .personProcessingEnabled, contents: enable)
            }
        }
    }

    /// Clears cached identity metadata and optionally removes persisted values.
    ///
    /// - Parameters:
    ///   - keepAnonymousId: Whether to keep the current anonymous ID cached and persisted.
    ///   - resetStorage: Whether to remove values from the backing store as well as memory.
    public func reset(keepAnonymousId: Bool = false, _ resetStorage: Bool = false) {
        // resetStorage is only used for testing, when the reset method is called,
        // the storage is also cleared, so we don't do here to not do it twice.
        distinctLock.withLock {
            distinctId = nil
            cachedDistinctId = false
            if resetStorage {
                storage.remove(key: .distinctId)
            }
        }

        if !keepAnonymousId {
            anonLock.withLock {
                anonymousId = nil
                if resetStorage {
                    storage.remove(key: .anonymousId)
                }
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
