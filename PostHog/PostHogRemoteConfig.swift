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
    private let getDefaultPersonProperties: () -> [String: Any]

    private let loadingFeatureFlagsLock = NSLock()
    private let featureFlagsLock = NSLock()
    private var loadingFeatureFlags = false
    private var sessionReplayFlagActive = false

    private var flags: [String: Any]?
    private var featureFlags: [String: Any]?

    private var remoteConfigLock = NSLock()
    private let loadingRemoteConfigLock = NSLock()
    private var loadingRemoteConfig = false
    private var remoteConfig: [String: Any]?
    private var remoteConfigDidFetch: Bool = false
    private var featureFlagPayloads: [String: Any]?
    private var requestId: String?

    private let personPropertiesForFlagsLock = NSLock()
    private var personPropertiesForFlags: [String: Any] = [:]

    private let groupPropertiesForFlagsLock = NSLock()
    private var groupPropertiesForFlags: [String: [String: Any]] = [:]

    /// Internal, only used for testing
    var canReloadFlagsForTesting = true

    var onRemoteConfigLoaded: (([String: Any]?) -> Void)?
    var onFeatureFlagsLoaded: (([String: Any]?) -> Void)?

    private let dispatchQueue = DispatchQueue(label: "com.posthog.RemoteConfig",
                                              target: .global(qos: .utility))

    var lastRequestId: String? {
        featureFlagsLock.withLock {
            requestId ?? storage.getString(forKey: .requestId)
        }
    }

    init(_ config: PostHogConfig,
         _ storage: PostHogStorage,
         _ api: PostHogApi,
         _ getDefaultPersonProperties: @escaping () -> [String: Any])
    {
        self.config = config
        self.storage = storage
        self.api = api
        self.getDefaultPersonProperties = getDefaultPersonProperties

        // Load cached person and group properties for flags
        loadCachedPropertiesForFlags()

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

                    // if there's no remote config response, skip
                    guard let remoteConfig else {
                        hedgeLog("Remote config response is missing, skipping loading flags")
                        notifyFeatureFlags(nil)
                        return
                    }

                    // Check if the server explicitly responded with hasFeatureFlags key
                    if let hasFeatureFlagsBoolValue = remoteConfig[self.hasFeatureFlagsKey] as? Bool, !hasFeatureFlagsBoolValue {
                        hedgeLog("hasFeatureFlags is false, clearing flags and skipping loading flags")
                        // Server responded with explicit hasFeatureFlags: false, meaning no active flags on the account
                        clearFeatureFlags()
                        // need to notify cause people may be waiting for flags to load
                        notifyFeatureFlags([:])
                    } else if self.config.preloadFeatureFlags {
                        // If we reach here, hasFeatureFlags is either true, nil or not a boolean value
                        // Note: notifyFeatureFlags() will be eventually called inside preloadFeatureFlags()
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
            hedgeLog("No PostHogStorageManager found in config, skipping loading feature flags")
            callback?(nil)
            return
        }

        let groups = featureFlagsLock.withLock { getGroups() }
        let distinctId = storageManager.getDistinctId()
        let anonymousId = config.reuseAnonymousId == false ? storageManager.getAnonymousId() : nil

        loadFeatureFlags(
            distinctId: distinctId,
            anonymousId: anonymousId,
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
        anonymousId: String?,
        groups: [String: String],
        callback: @escaping ([String: Any]?) -> Void
    ) {
        loadingFeatureFlagsLock.withLock {
            if self.loadingFeatureFlags {
                return
            }
            self.loadingFeatureFlags = true
        }

        let personProperties = getPersonPropertiesForFlags()
        let groupProperties = getGroupPropertiesForFlags()

        api.flags(distinctId: distinctId,
                  anonymousId: anonymousId,
                  groups: groups,
                  personProperties: personProperties,
                  groupProperties: groupProperties.isEmpty ? nil : groupProperties)
        { data, _ in
            self.dispatchQueue.async {
                // Check for quota limitation first
                if let quotaLimited = data?["quotaLimited"] as? [String],
                   quotaLimited.contains("feature_flags")
                {
                    // swiftlint:disable:next line_length
                    hedgeLog("Warning: Feature flags quota limit reached - clearing all feature flags and payloads. See https://posthog.com/docs/billing/limits-alerts for more information.")

                    self.clearFeatureFlags()
                    self.notifyFeatureFlagsAndRelease([:])
                    return callback([:])
                }

                // Safely handle optional data
                guard var data = data else {
                    hedgeLog("Error: Flags response data is nil")
                    self.notifyFeatureFlagsAndRelease(nil)
                    return callback(nil)
                }

                self.normalizeResponse(&data)

                let flagsV4 = data["flags"] as? [String: Any]

                guard let featureFlags = data["featureFlags"] as? [String: Any],
                      let featureFlagPayloads = data["featureFlagPayloads"] as? [String: Any]
                else {
                    hedgeLog("Error: Flags response missing correct featureFlags format")
                    self.notifyFeatureFlagsAndRelease(nil)
                    return callback(nil)
                }

                #if os(iOS)
                    self.processSessionRecordingConfig(data, featureFlags: featureFlags)
                #endif

                // Grab the request ID from the response
                let requestId = data["requestId"] as? String
                let errorsWhileComputingFlags = data["errorsWhileComputingFlags"] as? Bool ?? false
                var loadedFeatureFlags: [String: Any]?

                self.featureFlagsLock.withLock {
                    if let requestId {
                        // Store the request ID in the storage.
                        self.setCachedRequestId(requestId)
                    }

                    if errorsWhileComputingFlags {
                        // v4 cached flags which contains metadata about each flag.
                        let cachedFlags = self.getCachedFlags() ?? [:]

                        // The following two aren't necessarily needed for v4, but we'll keep them for now
                        // for back compatibility for existing v3 users who might already have cached flag data.
                        let cachedFeatureFlags = self.getCachedFeatureFlags() ?? [:]
                        let cachedFeatureFlagsPayloads = self.getCachedFeatureFlagPayload() ?? [:]

                        let newFeatureFlags = cachedFeatureFlags.merging(featureFlags) { _, new in new }
                        let newFeatureFlagsPayloads = cachedFeatureFlagsPayloads.merging(featureFlagPayloads) { _, new in new }

                        // if not all flags were computed, we upsert flags instead of replacing them
                        loadedFeatureFlags = newFeatureFlags
                        if let flagsV4 {
                            let newFlags = cachedFlags.merging(flagsV4) { _, new in new }
                            // if not all flags were computed, we upsert flags instead of replacing them
                            self.setCachedFlags(newFlags)
                        }
                        self.setCachedFeatureFlags(newFeatureFlags)
                        self.setCachedFeatureFlagPayload(newFeatureFlagsPayloads)
                        self.notifyFeatureFlagsAndRelease(newFeatureFlags)
                    } else {
                        loadedFeatureFlags = featureFlags
                        if let flagsV4 {
                            self.setCachedFlags(flagsV4)
                        }
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

    private func notifyFeatureFlags(_ featureFlags: [String: Any]?) {
        DispatchQueue.main.async {
            self.onFeatureFlagsLoaded?(featureFlags)
            NotificationCenter.default.post(name: PostHogSDK.didReceiveFeatureFlags, object: nil)
        }
    }

    private func notifyFeatureFlagsAndRelease(_ featureFlags: [String: Any]?) {
        notifyFeatureFlags(featureFlags)

        loadingFeatureFlagsLock.withLock {
            self.loadingFeatureFlags = false
        }
    }

    func getFeatureFlags() -> [String: Any]? {
        featureFlagsLock.withLock { getCachedFeatureFlags() }
    }

    func getFeatureFlag(_ key: String) -> Any? {
        var flags: [String: Any]?
        featureFlagsLock.withLock {
            flags = self.getCachedFeatureFlags()
        }

        return flags?[key]
    }

    func getFeatureFlagDetails(_ key: String) -> Any? {
        var flags: [String: Any]?
        featureFlagsLock.withLock {
            flags = self.getCachedFlags()
        }

        return flags?[key]
    }

    // To be called after acquiring `featureFlagsLock`
    private func getCachedFeatureFlagPayload() -> [String: Any]? {
        if featureFlagPayloads == nil {
            featureFlagPayloads = storage.getDictionary(forKey: .enabledFeatureFlagPayloads) as? [String: Any]
        }
        return featureFlagPayloads
    }

    // To be called after acquiring `featureFlagsLock`
    private func setCachedFeatureFlagPayload(_ featureFlagPayloads: [String: Any]) {
        self.featureFlagPayloads = featureFlagPayloads
        storage.setDictionary(forKey: .enabledFeatureFlagPayloads, contents: featureFlagPayloads)
    }

    // To be called after acquiring `featureFlagsLock`
    private func getCachedFeatureFlags() -> [String: Any]? {
        if featureFlags == nil {
            featureFlags = storage.getDictionary(forKey: .enabledFeatureFlags) as? [String: Any]
        }
        return featureFlags
    }

    // To be called after acquiring `featureFlagsLock`
    private func setCachedFeatureFlags(_ featureFlags: [String: Any]) {
        self.featureFlags = featureFlags
        storage.setDictionary(forKey: .enabledFeatureFlags, contents: featureFlags)
    }

    // To be called after acquiring `featureFlagsLock`
    private func setCachedFlags(_ flags: [String: Any]) {
        self.flags = flags
        storage.setDictionary(forKey: .flags, contents: flags)
    }

    // To be called after acquiring `featureFlagsLock`
    private func getCachedFlags() -> [String: Any]? {
        if flags == nil {
            flags = storage.getDictionary(forKey: .flags) as? [String: Any]
        }
        return flags
    }

    func setPersonPropertiesForFlags(_ properties: [String: Any]) {
        personPropertiesForFlagsLock.withLock {
            // Merge properties additively, similar to JS SDK behavior
            personPropertiesForFlags.merge(properties, uniquingKeysWith: { _, new in new })
            // Persist to disk
            storage.setDictionary(forKey: .personPropertiesForFlags, contents: personPropertiesForFlags)
        }
    }

    func resetPersonPropertiesForFlags() {
        personPropertiesForFlagsLock.withLock {
            personPropertiesForFlags.removeAll()
            // Clear from disk
            storage.setDictionary(forKey: .personPropertiesForFlags, contents: personPropertiesForFlags)
        }
    }

    func setGroupPropertiesForFlags(_ groupType: String, properties: [String: Any]) {
        groupPropertiesForFlagsLock.withLock {
            // Merge properties additively for this group type
            groupPropertiesForFlags[groupType, default: [:]].merge(properties) { _, new in new }
            // Persist to disk
            storage.setDictionary(forKey: .groupPropertiesForFlags, contents: groupPropertiesForFlags)
        }
    }

    func resetGroupPropertiesForFlags(_ groupType: String? = nil) {
        groupPropertiesForFlagsLock.withLock {
            if let groupType = groupType {
                groupPropertiesForFlags.removeValue(forKey: groupType)
            } else {
                groupPropertiesForFlags.removeAll()
            }
            // Persist changes to disk
            storage.setDictionary(forKey: .groupPropertiesForFlags, contents: groupPropertiesForFlags)
        }
    }

    private func getGroupPropertiesForFlags() -> [String: [String: Any]] {
        groupPropertiesForFlagsLock.withLock {
            groupPropertiesForFlags
        }
    }

    private func getPersonPropertiesForFlags() -> [String: Any] {
        personPropertiesForFlagsLock.withLock {
            var properties = personPropertiesForFlags

            // Always include fresh default properties if enabled
            if config.setDefaultPersonProperties {
                let defaultProperties = getDefaultPersonProperties()
                // User-set properties override default properties
                properties = defaultProperties.merging(properties) { _, userValue in userValue }
            }

            return properties
        }
    }

    private func loadCachedPropertiesForFlags() {
        personPropertiesForFlagsLock.withLock {
            if let cachedPersonProperties = storage.getDictionary(forKey: .personPropertiesForFlags) as? [String: Any] {
                personPropertiesForFlags = cachedPersonProperties
            }
        }

        groupPropertiesForFlagsLock.withLock {
            if let cachedGroupProperties = storage.getDictionary(forKey: .groupPropertiesForFlags) as? [String: [String: Any]] {
                groupPropertiesForFlags = cachedGroupProperties
            }
        }
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

    // To be called after acquiring `featureFlagsLock`
    private func setCachedRequestId(_ value: String?) {
        requestId = value
        if let value {
            storage.setString(forKey: .requestId, contents: value)
        } else {
            storage.remove(key: .requestId)
        }
    }

    private func normalizeResponse(_ data: inout [String: Any]) {
        if let flagsV4 = data["flags"] as? [String: Any] {
            var featureFlags = [String: Any]()
            var featureFlagsPayloads = [String: Any]()
            for (key, value) in flagsV4 {
                if let flag = value as? [String: Any] {
                    if let variant = flag["variant"] as? String {
                        featureFlags[key] = variant
                        // If there's a variant, the flag is enabled, so we can store the payload
                        if let metadata = flag["metadata"] as? [String: Any],
                           let payload = metadata["payload"]
                        {
                            featureFlagsPayloads[key] = payload
                        }
                    } else {
                        let enabled = flag["enabled"] as? Bool
                        featureFlags[key] = enabled

                        // Only store payload if the flag is enabled
                        if enabled == true,
                           let metadata = flag["metadata"] as? [String: Any],
                           let payload = metadata["payload"]
                        {
                            featureFlagsPayloads[key] = payload
                        }
                    }
                }
            }
            data["featureFlags"] = featureFlags
            data["featureFlagPayloads"] = featureFlagsPayloads
        }
    }

    private func clearFeatureFlags() {
        featureFlagsLock.withLock {
            setCachedFlags([:])
            setCachedFeatureFlags([:])
            setCachedFeatureFlagPayload([:])
            setCachedRequestId(nil) // requestId no longer valid
        }
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
