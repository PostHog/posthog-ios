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
    private let featureFlagCalledCallback: ((_ flagKey: String, _ flagValue: Any?) -> Void)?

    private let loadingFeatureFlagsLock = NSLock()
    private let featureFlagsLock = NSLock()
    private var loadingFeatureFlags = false
    private var pendingFeatureFlagsRequest: PendingFeatureFlagsRequest?
    private let sessionReplayLock = NSLock()
    private var sessionReplayFlagActive = false
    private var recordingSampleRate: Double?
    private var recordingMinimumDuration: TimeInterval?

    private let errorTrackingLock = NSLock()
    private var autoCaptureExceptions = false

    private var flags: [String: Any]?
    private var featureFlags: [String: Any]?

    private var remoteConfigLock = NSLock()
    private let loadingRemoteConfigLock = NSLock()
    private var loadingRemoteConfig = false
    private var remoteConfig: [String: Any]?
    private var remoteConfigDidFetch: Bool = false
    private var featureFlagPayloads: [String: Any]?
    private var requestId: String?
    private var evaluatedAt: Int?

    private let personPropertiesForFlagsLock = NSLock()
    private var personPropertiesForFlags: [String: Any] = [:]

    private let groupPropertiesForFlagsLock = NSLock()
    private var groupPropertiesForFlags: [String: [String: Any]] = [:]

    /// Internal, only used for testing
    var canReloadFlagsForTesting = true

    let onRemoteConfigLoaded = PostHogMulticastCallback<[String: Any]?>()
    let onFeatureFlagsLoaded = PostHogMulticastCallback<[String: Any]?>()

    private let dispatchQueue = DispatchQueue(label: "com.posthog.RemoteConfig",
                                              target: .global(qos: .utility))

    var lastRequestId: String? {
        featureFlagsLock.withLock {
            getCachedValue(\.requestId, key: .requestId) { storage.getString(forKey: $0) }
        }
    }

    var lastEvaluatedAt: Int? {
        featureFlagsLock.withLock {
            getCachedValue(\.evaluatedAt, key: .evaluatedAt) { storage.getInt(forKey: $0) }
        }
    }

    init(_ config: PostHogConfig,
         _ storage: PostHogStorage,
         _ api: PostHogApi,
         _ getDefaultPersonProperties: @escaping () -> [String: Any],
         _ featureFlagCalledCallback: ((_ flagKey: String, _ flagValue: Any?) -> Void)? = nil)
    {
        self.config = config
        self.storage = storage
        self.api = api
        self.getDefaultPersonProperties = getDefaultPersonProperties
        self.featureFlagCalledCallback = featureFlagCalledCallback

        // Load cached person and group properties for flags
        loadCachedPropertiesForFlags()

        preloadSessionReplay()
        preloadErrorTrackingConfig()

        // Remote config is always loaded (config.remoteConfig is now a no-op)
        preloadRemoteConfig()
    }

    private func preloadRemoteConfig() {
        remoteConfigLock.withLock {
            // load disk cached config to memory
            _ = getCachedRemoteConfig()
        }

        guard !config.disableRemoteConfigForTesting else {
            return
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
        // Remote config is always loaded (config.remoteConfig is now a no-op)
        // Note: this guard has the same withLock closure-return bug as loadFeatureFlags
        // had, but for remote config duplicate concurrent requests are harmless (no
        // identity-sensitive params). Fixing it properly requires a pending callback
        // queue to avoid dropping callers. See loadFeatureFlags() for the correct pattern.
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

                // process error tracking config
                self.processErrorTrackingConfig(config)

                // notify
                DispatchQueue.main.async {
                    self.onRemoteConfigLoaded.invoke(config)
                }
            }

            // Guard `remoteConfigDidFetch` with the same lock that reads it (and that clear() resets it
            // under) so the session-replay buffering decision has a sound happens-before with this write.
            self.remoteConfigLock.withLock {
                self.remoteConfigDidFetch = true
            }
            self.loadingRemoteConfigLock.withLock {
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
        let deviceId = storageManager.getDeviceId()

        loadFeatureFlags(
            distinctId: distinctId,
            anonymousId: anonymousId,
            deviceId: deviceId.isEmpty ? nil : deviceId,
            groups: groups,
            callback: callback ?? { _ in }
        )
    }

    private func preloadSessionReplay() {
        let sessionReplay = remoteConfigLock.withLock {
            getCachedRemoteConfig()?["sessionRecording"] as? [String: Any]
        }
        let featureFlags = featureFlagsLock.withLock {
            self.getCachedFeatureFlags()
        }

        if let sessionReplay = sessionReplay {
            if let endpoint = sessionReplay["endpoint"] as? String {
                config.snapshotEndpoint = endpoint
            }

            sessionReplayLock.withLock {
                sessionReplayFlagActive = isRecordingActive(featureFlags ?? [:], sessionReplay)
                #if os(iOS)
                    recordingSampleRate = parseSampleRate(sessionReplay["sampleRate"])
                    recordingMinimumDuration = parseMinimumDuration(sessionReplay["minimumDurationMilliseconds"])
                #endif
            }
        }
    }

    private func isRecordingActive(_ featureFlags: [String: Any], _ sessionRecording: [String: Any]) -> Bool {
        var recordingActive = true
        var flagKey: String?
        var flagValue: Any?

        // check for boolean flags
        if let linkedFlag = sessionRecording["linkedFlag"] as? String {
            let value = featureFlags[linkedFlag]
            flagKey = linkedFlag
            flagValue = value

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
                flagKey = flag
                flagValue = value
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

        // Report the feature flag as called so usage is tracked
        if let flagKey, let flagValue, config.sendFeatureFlagEvent {
            featureFlagCalledCallback?(flagKey, flagValue)
        }

        return recordingActive
    }

    func loadFeatureFlags(
        distinctId: String,
        anonymousId: String?,
        deviceId: String? = nil,
        groups: [String: String],
        callback: @escaping ([String: Any]?) -> Void
    ) {
        let (alreadyLoading, previousCallback): (Bool, (([String: Any]?) -> Void)?) = loadingFeatureFlagsLock.withLock {
            if self.loadingFeatureFlags {
                let prev = self.pendingFeatureFlagsRequest?.callback
                self.pendingFeatureFlagsRequest = PendingFeatureFlagsRequest(
                    distinctId: distinctId,
                    anonymousId: anonymousId,
                    deviceId: deviceId,
                    groups: groups,
                    callback: callback
                )
                return (true, prev)
            }
            self.loadingFeatureFlags = true
            return (false, nil)
        }
        if alreadyLoading {
            let cached = featureFlagsLock.withLock { getCachedFeatureFlags() }
            previousCallback?(cached)
            return
        }

        let personProperties = getPersonPropertiesForFlags()
        let groupProperties = getGroupPropertiesForFlags()

        api.flags(distinctId: distinctId,
                  anonymousId: anonymousId,
                  deviceId: deviceId,
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
                    hedgeLog("Warning: Feature flags quota limit reached - flags could not be updated. See https://posthog.com/docs/billing/limits-alerts for more information.")

                    let cachedFeatureFlags = self.featureFlagsLock.withLock {
                        self.getCachedFeatureFlags() ?? [:]
                    }

                    // quota-limited /flags carries no config; re-arm from the cached remote config
                    #if os(iOS)
                        self.processSessionRecordingConfig(nil, featureFlags: cachedFeatureFlags)
                    #endif
                    self.processErrorTrackingConfig(nil)

                    self.notifyFeatureFlagsAndRelease(cachedFeatureFlags)
                    return callback(cachedFeatureFlags)
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

                // /flags carries no config; re-arm from the cached remote config
                #if os(iOS)
                    self.processSessionRecordingConfig(nil, featureFlags: featureFlags)
                #endif
                self.processErrorTrackingConfig(nil)

                // Grab the request ID and evaluated timestamp from the response
                let requestId = data["requestId"] as? String
                let evaluatedAt = data["evaluatedAt"] as? Int
                let errorsWhileComputingFlags = data["errorsWhileComputingFlags"] as? Bool ?? false
                var loadedFeatureFlags: [String: Any]?

                self.featureFlagsLock.withLock {
                    if let requestId {
                        self.setCachedRequestId(requestId)
                    }

                    if let evaluatedAt {
                        self.setCachedEvaluatedAt(evaluatedAt)
                    }

                    if errorsWhileComputingFlags {
                        let cachedFlags = self.getCachedFlags() ?? [:]
                        let cachedFeatureFlags = self.getCachedFeatureFlags() ?? [:]
                        let cachedFeatureFlagsPayloads = self.getCachedFeatureFlagPayload() ?? [:]

                        let newFeatureFlags = cachedFeatureFlags.merging(featureFlags) { _, new in new }
                        let newFeatureFlagsPayloads = cachedFeatureFlagsPayloads.merging(featureFlagPayloads) { _, new in new }

                        loadedFeatureFlags = newFeatureFlags
                        if let flagsV4 {
                            let newFlags = cachedFlags.merging(flagsV4) { _, new in new }
                            self.setCachedFlags(newFlags)
                        }
                        self.setCachedFeatureFlags(newFeatureFlags)
                        self.setCachedFeatureFlagPayload(newFeatureFlagsPayloads)
                    } else {
                        loadedFeatureFlags = featureFlags
                        if let flagsV4 {
                            self.setCachedFlags(flagsV4)
                        }
                        self.setCachedFeatureFlags(featureFlags)
                        self.setCachedFeatureFlagPayload(featureFlagPayloads)
                    }
                }

                self.notifyFeatureFlagsAndRelease(loadedFeatureFlags)
                return callback(loadedFeatureFlags)
            }
        }
    }

    #if os(iOS)
        private func processSessionRecordingConfig(_ data: [String: Any]?, featureFlags: [String: Any]) {
            // fall back to the cached remote config (survives reset()) so replay re-arms; only Bool false disables
            let sessionRecording: Any? = data?["sessionRecording"]
                ?? remoteConfigLock.withLock { getCachedRemoteConfig()?["sessionRecording"] }

            if let sessionRecording = sessionRecording as? Bool {
                sessionReplayLock.withLock {
                    sessionReplayFlagActive = sessionRecording
                }
            } else if let sessionRecording = sessionRecording as? [String: Any] {
                // enabled in project settings, but only active locally when the replay integration is
                if let endpoint = sessionRecording["endpoint"] as? String {
                    config.snapshotEndpoint = endpoint
                }
                sessionReplayLock.withLock {
                    applySessionRecordingConfigLocked(sessionRecording, featureFlags: featureFlags)
                }
            }
        }

        /// Applies a `sessionRecording` config dict to the in-memory replay state (active flag,
        /// sample rate, minimum duration). The caller must already hold `sessionReplayLock`.
        private func applySessionRecordingConfigLocked(_ recordingConfig: [String: Any], featureFlags: [String: Any]) {
            sessionReplayFlagActive = isRecordingActive(featureFlags, recordingConfig)
            recordingSampleRate = parseSampleRate(recordingConfig["sampleRate"])
            recordingMinimumDuration = parseMinimumDuration(recordingConfig["minimumDurationMilliseconds"])
        }

        /// Parses and validates a sample rate value which may come as a String (from the API JSON)
        /// or as a Number (from cached storage). Returns `nil` if the value is absent, unparseable,
        /// or outside the 0.0–1.0 range.
        private func parseSampleRate(_ raw: Any?) -> Double? {
            let value: Double?
            if let number = raw as? Double {
                value = number
            } else if let number = raw as? NSNumber {
                value = number.doubleValue
            } else if let string = raw as? String {
                value = Double(string)
            } else {
                return nil
            }

            guard let value, value >= 0.0, value <= 1.0 else {
                if let value {
                    hedgeLog("Remote config sampleRate must be between 0.0 and 1.0, got \(value). Ignoring.")
                }
                return nil
            }
            return value
        }

        func getRecordingSampleRate() -> Double? {
            sessionReplayLock.withLock { recordingSampleRate }
        }

        /// Parses and validates a minimum duration value which may come as a Number (from the API JSON)
        /// or from cached storage. Returns `nil` if the value is absent, unparseable, or negative.
        /// The value is expected to be in milliseconds.
        private func parseMinimumDuration(_ raw: Any?) -> TimeInterval? {
            let milliseconds: Double?
            if let number = raw as? Double {
                milliseconds = number
            } else if let number = raw as? NSNumber {
                milliseconds = number.doubleValue
            } else if let number = raw as? Int {
                milliseconds = Double(number)
            } else {
                return nil
            }

            guard let milliseconds, milliseconds >= 0 else {
                if let milliseconds {
                    hedgeLog("Remote config minimumDurationMilliseconds must be non-negative, got \(milliseconds). Ignoring.")
                }
                return nil
            }
            return milliseconds / 1_000.0
        }

        func getRecordingMinimumDuration() -> TimeInterval? {
            sessionReplayLock.withLock { recordingMinimumDuration }
        }
    #endif

    private func processErrorTrackingConfig(_ data: [String: Any]?) {
        // fall back to the cached remote config (survives reset()) so autocapture re-arms; only Bool false disables
        let errorTracking: Any? = data?["errorTracking"]
            ?? remoteConfigLock.withLock { getCachedRemoteConfig()?["errorTracking"] }

        if let errorTracking = errorTracking as? Bool {
            errorTrackingLock.withLock {
                autoCaptureExceptions = errorTracking
            }
        } else if let errorTracking = errorTracking as? [String: Any] {
            let enabled = errorTracking["autocaptureExceptions"] as? Bool ?? false
            errorTrackingLock.withLock {
                autoCaptureExceptions = enabled
            }
        }
    }

    private func preloadErrorTrackingConfig() {
        let errorTracking = remoteConfigLock.withLock {
            getCachedRemoteConfig()?["errorTracking"] as? [String: Any]
        }
        if let errorTracking {
            let enabled = errorTracking["autocaptureExceptions"] as? Bool ?? false
            errorTrackingLock.withLock {
                autoCaptureExceptions = enabled
            }
        }
    }

    /// Returns whether autocapture of exceptions is enabled based on the remote config.
    /// The remote config must have `autocaptureExceptions` set to `true` or a dictionary.
    func isAutocaptureExceptionsEnabled() -> Bool {
        errorTrackingLock.withLock { autoCaptureExceptions }
    }

    private func notifyFeatureFlags(_ featureFlags: [String: Any]?) {
        DispatchQueue.main.async {
            self.onFeatureFlagsLoaded.invoke(featureFlags)
            NotificationCenter.default.post(name: PostHogSDK.didReceiveFeatureFlags, object: nil)
        }
    }

    private func notifyFeatureFlagsAndRelease(_ featureFlags: [String: Any]?) {
        notifyFeatureFlags(featureFlags)

        let pending: PendingFeatureFlagsRequest? = loadingFeatureFlagsLock.withLock {
            self.loadingFeatureFlags = false
            let req = self.pendingFeatureFlagsRequest
            self.pendingFeatureFlagsRequest = nil
            return req
        }

        if let pending {
            loadFeatureFlags(
                distinctId: pending.distinctId,
                anonymousId: pending.anonymousId,
                deviceId: pending.deviceId,
                groups: pending.groups,
                callback: pending.callback
            )
        }
    }

    func getFeatureFlags() -> [String: Any]? {
        featureFlagsLock.withLock { getCachedFeatureFlags() }
    }

    func getFeatureFlag(_ key: String) -> Any? {
        getFeatureFlagValue(key) { self.getCachedFeatureFlags() }
    }

    func getFeatureFlagDetails(_ key: String) -> Any? {
        getFeatureFlagValue(key) { self.getCachedFlags() }
    }

    private func getFeatureFlagValue(_ key: String, from getCachedValues: () -> [String: Any]?) -> Any? {
        var flags: [String: Any]?
        featureFlagsLock.withLock {
            flags = getCachedValues()
        }

        return flags?[key]
    }

    // To be called after acquiring `featureFlagsLock`
    private func getCachedFeatureFlagPayload() -> [String: Any]? {
        getCachedDictionary(\.featureFlagPayloads, forKey: .enabledFeatureFlagPayloads)
    }

    // To be called after acquiring `featureFlagsLock`
    private func setCachedFeatureFlagPayload(_ featureFlagPayloads: [String: Any]) {
        setCachedDictionary(featureFlagPayloads, cache: \.featureFlagPayloads, forKey: .enabledFeatureFlagPayloads)
    }

    // To be called after acquiring `featureFlagsLock`
    private func getCachedFeatureFlags() -> [String: Any]? {
        getCachedDictionary(\.featureFlags, forKey: .enabledFeatureFlags)
    }

    // To be called after acquiring `featureFlagsLock`
    private func setCachedFeatureFlags(_ featureFlags: [String: Any]) {
        setCachedDictionary(featureFlags, cache: \.featureFlags, forKey: .enabledFeatureFlags)
    }

    // To be called after acquiring `featureFlagsLock`
    private func setCachedFlags(_ flags: [String: Any]) {
        setCachedDictionary(flags, cache: \.flags, forKey: .flags)
    }

    // To be called after acquiring `featureFlagsLock`
    private func getCachedFlags() -> [String: Any]? {
        getCachedDictionary(\.flags, forKey: .flags)
    }

    private func getCachedDictionary(
        _ cache: ReferenceWritableKeyPath<PostHogRemoteConfig, [String: Any]?>,
        forKey key: PostHogStorage.StorageKey
    ) -> [String: Any]? {
        if self[keyPath: cache] == nil {
            self[keyPath: cache] = storage.getDictionary(forKey: key) as? [String: Any]
        }
        return self[keyPath: cache]
    }

    private func setCachedDictionary(
        _ value: [String: Any],
        cache: ReferenceWritableKeyPath<PostHogRemoteConfig, [String: Any]?>,
        forKey key: PostHogStorage.StorageKey
    ) {
        self[keyPath: cache] = value
        storage.setDictionary(forKey: key, contents: value)
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

    func getPersonPropertiesForFlags() -> [String: Any] {
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

    func getFeatureFlagResult(_ key: String) -> PostHogFeatureFlagResult? {
        var flagValue: Any?
        var payloadValue: Any?

        featureFlagsLock.withLock {
            flagValue = getCachedFeatureFlags()?[key]
            payloadValue = getCachedFeatureFlagPayload()?[key]
        }

        guard flagValue != nil else { return nil }

        return makeFeatureFlagResult(key: key, flagValue: flagValue, payloadValue: payloadValue)
    }

    func getAllFeatureFlagResults() -> [PostHogFeatureFlagResult]? {
        var flags: [String: Any]?
        var payloads: [String: Any]?

        featureFlagsLock.withLock {
            flags = getCachedFeatureFlags()
            payloads = getCachedFeatureFlagPayload()
        }

        guard let flags else { return nil }

        return flags.map { key, value in
            makeFeatureFlagResult(key: key, flagValue: value, payloadValue: payloads?[key])
        }
    }

    private func makeFeatureFlagResult(key: String, flagValue: Any?, payloadValue: Any?) -> PostHogFeatureFlagResult {
        let payload: Any?
        if let stringValue = payloadValue as? String {
            do {
                payload = try JSONSerialization.jsonObject(with: stringValue.data(using: .utf8)!, options: .fragmentsAllowed)
            } catch {
                hedgeLog("Error parsing the object \(String(describing: payloadValue)): \(error)")
                payload = payloadValue
            }
        } else {
            payload = payloadValue
        }

        let isEnabled: Bool
        let variant: String?

        if let stringValue = flagValue as? String {
            isEnabled = true
            variant = stringValue
        } else if let boolValue = flagValue as? Bool {
            isEnabled = boolValue
            variant = nil
        } else {
            isEnabled = false
            variant = nil
        }

        return PostHogFeatureFlagResult(
            key: key,
            enabled: isEnabled,
            variant: variant,
            payload: payload
        )
    }

    // To be called after acquiring `featureFlagsLock`
    private func setCachedRequestId(_ value: String?) {
        setCachedValue(value, cache: \.requestId, key: .requestId) { key, value in
            storage.setString(forKey: key, contents: value)
        }
    }

    // To be called after acquiring `featureFlagsLock`
    private func setCachedEvaluatedAt(_ value: Int?) {
        setCachedValue(value, cache: \.evaluatedAt, key: .evaluatedAt) { key, value in
            storage.setInt(forKey: key, contents: value)
        }
    }

    private func getCachedValue<T>(
        _ cache: KeyPath<PostHogRemoteConfig, T?>,
        key: PostHogStorage.StorageKey,
        load: (PostHogStorage.StorageKey) -> T?
    ) -> T? {
        self[keyPath: cache] ?? load(key)
    }

    private func setCachedValue<T>(
        _ value: T?,
        cache: ReferenceWritableKeyPath<PostHogRemoteConfig, T?>,
        key: PostHogStorage.StorageKey,
        persist: (PostHogStorage.StorageKey, T) -> Void
    ) {
        self[keyPath: cache] = value
        if let value {
            persist(key, value)
        } else {
            storage.remove(key: key)
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
            setCachedEvaluatedAt(nil) // evaluatedAt no longer valid
        }
    }

    /// Clears all cached feature flags, remote config state, and user-specific properties.
    /// This should be called during reset() to ensure stale data from a previous user
    /// doesn't persist in memory after the user switches.
    func clear() {
        clearFeatureFlags()

        sessionReplayLock.withLock {
            sessionReplayFlagActive = false
            recordingSampleRate = nil
        }

        errorTrackingLock.withLock {
            autoCaptureExceptions = false
        }

        // Clear person and group properties for flags
        resetPersonPropertiesForFlags()
        resetGroupPropertiesForFlags()

        // keep the cached remote config across reset() (project-level, not user data) so features re-arm;
        // just mark it un-fetched so a fresh copy is pulled
        remoteConfigLock.withLock {
            remoteConfigDidFetch = false
        }
    }

    #if os(iOS)
        func isSessionReplayFlagActive() -> Bool {
            sessionReplayLock.withLock { sessionReplayFlagActive }
        }

        /// Whether the live remote config (`/config`) has been fetched at least once.
        /// Session replay uses this to know whether the first remote-config decision is still
        /// pending so it can buffer snapshots until the cached flag is confirmed or overridden.
        var hasFetchedRemoteConfig: Bool {
            remoteConfigLock.withLock { remoteConfigDidFetch }
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
        getCachedDictionary(\.remoteConfig, forKey: .remoteConfig)
    }
}

private struct PendingFeatureFlagsRequest {
    let distinctId: String
    let anonymousId: String?
    let deviceId: String?
    let groups: [String: String]
    let callback: ([String: Any]?) -> Void
}
