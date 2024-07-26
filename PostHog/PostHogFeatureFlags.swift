//
//  PostHogFeatureFlags.swift
//  PostHog
//
//  Created by Manoel Aranda Neto on 10.10.23.
//

import Foundation

class PostHogFeatureFlags {
    private let config: PostHogConfig
    private let storage: PostHogStorage
    private let api: PostHogApi

    private let loadingLock = NSLock()
    private let featureFlagsLock = NSLock()
    private var loadingFeatureFlags = false
    private var sessionReplayFlagActive = false

    private let dispatchQueue = DispatchQueue(label: "com.posthog.FeatureFlags",
                                              target: .global(qos: .utility))

    init(_ config: PostHogConfig,
         _ storage: PostHogStorage,
         _ api: PostHogApi)
    {
        self.config = config
        self.storage = storage
        self.api = api

        preloadSesssionReplayFlag()
    }

    private func preloadSesssionReplayFlag() {
        var sessionReplay: [String: Any]?
        featureFlagsLock.withLock {
            sessionReplay = self.storage.getDictionary(forKey: .sessionReplay) as? [String: Any]
        }

        if sessionReplay != nil {
            sessionReplayFlagActive = true
        }
    }

    func loadFeatureFlags(
        distinctId: String,
        anonymousId: String,
        groups: [String: String],
        callback: @escaping () -> Void
    ) {
        loadingLock.withLock {
            if self.loadingFeatureFlags {
                return
            }
            self.loadingFeatureFlags = true
        }

        api.decide(distinctId: distinctId,
                   anonymousId: anonymousId,
                   groups: groups)
        { data, _ in
            self.dispatchQueue.async {
                guard let featureFlags = data?["featureFlags"] as? [String: Any],
                      let featureFlagPayloads = data?["featureFlagPayloads"] as? [String: Any]
                else {
                    hedgeLog("Error: Decide response missing correct featureFlags format")

                    self.notifyAndRelease()

                    return callback()
                }
                let errorsWhileComputingFlags = data?["errorsWhileComputingFlags"] as? Bool ?? false

                #if os(iOS)
                    if let sessionRecording = data?["sessionRecording"] as? Bool {
                        self.sessionReplayFlagActive = sessionRecording

                        // its always false here anyway
                        if !sessionRecording {
                            self.storage.remove(key: .sessionReplay)
                        }

                    } else if let sessionRecording = data?["sessionRecording"] as? [String: Any] {
                        // keeps the value from config.sessionReplay since having sessionRecording
                        // means its enabled on the project settings, but its only enabled
                        // when local config.sessionReplay is also enabled
                        if let endpoint = sessionRecording["endpoint"] as? String {
                            self.config.snapshotEndpoint = endpoint
                        }
                        self.sessionReplayFlagActive = true
                        self.storage.setDictionary(forKey: .sessionReplay, contents: sessionRecording)
                    }
                #endif

                self.featureFlagsLock.withLock {
                    if errorsWhileComputingFlags {
                        let cachedFeatureFlags = self.storage.getDictionary(forKey: .enabledFeatureFlags) as? [String: Any] ?? [:]
                        let cachedFeatureFlagsPayloads = self.storage.getDictionary(forKey: .enabledFeatureFlagPayloads) as? [String: Any] ?? [:]

                        let newFeatureFlags = cachedFeatureFlags.merging(featureFlags) { _, new in new }
                        let newFeatureFlagsPayloads = cachedFeatureFlagsPayloads.merging(featureFlagPayloads) { _, new in new }

                        // if not all flags were computed, we upsert flags instead of replacing them
                        self.storage.setDictionary(forKey: .enabledFeatureFlags, contents: newFeatureFlags)
                        self.storage.setDictionary(forKey: .enabledFeatureFlagPayloads, contents: newFeatureFlagsPayloads)
                    } else {
                        self.storage.setDictionary(forKey: .enabledFeatureFlags, contents: featureFlags)
                        self.storage.setDictionary(forKey: .enabledFeatureFlagPayloads, contents: featureFlagPayloads)
                    }
                }

                self.notifyAndRelease()

                return callback()
            }
        }
    }

    private func notifyAndRelease() {
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: PostHogSDK.didReceiveFeatureFlags, object: nil)
        }

        loadingLock.withLock {
            self.loadingFeatureFlags = false
        }
    }

    func getFeatureFlags() -> [String: Any]? {
        var flags: [String: Any]?
        featureFlagsLock.withLock {
            flags = self.storage.getDictionary(forKey: .enabledFeatureFlags) as? [String: Any]
        }

        return flags
    }

    func isFeatureEnabled(_ key: String) -> Bool {
        var flags: [String: Any]?
        featureFlagsLock.withLock {
            flags = self.storage.getDictionary(forKey: .enabledFeatureFlags) as? [String: Any]
        }

        let value = flags?[key]

        if value != nil {
            let boolValue = value as? Bool
            if boolValue != nil {
                return boolValue!
            } else {
                return true
            }
        } else {
            return false
        }
    }

    func getFeatureFlag(_ key: String) -> Any? {
        var flags: [String: Any]?
        featureFlagsLock.withLock {
            flags = self.storage.getDictionary(forKey: .enabledFeatureFlags) as? [String: Any]
        }

        return flags?[key]
    }

    func getFeatureFlagPayload(_ key: String) -> Any? {
        var flags: [String: Any]?
        featureFlagsLock.withLock {
            flags = self.storage.getDictionary(forKey: .enabledFeatureFlagPayloads) as? [String: Any]
        }

        let value = flags?[key]

        guard let stringValue = value as? String else {
            return value
        }

        do {
            // The payload value is stored as a string and is not pre-parsed...
            // We need to mimic the JSON.parse of JS which is what posthog-js uses
            return try JSONSerialization.jsonObject(with: stringValue.data(using: .utf8)!, options: .fragmentsAllowed)
        } catch {
            hedgeLog("Error parsing the object \(String(describing: value)): \(error)")
        }

        // fallbak to original value if not possible to serialize
        return value
    }

    #if os(iOS)
        func isSessionReplayFlagActive() -> Bool {
            sessionReplayFlagActive
        }
    #endif
}
