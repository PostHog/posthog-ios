//
//  PostHogRemoteConfig.swift
//  PostHog
//
//  Created by Manoel Aranda Neto on 10.10.23.
//

import Foundation

class PostHogRemoteConfig {
    private let hasFeatureFlagsKey = "hasFeatureFlags"
    
    private let config: PostHogConfig
    private let storage: PostHogStorage
    private let api: PostHogApi

    private let loadingFeatureFlagsLock = NSLock()
    private let featureFlagsLock = NSLock()
    private var loadingFeatureFlags = false
    private var sessionReplayFlagActive = false
    private var featureFlags: [String: Any]?

    private var remoteConfigLock = NSLock()
    private let loadingRemoteConfigLock = NSLock()
    private var loadingRemoteConfig = false
    private var remoteConfig: [String: Any]?
    private var hasFeatureFlags: Bool?
    private var remoteConfigDidFetch: Bool = false
    private var featureFlagPayloads: [String: Any]?

    /// Internal, only used for testing
    var canReloadFlagsForTesting = true
    var onRemoteConfigLoaded: (([String: Any]?) -> Void)?
    var onFeatureFlagsLoaded: (([String: Any]?) -> Void)?

    private let dispatchQueue = DispatchQueue(label: "com.posthog.RemoteConfig",
                                              target: .global(qos: .utility))

    init(_ config: PostHogConfig,
         _ storage: PostHogStorage,
         _ api: PostHogApi)
    {
        self.config = config
        self.storage = storage
        self.api = api

        preloadRemoteConfig()
        preloadFeatureFlags()
        preloadSessionReplayFlag()
    }

    private func preloadRemoteConfig() {
        remoteConfigLock.withLock {
            _ = getCachedRemoteConfig()
        }

        // may have already beed fetched from `loadFeatureFlags` call
        if remoteConfigLock.withLock({
            self.remoteConfig == nil || !self.remoteConfigDidFetch
        }) {
            dispatchQueue.async {
                self.reloadRemoteConfig()
            }
        }
    }

    private func preloadFeatureFlags() {
        featureFlagsLock.withLock {
            _ = getCachedFeatureFlags()
        }

        if config.preloadFeatureFlags {
            dispatchQueue.async {
                self.reloadFeatureFlags()
            }
        }
    }

    func reloadRemoteConfig(
        callback: (() -> Void)? = nil
    ) {
        loadingRemoteConfigLock.withLock {
            if self.loadingRemoteConfig {
                return
            }
            self.loadingRemoteConfig = true
        }

        api.remoteConfig { data, _ in

            if let data {
                self.onRemoteConfig(data)
            }

            self.loadingRemoteConfigLock.withLock {
                self.remoteConfigDidFetch = true
                self.loadingRemoteConfig = false
            }

            callback?()
        }
    }

    func reloadFeatureFlags(
        callback: (() -> Void)? = nil
    ) {
        guard canReloadFlagsForTesting else {
            return
        }

        guard let storageManager = config.storageManager else {
            return
        }

        let groups = featureFlagsLock.withLock { getGroups() }

        loadFeatureFlags(
            distinctId: storageManager.getDistinctId(),
            anonymousId: storageManager.getAnonymousId(),
            groups: groups,
            callback: callback ?? {}
        )
    }

    private func preloadSessionReplayFlag() {
        var sessionReplay: [String: Any]?
        var featureFlags: [String: Any]?
        featureFlagsLock.withLock {
            sessionReplay = self.storage.getDictionary(forKey: .sessionReplay) as? [String: Any]
            featureFlags = self.getCachedFeatureFlags()
        }

        if let sessionReplay = sessionReplay {
            sessionReplayFlagActive = isRecordingActive(featureFlags ?? [:], sessionReplay)

            if let endpoint = sessionReplay["endpoint"] as? String {
                config.snapshotEndpoint = endpoint
            }
        }
    }

    private func isRecordingActive(_ featureFlags: [String: Any], _ sessionRecording: [String: Any]) -> Bool {
        var recordingActive = true

        // check for boolean flags
        if let linkedFlag = sessionRecording["linkedFlag"] as? String,
           let value = featureFlags[linkedFlag] as? Bool
        {
            recordingActive = value
            // check for specific flag variant
        } else if let linkedFlag = sessionRecording["linkedFlag"] as? [String: Any],
                  let flag = linkedFlag["flag"] as? String,
                  let variant = linkedFlag["variant"] as? String,
                  let value = featureFlags[flag] as? String
        {
            recordingActive = value == variant
        }
        // check for multi flag variant (any)
        // if let linkedFlag = sessionRecording["linkedFlag"] as? String,
        //    featureFlags[linkedFlag] != nil
        // is also a valid check but since we cannot check the value of the flag,
        // we consider session recording is active

        return recordingActive
    }

    func loadFeatureFlags(
        distinctId: String,
        anonymousId: String,
        groups: [String: String],
        callback: @escaping () -> Void
    ) {
        if remoteConfigLock.withLock({ hasFeatureFlags == nil }) {
            // not cached or fetched yet
            reloadRemoteConfig {
                self.loadFeatureFlagsInternal(
                    distinctId: distinctId,
                    anonymousId: anonymousId,
                    groups: groups,
                    callback: callback
                )
            }
        } else {
            loadFeatureFlagsInternal(
                distinctId: distinctId,
                anonymousId: anonymousId,
                groups: groups,
                callback: callback
            )
        }
    }

    private func loadFeatureFlagsInternal(
        distinctId: String,
        anonymousId: String,
        groups: [String: String],
        callback: @escaping () -> Void
    ) {
        guard remoteConfigLock.withLock({ hasFeatureFlags == true }) else {
            hedgeLog("Remote config reported no feature flags. Skipping")
            return
        }

        loadingFeatureFlagsLock.withLock {
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

                    self.notifyFeatureFlagsAndRelease(data)

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
                        // when local replay integration is enabled/active
                        if let endpoint = sessionRecording["endpoint"] as? String {
                            self.config.snapshotEndpoint = endpoint
                        }
                        self.sessionReplayFlagActive = self.isRecordingActive(featureFlags, sessionRecording)
                        self.storage.setDictionary(forKey: .sessionReplay, contents: sessionRecording)
                    }
                #endif

                self.featureFlagsLock.withLock {
                    if errorsWhileComputingFlags {
                        let cachedFeatureFlags = self.getCachedFeatureFlags() ?? [:]
                        let cachedFeatureFlagsPayloads = self.getCachedFeatureFlagPayload() ?? [:]

                        let newFeatureFlags = cachedFeatureFlags.merging(featureFlags) { _, new in new }
                        let newFeatureFlagsPayloads = cachedFeatureFlagsPayloads.merging(featureFlagPayloads) { _, new in new }

                        // if not all flags were computed, we upsert flags instead of replacing them
                        self.setCachedFeatureFlags(newFeatureFlags)
                        self.setCachedFeatureFlagPayload(newFeatureFlagsPayloads)
                        self.notifyFeatureFlagsAndRelease(newFeatureFlags)
                    } else {
                        self.setCachedFeatureFlags(featureFlags)
                        self.setCachedFeatureFlagPayload(featureFlagPayloads)
                        self.notifyFeatureFlagsAndRelease(featureFlags)
                    }
                }

                return callback()
            }
        }
    }

    private func notifyFeatureFlagsAndRelease(_ featureFlags: [String: Any]?) {
        DispatchQueue.main.async {
            self.onFeatureFlagsLoaded?(featureFlags)
            NotificationCenter.default.post(name: PostHogSDK.didReceiveFeatureFlags, object: nil)
        }

        loadingFeatureFlagsLock.withLock {
            self.loadingFeatureFlags = false
        }
    }

    func getFeatureFlags() -> [String: Any]? {
        var flags: [String: Any]?
        featureFlagsLock.withLock {
            flags = self.getCachedFeatureFlags()
        }

        return flags
    }

    func isFeatureEnabled(_ key: String) -> Bool {
        var flags: [String: Any]?
        featureFlagsLock.withLock {
            flags = self.getCachedFeatureFlags()
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
            flags = self.getCachedFeatureFlags()
        }

        return flags?[key]
    }

    private func getCachedFeatureFlagPayload() -> [String: Any]? {
        if featureFlagPayloads == nil {
            featureFlagPayloads = storage.getDictionary(forKey: .enabledFeatureFlagPayloads) as? [String: Any]
        }
        return featureFlagPayloads
    }

    private func setCachedFeatureFlagPayload(_ featureFlagPayloads: [String: Any]) {
        self.featureFlagPayloads = featureFlagPayloads
        storage.setDictionary(forKey: .enabledFeatureFlagPayloads, contents: featureFlagPayloads)
    }

    private func getCachedFeatureFlags() -> [String: Any]? {
        if featureFlags == nil {
            featureFlags = storage.getDictionary(forKey: .enabledFeatureFlags) as? [String: Any]
        }
        return featureFlags
    }

    private func setCachedFeatureFlags(_ featureFlags: [String: Any]) {
        self.featureFlags = featureFlags
        storage.setDictionary(forKey: .enabledFeatureFlags, contents: featureFlags)
    }

    func getFeatureFlagPayload(_ key: String) -> Any? {
        var flags: [String: Any]?
        featureFlagsLock.withLock {
            flags = getCachedFeatureFlagPayload()
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

        // fallback to original value if not possible to serialize
        return value
    }

    #if os(iOS)
        func isSessionReplayFlagActive() -> Bool {
            sessionReplayFlagActive
        }
    #endif

    private func getGroups() -> [String: String] {
        guard let groups = storage.getDictionary(forKey: .groups) as? [String: String] else {
            return [:]
        }
        return groups
    }

    // MARK: Remote Config

    func getRemoteConfig() -> [String: Any]? {
        remoteConfig
    }

    private func getCachedRemoteConfig() -> [String: Any]? {
        if remoteConfig == nil {
            remoteConfig = storage.getDictionary(forKey: .remoteConfig) as? [String: Any]
        }
        return remoteConfig
    }

    private func onRemoteConfig(_ remoteConfig: [String: Any]) {
        let hasFeatureFlags = remoteConfig[hasFeatureFlagsKey] as? Bool

        // cache config
        remoteConfigLock.withLock {
            self.remoteConfig = remoteConfig
            self.hasFeatureFlags = hasFeatureFlags
            storage.setDictionary(forKey: .remoteConfig, contents: remoteConfig)
        }

        // reload feature flags if not previously loaded
        let cachedFeatureFlags = featureFlagsLock.withLock { self.featureFlags }
        if hasFeatureFlags == true, cachedFeatureFlags == nil {
            reloadFeatureFlags()
        }

        DispatchQueue.main.async {
            self.onRemoteConfigLoaded?(remoteConfig)
        }
    }
}
