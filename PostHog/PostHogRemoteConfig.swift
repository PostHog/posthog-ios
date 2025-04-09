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

        preloadSessionReplayFlag()

        if config.remoteConfig {
            preloadRemoteConfig()
        } else if config.preloadFeatureFlags {
            preloadFeatureFlags()
        }
    }

    private func preloadRemoteConfig() {
        remoteConfigLock.withLock {
            // load disk cached config to memory
            _ = getCachedRemoteConfig()
        }

        // may have already beed fetched from `loadFeatureFlags` call
        if remoteConfigLock.withLock({
            self.remoteConfig == nil || !self.remoteConfigDidFetch
        }) {
            dispatchQueue.async {
                self.reloadRemoteConfig { [weak self] remoteConfig in
                    guard let self else { return }
                    let hasFeatureFlags = remoteConfig?[self.hasFeatureFlagsKey] as? Bool == true
                    let cachedFeatureFlags = self.featureFlagsLock.withLock { self.featureFlags }
                    let preloadFeatureFlags = self.config.preloadFeatureFlags
                    // reload feature flags if not previously loaded
                    if hasFeatureFlags, cachedFeatureFlags == nil, preloadFeatureFlags {
                        self.preloadFeatureFlags()
                    }
                }
            }
        }
    }

    private func preloadFeatureFlags() {
        featureFlagsLock.withLock {
            // load disk cached config to memory
            _ = getCachedFeatureFlags()
        }

        if config.preloadFeatureFlags {
            dispatchQueue.async {
                self.reloadFeatureFlags()
            }
        }
    }

    func reloadRemoteConfig(
        callback: (([String: Any]?) -> Void)? = nil
    ) {
        guard config.remoteConfig else {
            callback?(nil)
            return
        }

        loadingRemoteConfigLock.withLock {
            if self.loadingRemoteConfig {
                return
            }
            self.loadingRemoteConfig = true
        }

        api.remoteConfig { config, _ in
            if let config {
                // cache config
                self.remoteConfigLock.withLock {
                    self.remoteConfig = config
                    self.storage.setDictionary(forKey: .remoteConfig, contents: config)
                }

                // process session replay config
                #if os(iOS)
                    let featureFlags = self.featureFlagsLock.withLock { self.featureFlags }
                    self.processSessionRecordingConfig(config, featureFlags: featureFlags ?? [:])
                #endif

                // notify
                DispatchQueue.main.async {
                    self.onRemoteConfigLoaded?(config)
                }
            }

            self.loadingRemoteConfigLock.withLock {
                self.remoteConfigDidFetch = true
                self.loadingRemoteConfig = false
            }

            callback?(config)
        }
    }

    func reloadFeatureFlags(
        callback: (([String: Any]?) -> Void)? = nil
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
            callback: callback ?? { _ in }
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
        if let linkedFlag = sessionRecording["linkedFlag"] as? String {
            let value = featureFlags[linkedFlag]

            if let boolValue = value as? Bool {
                // boolean flag with value
                recordingActive = boolValue
            } else if value is String {
                // its a multi-variant flag linked to "any"
                recordingActive = true
            } else {
                // disable recording if the flag does not exist/quota limited
                recordingActive = false
            }
            // check for specific flag variant
        } else if let linkedFlag = sessionRecording["linkedFlag"] as? [String: Any] {
            let flag = linkedFlag["flag"] as? String
            let variant = linkedFlag["variant"] as? String

            if let flag, let variant {
                let value = featureFlags[flag] as? String
                recordingActive = value == variant
            } else {
                // disable recording if the flag does not exist/quota limited
                recordingActive = false
            }
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
        callback: @escaping ([String: Any]?) -> Void
    ) {
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
                // Check for quota limitation first
                if let quotaLimited = data?["quotaLimited"] as? [String],
                   quotaLimited.contains("feature_flags")
                {
                    // swiftlint:disable:next line_length
                    hedgeLog("Warning: Feature flags quota limit reached - clearing all feature flags and payloads. See https://posthog.com/docs/billing/limits-alerts for more information.")
                    self.featureFlagsLock.withLock {
                        // Clear both feature flags and payloads
                        self.setCachedFeatureFlags([:])
                        self.setCachedFeatureFlagPayload([:])
                    }

                    self.notifyFeatureFlagsAndRelease([:])
                    return callback([:])
                }

                guard let featureFlags = data?["featureFlags"] as? [String: Any],
                      let featureFlagPayloads = data?["featureFlagPayloads"] as? [String: Any]
                else {
                    hedgeLog("Error: Decide response missing correct featureFlags format")

                    self.notifyFeatureFlagsAndRelease(data)

                    return callback(nil)
                }
                let errorsWhileComputingFlags = data?["errorsWhileComputingFlags"] as? Bool ?? false

                #if os(iOS)
                    self.processSessionRecordingConfig(data, featureFlags: featureFlags)
                #endif

                var loadedFeatureFlags: [String: Any]?

                self.featureFlagsLock.withLock {
                    if errorsWhileComputingFlags {
                        let cachedFeatureFlags = self.getCachedFeatureFlags() ?? [:]
                        let cachedFeatureFlagsPayloads = self.getCachedFeatureFlagPayload() ?? [:]

                        let newFeatureFlags = cachedFeatureFlags.merging(featureFlags) { _, new in new }
                        let newFeatureFlagsPayloads = cachedFeatureFlagsPayloads.merging(featureFlagPayloads) { _, new in new }

                        // if not all flags were computed, we upsert flags instead of replacing them
                        loadedFeatureFlags = newFeatureFlags
                        self.setCachedFeatureFlags(newFeatureFlags)
                        self.setCachedFeatureFlagPayload(newFeatureFlagsPayloads)
                        self.notifyFeatureFlagsAndRelease(newFeatureFlags)
                    } else {
                        loadedFeatureFlags = featureFlags
                        self.setCachedFeatureFlags(featureFlags)
                        self.setCachedFeatureFlagPayload(featureFlagPayloads)
                        self.notifyFeatureFlagsAndRelease(featureFlags)
                    }
                }

                return callback(loadedFeatureFlags)
            }
        }
    }

    #if os(iOS)
        private func processSessionRecordingConfig(_ data: [String: Any]?, featureFlags: [String: Any]) {
            if let sessionRecording = data?["sessionRecording"] as? Bool {
                sessionReplayFlagActive = sessionRecording

                // its always false here anyway
                if !sessionRecording {
                    storage.remove(key: .sessionReplay)
                }

            } else if let sessionRecording = data?["sessionRecording"] as? [String: Any] {
                // keeps the value from config.sessionReplay since having sessionRecording
                // means its enabled on the project settings, but its only enabled
                // when local replay integration is enabled/active
                if let endpoint = sessionRecording["endpoint"] as? String {
                    config.snapshotEndpoint = endpoint
                }
                sessionReplayFlagActive = isRecordingActive(featureFlags, sessionRecording)
                storage.setDictionary(forKey: .sessionReplay, contents: sessionRecording)
            }
        }
    #endif

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
        featureFlagsLock.withLock { getCachedFeatureFlags() }
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
        remoteConfigLock.withLock { getCachedRemoteConfig() }
    }

    private func getCachedRemoteConfig() -> [String: Any]? {
        if remoteConfig == nil {
            remoteConfig = storage.getDictionary(forKey: .remoteConfig) as? [String: Any]
        }
        return remoteConfig
    }
}
