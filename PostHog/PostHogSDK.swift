// swiftlint:disable file_length cyclomatic_complexity

//
//  PostHogSDK.swift
//  PostHogSDK
//
//  Created by Ben White on 07.02.23.
//

import Foundation

#if os(iOS) || os(tvOS)
    import UIKit
#elseif os(macOS)
    import AppKit
#elseif os(watchOS)
    import WatchKit
#endif

let retryDelay = 5.0
let maxRetryDelay = 30.0

// renamed to PostHogSDK due to https://github.com/apple/swift/issues/56573
@objc public class PostHogSDK: NSObject {
    private(set) var config: PostHogConfig

    private init(_ config: PostHogConfig) {
        self.config = config
    }

    private var enabled = false
    private let setupLock = NSLock()
    private let optOutLock = NSLock()
    private let groupsLock = NSLock()
    private let flagCallReportedLock = NSLock()
    private let personPropsLock = NSLock()

    private var queue: PostHogQueue?
    private var replayQueue: PostHogQueue?
    private(set) var storage: PostHogStorage?
    #if !os(watchOS)
        private var reachability: Reachability?
    #endif
    private var flagCallReported = Set<String>()
    private(set) var remoteConfig: PostHogRemoteConfig?
    private var context: PostHogContext?
    private static var apiKeys = Set<String>()
    private var installedIntegrations: [PostHogIntegration] = []

    #if os(iOS)
        private weak var replayIntegration: PostHogReplayIntegration?
        private weak var surveysIntegration: PostHogSurveyIntegration?
    #endif

    // nonisolated(unsafe) is introduced in Swift 5.10
    #if swift(>=5.10)
        @objc public nonisolated(unsafe) static let shared: PostHogSDK = {
            let instance = PostHogSDK(PostHogConfig(apiKey: ""))
            return instance
        }()
    #else
        @objc public static let shared: PostHogSDK = {
            let instance = PostHogSDK(PostHogConfig(apiKey: ""))
            return instance
        }()
    #endif

    deinit {
        #if !os(watchOS)
            self.reachability?.stopNotifier()
        #endif

        uninstallIntegrations()
    }

    @objc public func debug(_ enabled: Bool = true) {
        if !isEnabled() {
            return
        }

        toggleHedgeLog(enabled)
    }

    @objc public func setup(_ config: PostHogConfig) {
        setupLock.withLock {
            toggleHedgeLog(config.debug)
            if enabled {
                hedgeLog("Setup called despite already being setup!")
                return
            }

            if PostHogSDK.apiKeys.contains(config.apiKey) {
                hedgeLog("API Key: \(config.apiKey) already has a PostHog instance.")
            } else {
                PostHogSDK.apiKeys.insert(config.apiKey)
            }

            enabled = true
            self.config = config
            let theStorage = PostHogStorage(config)
            storage = theStorage
            let api = PostHogApi(config)

            config.storageManager = config.storageManager ?? PostHogStorageManager(config)
            remoteConfig = PostHogRemoteConfig(config, theStorage, api) { [weak self] in
                self?.getDefaultPersonProperties() ?? [:]
            }

            #if !os(watchOS)
                do {
                    reachability = try Reachability()
                } catch {
                    // ignored
                }
                context = PostHogContext(reachability)
            #else
                context = PostHogContext()
            #endif

            optOutLock.withLock {
                let optOut = theStorage.getBool(forKey: .optOut)
                config.optOut = optOut ?? config.optOut
            }

            #if !os(watchOS)
                queue = PostHogQueue(config, theStorage, api, .batch, reachability)
                replayQueue = PostHogQueue(config, theStorage, api, .snapshot, reachability)
            #else
                queue = PostHogQueue(config, theStorage, api, .batch)
                replayQueue = PostHogQueue(config, theStorage, api, .snapshot)
            #endif

            queue?.start(disableReachabilityForTesting: config.disableReachabilityForTesting,
                         disableQueueTimerForTesting: config.disableQueueTimerForTesting)

            replayQueue?.start(disableReachabilityForTesting: config.disableReachabilityForTesting,
                               disableQueueTimerForTesting: config.disableQueueTimerForTesting)

            PostHogSessionManager.shared.startSession()

            if !config.optOut {
                // don't install integrations if in opt-out state
                installIntegrations()
            }

            DispatchQueue.main.async {
                NotificationCenter.default.post(name: PostHogSDK.didStartNotification, object: nil)
            }
        }
    }

    @objc public func getDistinctId() -> String {
        if !isEnabled() {
            return ""
        }

        return config.storageManager?.getDistinctId() ?? ""
    }

    @objc public func getAnonymousId() -> String {
        if !isEnabled() {
            return ""
        }

        return config.storageManager?.getAnonymousId() ?? ""
    }

    @objc public func getSessionId() -> String? {
        if !isEnabled() {
            return nil
        }

        return PostHogSessionManager.shared.getSessionId(readOnly: true)
    }

    @objc public func startSession() {
        if !isEnabled() {
            return
        }

        PostHogSessionManager.shared.startSession()
    }

    @objc public func endSession() {
        if !isEnabled() {
            return
        }

        PostHogSessionManager.shared.endSession()
    }

    // EVENT CAPTURE

    private func dynamicContext() -> [String: Any] {
        var properties = getRegisteredProperties()

        var groups: [String: String]?
        groupsLock.withLock {
            groups = getGroups()
        }
        if groups != nil, !groups!.isEmpty {
            properties["$groups"] = groups!
        }

        guard let flags = remoteConfig?.getFeatureFlags() as? [String: Any] else {
            return properties
        }

        var keys: [String] = []
        for (key, value) in flags {
            properties["$feature/\(key)"] = value

            var active = true
            let boolValue = value as? Bool
            if boolValue != nil {
                active = boolValue!
            } else {
                active = true
            }

            if active {
                keys.append(key)
            }
        }

        if !keys.isEmpty {
            properties["$active_feature_flags"] = keys
        }

        return properties
    }

    private func hasPersonProcessing() -> Bool {
        !(
            config.personProfiles == .never ||
                (
                    config.personProfiles == .identifiedOnly &&
                        config.storageManager?.isIdentified() == false &&
                        config.storageManager?.isPersonProcessing() == false
                )
        )
    }

    @discardableResult
    private func requirePersonProcessing() -> Bool {
        if config.personProfiles == .never {
            hedgeLog("personProfiles is set to `never`. This call will be ignored.")
            return false
        }
        config.storageManager?.setPersonProcessing(true)
        return true
    }

    private func buildProperties(distinctId: String,
                                 properties: [String: Any]?,
                                 userProperties: [String: Any]? = nil,
                                 userPropertiesSetOnce: [String: Any]? = nil,
                                 groups: [String: String]? = nil,
                                 appendSharedProps: Bool = true,
                                 timestamp: Date? = nil) -> [String: Any]
    {
        var props: [String: Any] = [:]

        if appendSharedProps {
            let staticCtx = context?.staticContext()
            let dynamicCtx = context?.dynamicContext()
            let localDynamicCtx = dynamicContext()

            if staticCtx != nil {
                props = props.merging(staticCtx ?? [:]) { current, _ in current }
            }
            if dynamicCtx != nil {
                props = props.merging(dynamicCtx ?? [:]) { current, _ in current }
            }
            props = props.merging(localDynamicCtx) { current, _ in current }
            if userProperties != nil {
                props["$set"] = (userProperties ?? [:])
            }
            if userPropertiesSetOnce != nil {
                props["$set_once"] = (userPropertiesSetOnce ?? [:])
            }
            if groups != nil {
                // $groups are also set via the dynamicContext
                let currentGroups = props["$groups"] as? [String: String] ?? [:]
                let mergedGroups = currentGroups.merging(groups ?? [:]) { current, _ in current }
                props["$groups"] = mergedGroups
            }

            if let isIdentified = config.storageManager?.isIdentified() {
                props["$is_identified"] = isIdentified
            }

            props["$process_person_profile"] = hasPersonProcessing()
        }

        let sdkInfo = context?.sdkInfo()
        if sdkInfo != nil {
            props = props.merging(sdkInfo ?? [:]) { current, _ in current }
        }

        // use existing session id if already present in properties (from params)
        // for session replay, we attach the session id on the event as early as possible to avoid sending snapshots to a wrong session
        // if not present, get a current or new session id at event timestamp
        let propSessionId = properties?["$session_id"] as? String
        let sessionId: String? = propSessionId.isNilOrEmpty
            ? PostHogSessionManager.shared.getSessionId(at: timestamp ?? now())
            : propSessionId

        if let sessionId {
            if propSessionId.isNilOrEmpty {
                props["$session_id"] = sessionId
            }
            // only Session replay requires $window_id, so we set as the same as $session_id.
            // the backend might fallback to $session_id if $window_id is not present next.
            #if os(iOS)
                if !appendSharedProps, isSessionReplayActive() {
                    props["$window_id"] = sessionId
                }
            #endif
        }

        // only Session Replay needs distinct_id also in the props
        // remove after https://github.com/PostHog/posthog/issues/23275 gets merged
        let propDistinctId = properties?["distinct_id"] as? String
        if !appendSharedProps, propDistinctId == nil || propDistinctId?.isEmpty == true {
            props["distinct_id"] = distinctId
        }

        props = props.merging(properties ?? [:]) { current, _ in current }

        return props
    }

    @objc public func flush() {
        if !isEnabled() {
            return
        }

        queue?.flush()
        replayQueue?.flush()
    }

    @objc public func reset() {
        if !isEnabled() {
            return
        }

        // storage also removes all feature flags
        storage?.reset(keepAnonymousId: config.reuseAnonymousId)
        config.storageManager?.reset(keepAnonymousId: config.reuseAnonymousId)
        flagCallReportedLock.withLock {
            flagCallReported.removeAll()
        }
        PostHogSessionManager.shared.resetSession()

        // Clear person and group properties for flags
        remoteConfig?.resetPersonPropertiesForFlags()
        remoteConfig?.resetGroupPropertiesForFlags()

        // reload flags as anon user
        remoteConfig?.reloadFeatureFlags()
    }

    private func getGroups() -> [String: String] {
        guard let groups = storage?.getDictionary(forKey: .groups) as? [String: String] else {
            return [:]
        }
        return groups
    }

    private func getRegisteredProperties() -> [String: Any] {
        guard let props = storage?.getDictionary(forKey: .registerProperties) as? [String: Any] else {
            return [:]
        }
        return props
    }

    // register is a reserved word in ObjC
    @objc(registerProperties:)
    public func register(_ properties: [String: Any]) {
        if !isEnabled() {
            return
        }

        let sanitizedProps = sanitizeDictionary(properties)
        if sanitizedProps == nil {
            return
        }

        personPropsLock.withLock {
            let props = getRegisteredProperties()
            let mergedProps = props.merging(sanitizedProps!) { _, new in new }
            storage?.setDictionary(forKey: .registerProperties, contents: mergedProps)
        }
    }

    @objc(unregisterProperties:)
    public func unregister(_ key: String) {
        if !isEnabled() {
            return
        }

        personPropsLock.withLock {
            var props = getRegisteredProperties()
            props.removeValue(forKey: key)
            storage?.setDictionary(forKey: .registerProperties, contents: props)
        }
    }

    @objc public func identify(_ distinctId: String) {
        identify(distinctId, userProperties: nil, userPropertiesSetOnce: nil)
    }

    @objc(identifyWithDistinctId:userProperties:)
    public func identify(_ distinctId: String,
                         userProperties: [String: Any]? = nil)
    {
        identify(distinctId, userProperties: userProperties, userPropertiesSetOnce: nil)
    }

    @objc(identifyWithDistinctId:userProperties:userPropertiesSetOnce:)
    public func identify(_ distinctId: String,
                         userProperties: [String: Any]? = nil,
                         userPropertiesSetOnce: [String: Any]? = nil)
    {
        if !isEnabled() {
            return
        }

        if distinctId.isEmpty {
            hedgeLog("identify call not allowed, distinctId is invalid: \(distinctId)")
            return
        }

        if isOptOutState() {
            return
        }

        if !requirePersonProcessing() {
            return
        }

        guard let queue, let storageManager = config.storageManager else {
            return
        }
        let oldDistinctId = getDistinctId()

        let isIdentified = storageManager.isIdentified()

        let hasDifferentDistinctId = distinctId != oldDistinctId

        if hasDifferentDistinctId, !isIdentified {
            var props: [String: Any] = ["distinct_id": distinctId]

            if !config.reuseAnonymousId {
                // We keep the AnonymousId to be used by flags calls and identify to link the previousId
                storageManager.setAnonymousId(oldDistinctId)
                props["$anon_distinct_id"] = oldDistinctId
            }

            storageManager.setDistinctId(distinctId)
            storageManager.setIdentified(true)

            let properties = buildProperties(
                distinctId: distinctId,
                properties: props,
                userProperties: sanitizeDictionary(userProperties),
                userPropertiesSetOnce: sanitizeDictionary(userPropertiesSetOnce)
            )

            guard let event = buildEvent(event: "$identify", distinctId: distinctId, properties: properties) else {
                return
            }

            queue.add(event)

            // Automatically set person properties for feature flags during identify() call
            setPersonPropertiesForFlagsIfNeeded(userProperties, userPropertiesSetOnce: userPropertiesSetOnce)

            remoteConfig?.reloadFeatureFlags()

            // we need to make sure the user props update is for the same user
            // otherwise they have to reset and identify again
        } else if !hasDifferentDistinctId, !(userProperties?.isEmpty ?? true) || !(userPropertiesSetOnce?.isEmpty ?? true) {
            capture("$set",
                    distinctId: distinctId,
                    userProperties: userProperties,
                    userPropertiesSetOnce: userPropertiesSetOnce)

            // Automatically set person properties for feature flags during user property updates
            setPersonPropertiesForFlagsIfNeeded(userProperties, userPropertiesSetOnce: userPropertiesSetOnce)

            // Note we don't reload flags on property changes as these get processed async

        } else {
            hedgeLog("already identified with id: \(oldDistinctId)")
        }
    }

    private func isOptOutState() -> Bool {
        if config.optOut {
            hedgeLog("PostHog is in OptOut state.")
            return true
        }
        return false
    }

    private func setPersonPropertiesForFlagsIfNeeded(
        _ userProperties: [String: Any]?,
        userPropertiesSetOnce: [String: Any]? = nil
    ) {
        guard hasPersonProcessing() else {
            return
        }

        let sanitizedUserProperties = sanitizeDictionary(userProperties) ?? [:]
        let sanitizedUserPropertiesSetOnce = sanitizeDictionary(userPropertiesSetOnce) ?? [:]

        // Combine both types of properties for feature flag evaluation
        let allProperties = sanitizedUserProperties.merging(sanitizedUserPropertiesSetOnce) { current, _ in current }

        guard !allProperties.isEmpty else {
            return
        }

        remoteConfig?.setPersonPropertiesForFlags(allProperties)
    }

    private func setGroupPropertiesForFlagsIfNeeded(
        type: String,
        groupProperties: [String: Any]?
    ) {
        guard hasPersonProcessing() else {
            return
        }

        let sanitizedGroupProperties = sanitizeDictionary(groupProperties) ?? [:]

        guard !sanitizedGroupProperties.isEmpty else {
            return
        }

        remoteConfig?.setGroupPropertiesForFlags(type, properties: sanitizedGroupProperties)
    }

    /// Returns fresh default device and app properties for feature flag evaluation.
    /// This ensures feature flags can use current properties like $app_version, $os_version, etc.
    /// These properties are computed fresh each time they're needed.
    private func getDefaultPersonProperties() -> [String: Any] {
        guard config.setDefaultPersonProperties else { return [:] }
        guard isEnabled() else { return [:] }

        return context?.personPropertiesContext() ?? [:]
    }

    @objc public func capture(_ event: String) {
        capture(event, distinctId: nil, properties: nil, userProperties: nil, userPropertiesSetOnce: nil, groups: nil)
    }

    @objc(captureWithEvent:properties:)
    public func capture(_ event: String,
                        properties: [String: Any]? = nil)
    {
        capture(event, distinctId: nil, properties: properties, userProperties: nil, userPropertiesSetOnce: nil, groups: nil)
    }

    @objc(captureWithEvent:properties:userProperties:)
    public func capture(_ event: String,
                        properties: [String: Any]? = nil,
                        userProperties: [String: Any]? = nil)
    {
        capture(event, distinctId: nil, properties: properties, userProperties: userProperties, userPropertiesSetOnce: nil, groups: nil)
    }

    @objc(captureWithEvent:properties:userProperties:userPropertiesSetOnce:)
    public func capture(_ event: String,
                        properties: [String: Any]? = nil,
                        userProperties: [String: Any]? = nil,
                        userPropertiesSetOnce: [String: Any]? = nil)
    {
        capture(event, distinctId: nil, properties: properties, userProperties: userProperties, userPropertiesSetOnce: userPropertiesSetOnce, groups: nil)
    }

    @objc(captureWithEvent:properties:userProperties:userPropertiesSetOnce:groups:)
    public func capture(_ event: String,
                        properties: [String: Any]? = nil,
                        userProperties: [String: Any]? = nil,
                        userPropertiesSetOnce: [String: Any]? = nil,
                        groups: [String: String]? = nil)
    {
        capture(event, distinctId: nil, properties: properties, userProperties: userProperties, userPropertiesSetOnce: userPropertiesSetOnce, groups: groups)
    }

    @objc(captureWithEvent:distinctId:properties:userProperties:userPropertiesSetOnce:groups:)
    public func capture(_ event: String,
                        distinctId: String? = nil,
                        properties: [String: Any]? = nil,
                        userProperties: [String: Any]? = nil,
                        userPropertiesSetOnce: [String: Any]? = nil,
                        groups: [String: String]? = nil)
    {
        capture(event,
                distinctId: distinctId,
                properties: properties,
                userProperties: userProperties,
                userPropertiesSetOnce: userPropertiesSetOnce,
                groups: groups,
                timestamp: nil)
    }

    @objc(captureWithEvent:distinctId:properties:userProperties:userPropertiesSetOnce:groups:timestamp:)
    public func capture(_ event: String,
                        distinctId: String? = nil,
                        properties: [String: Any]? = nil,
                        userProperties: [String: Any]? = nil,
                        userPropertiesSetOnce: [String: Any]? = nil,
                        groups: [String: String]? = nil,
                        timestamp: Date? = nil)
    {
        if !isEnabled() {
            return
        }

        if isOptOutState() {
            return
        }

        guard let queue else {
            return
        }

        var isSnapshotEvent = event == "$snapshot"
        let eventTimestamp = timestamp ?? now()
        let eventDistinctId = distinctId ?? getDistinctId()

        // if the user isn't identified but passed userProperties, userPropertiesSetOnce or groups,
        // we should still enable person processing since this is intentional
        if userProperties?.isEmpty == false || userPropertiesSetOnce?.isEmpty == false || groups?.isEmpty == false {
            requirePersonProcessing()
        }

        let properties = buildProperties(distinctId: eventDistinctId,
                                         properties: sanitizeDictionary(properties),
                                         userProperties: sanitizeDictionary(userProperties),
                                         userPropertiesSetOnce: sanitizeDictionary(userPropertiesSetOnce),
                                         groups: groups,
                                         appendSharedProps: !isSnapshotEvent,
                                         timestamp: timestamp)

        // Sanitize is now called in buildEvent
        let posthogEvent = buildEvent(
            event: event,
            distinctId: eventDistinctId,
            properties: properties,
            timestamp: eventTimestamp
        )

        guard let posthogEvent else {
            return
        }

        // Reevaluate if this is a snapshot event because the event might have been updated by the beforeSend hook
        isSnapshotEvent = posthogEvent.event == "$snapshot"

        // if this is a $snapshot event and $session_id is missing, don't process then event
        if isSnapshotEvent, posthogEvent.properties["$session_id"] == nil {
            return
        }

        // Session Replay has its own queue
        let targetQueue = isSnapshotEvent ? replayQueue : queue

        targetQueue?.add(posthogEvent)

        // Automatically set person properties for feature flags during capture event
        setPersonPropertiesForFlagsIfNeeded(userProperties, userPropertiesSetOnce: userPropertiesSetOnce)

        #if os(iOS)
            surveysIntegration?.onEvent(event: posthogEvent.event)
        #endif
    }

    @objc public func screen(_ screenTitle: String) {
        screen(screenTitle, properties: nil)
    }

    @objc(screenWithTitle:properties:)
    public func screen(_ screenTitle: String, properties: [String: Any]? = nil) {
        if !isEnabled() {
            return
        }

        if isOptOutState() {
            return
        }

        guard let queue else {
            return
        }

        let props = [
            "$screen_name": screenTitle,
        ].merging(sanitizeDictionary(properties) ?? [:]) { prop, _ in prop }

        let distinctId = getDistinctId()

        let properties = buildProperties(distinctId: distinctId, properties: props)

        guard let event = buildEvent(event: "$screen", distinctId: distinctId, properties: properties) else {
            return
        }

        queue.add(event)
    }

    func autocapture(
        eventType: String,
        elementsChain: String,
        properties: [String: Any]
    ) {
        if !isEnabled() {
            return
        }

        if isOptOutState() {
            return
        }

        guard let queue else {
            return
        }

        let props = [
            "$event_type": eventType,
            "$elements_chain": elementsChain,
        ].merging(sanitizeDictionary(properties) ?? [:]) { prop, _ in prop }

        let distinctId = getDistinctId()

        let properties = buildProperties(distinctId: distinctId, properties: props)

        guard let event = buildEvent(event: "$autocapture", distinctId: distinctId, properties: properties) else {
            return
        }

        queue.add(event)
    }

    private func sanitizeProperties(_ properties: [String: Any]) -> [String: Any] {
        if let sanitizer = config.propertiesSanitizer {
            return sanitizer.sanitize(properties)
        }
        return properties
    }

    @objc public func alias(_ alias: String) {
        if !isEnabled() {
            return
        }

        if isOptOutState() {
            return
        }

        if !requirePersonProcessing() {
            return
        }

        guard let queue else {
            return
        }

        let props = ["alias": alias]

        let distinctId = getDistinctId()

        let properties = buildProperties(distinctId: distinctId, properties: props)

        guard let event = buildEvent(event: "$create_alias", distinctId: distinctId, properties: properties) else {
            return
        }

        queue.add(event)
    }

    private func groups(_ newGroups: [String: String]) -> [String: String] {
        guard let storage else {
            return [:]
        }

        var groups: [String: String]?
        var mergedGroups: [String: String]?
        groupsLock.withLock {
            groups = getGroups()
            mergedGroups = groups?.merging(newGroups) { _, new in new }

            storage.setDictionary(forKey: .groups, contents: mergedGroups ?? [:])
        }

        var shouldReloadFlags = false

        for (key, value) in newGroups where groups?[key] != value {
            shouldReloadFlags = true
            break
        }

        if shouldReloadFlags {
            remoteConfig?.reloadFeatureFlags()
        }

        return mergedGroups ?? [:]
    }

    private func groupIdentify(type: String, key: String, groupProperties: [String: Any]? = nil) {
        if !isEnabled() {
            return
        }

        if isOptOutState() {
            return
        }

        guard let queue else {
            return
        }

        var props: [String: Any] = ["$group_type": type,
                                    "$group_key": key]

        let groupProps = sanitizeDictionary(groupProperties)

        if groupProps != nil {
            props["$group_set"] = groupProps
        }

        // Automatically set group properties for feature flags
        setGroupPropertiesForFlagsIfNeeded(type: type, groupProperties: groupProperties)

        // Same as .group but without associating the current user with the group
        let distinctId = getDistinctId()

        let properties = buildProperties(distinctId: distinctId, properties: props)

        guard let event = buildEvent(event: "$groupidentify", distinctId: distinctId, properties: properties) else {
            return
        }

        queue.add(event)
    }

    func buildEvent(event eventName: String, distinctId: String, properties: [String: Any], timestamp: Date = Date()) -> PostHogEvent? {
        let sanitizedProperties = sanitizeProperties(properties)

        let event = PostHogEvent(
            event: eventName,
            distinctId: distinctId,
            properties: sanitizedProperties,
            timestamp: timestamp
        )

        let resultEvent = config.runBeforeSend(event)

        if resultEvent == nil {
            let originalMessage = "PostHog event \(eventName) was dropped"
            let message = PostHogKnownUnsafeEditableEvent.contains(eventName)
                ? "\(originalMessage). This can cause unexpected behavior."
                : originalMessage

            hedgeLog(message)
        }

        return resultEvent
    }

    @objc(groupWithType:key:)
    public func group(type: String, key: String) {
        group(type: type, key: key, groupProperties: nil)
    }

    @objc(groupWithType:key:groupProperties:)
    public func group(type: String, key: String, groupProperties: [String: Any]? = nil) {
        if !isEnabled() {
            return
        }

        if isOptOutState() {
            return
        }

        if !requirePersonProcessing() {
            return
        }

        _ = groups([type: key])

        groupIdentify(type: type, key: key, groupProperties: sanitizeDictionary(groupProperties))
    }

    // FEATURE FLAGS

    /// Sets person properties that will be included in feature flag evaluation requests.
    ///
    /// This method allows you to override server-side person properties for immediate feature flag evaluation,
    /// solving the race condition where person properties from `identify()` calls may not have been processed
    /// by the server yet.
    ///
    /// Properties are merged additively with existing properties. Feature flags are automatically reloaded
    /// after setting properties.
    ///
    /// ## Example Usage
    /// ```swift
    /// // Set properties and automatically reload flags
    /// PostHogSDK.shared.setPersonPropertiesForFlags([
    ///     "$app_version": "2.93.0",
    ///     "plan": "premium"
    /// ])
    ///
    /// // Now feature flags will be evaluated with these properties
    /// let flagValue = PostHogSDK.shared.isFeatureEnabled("new_feature")
    /// ```
    ///
    /// - Parameter properties: Dictionary of person properties to include in flag evaluation
    /// - SeeAlso: `setPersonPropertiesForFlags(_:reloadFeatureFlags:)` to control flag reloading behavior
    @objc public func setPersonPropertiesForFlags(_ properties: [String: Any]) {
        setPersonPropertiesForFlags(properties, reloadFeatureFlags: true)
    }

    /// Sets person properties that will be included in feature flag evaluation requests.
    ///
    /// This method allows you to override server-side person properties for immediate feature flag evaluation,
    /// solving the race condition where person properties from `identify()` calls may not have been processed
    /// by the server yet.
    ///
    /// Properties are merged additively with existing properties.
    ///
    /// ## Example Usage
    /// ```swift
    /// // Set properties without automatically reloading flags
    /// PostHogSDK.shared.setPersonPropertiesForFlags([
    ///     "$app_version": "2.93.0",
    ///     "plan": "premium"
    /// ], reloadFeatureFlags: false)
    ///
    /// // Manually reload flags later
    /// PostHogSDK.shared.reloadFeatureFlags()
    /// ```
    ///
    /// - Parameters:
    ///   - properties: Dictionary of person properties to include in flag evaluation
    ///   - reloadFeatureFlags: Whether to automatically reload feature flags after setting properties
    @objc(setPersonPropertiesForFlagsWithProperties:reloadFeatureFlags:)
    public func setPersonPropertiesForFlags(_ properties: [String: Any], reloadFeatureFlags: Bool = true) {
        if !isEnabled() {
            return
        }

        guard hasPersonProcessing() else {
            return
        }

        let sanitizedProperties = sanitizeDictionary(properties) ?? [:]
        guard !sanitizedProperties.isEmpty else { return }
        remoteConfig?.setPersonPropertiesForFlags(sanitizedProperties)

        if reloadFeatureFlags {
            remoteConfig?.reloadFeatureFlags()
        }
    }

    /// Resets all person properties that were set for feature flag evaluation.
    ///
    /// After calling this method, feature flag evaluation will only use server-side person properties
    /// and will not include any locally overridden properties.
    ///
    /// ## Example Usage
    /// ```swift
    /// // Clear all locally set person properties for flags
    /// PostHogSDK.shared.resetPersonPropertiesForFlags()
    ///
    /// // Feature flags will now use only server-side properties
    /// let flagValue = PostHogSDK.shared.isFeatureEnabled("feature")
    /// ```
    ///
    /// - Note: This method does not automatically reload feature flags. Call `reloadFeatureFlags()`
    ///         after resetting if you want to immediately refresh flags with the cleared properties.
    @objc public func resetPersonPropertiesForFlags() {
        if !isEnabled() {
            return
        }

        guard hasPersonProcessing() else {
            return
        }

        remoteConfig?.resetPersonPropertiesForFlags()
    }

    /// Sets properties for a specific group type to include when evaluating feature flags.
    /// These properties supplement the standard group information sent to PostHog for flag evaluation,
    /// providing additional context that can be used in flag targeting conditions.
    ///
    /// ## Example Usage
    /// ```swift
    /// PostHogSDK.shared.setGroupPropertiesForFlags("organization", properties: [
    ///     "plan": "enterprise",
    ///     "seats": 50,
    ///     "industry": "technology"
    /// ])
    /// ```
    ///
    /// - Parameters:
    ///   - groupType: The group type identifier (e.g., "organization", "team")
    ///   - properties: Dictionary of properties to set for this group type
    /// - Note: This method automatically reloads feature flags to apply the new properties.
    /// - SeeAlso: `setGroupPropertiesForFlags(_:properties:reloadFeatureFlags:)` to control flag reloading behavior
    @objc(setGroupPropertiesForFlags:properties:)
    public func setGroupPropertiesForFlags(_ groupType: String, properties: [String: Any]) {
        setGroupPropertiesForFlags(groupType, properties: properties, reloadFeatureFlags: true)
    }

    /// Sets properties for a specific group type to include when evaluating feature flags.
    /// These properties supplement the standard group information sent to PostHog for flag evaluation,
    /// providing additional context that can be used in flag targeting conditions.
    ///
    /// ## Example Usage
    /// ```swift
    /// // Set properties without automatically reloading flags
    /// PostHogSDK.shared.setGroupPropertiesForFlags("organization", properties: [
    ///     "plan": "enterprise",
    ///     "seats": 50
    /// ], reloadFeatureFlags: false)
    ///
    /// // Manually reload flags later
    /// PostHogSDK.shared.reloadFeatureFlags()
    /// ```
    ///
    /// - Parameters:
    ///   - groupType: The group type identifier (e.g., "organization", "team")
    ///   - properties: Dictionary of properties to set for this group type
    ///   - reloadFeatureFlags: Whether to automatically reload feature flags after setting properties
    @objc(setGroupPropertiesForFlags:properties:reloadFeatureFlags:)
    public func setGroupPropertiesForFlags(_ groupType: String, properties: [String: Any], reloadFeatureFlags: Bool) {
        if !isEnabled() {
            return
        }

        guard hasPersonProcessing() else {
            return
        }

        let sanitizedProperties = sanitizeDictionary(properties) ?? [:]
        guard !sanitizedProperties.isEmpty else { return }
        remoteConfig?.setGroupPropertiesForFlags(groupType, properties: sanitizedProperties)

        if reloadFeatureFlags {
            remoteConfig?.reloadFeatureFlags()
        }
    }

    /// Clears all group properties for feature flag evaluation.
    ///
    /// ## Example Usage
    /// ```swift
    /// // Clear all group properties
    /// PostHogSDK.shared.resetGroupPropertiesForFlags()
    /// ```
    ///
    /// - Note: This method does not automatically reload feature flags. Call `reloadFeatureFlags()`
    ///         after resetting if you want to immediately refresh flags with the cleared properties.
    @objc public func resetGroupPropertiesForFlags() {
        resetGroupPropertiesForFlags(groupType: nil)
    }

    /// Clears group properties for feature flag evaluation for a specific group type.
    ///
    /// ## Example Usage
    /// ```swift
    /// // Clear properties for specific group type
    /// PostHogSDK.shared.resetGroupPropertiesForFlags("organization")
    /// ```
    ///
    /// - Parameter groupType: The group type to clear properties for
    /// - Note: This method does not automatically reload feature flags. Call `reloadFeatureFlags()`
    ///         after resetting if you want to immediately refresh flags with the cleared properties.
    @objc(resetGroupPropertiesForFlagsWithGroupType:)
    public func resetGroupPropertiesForFlags(_ groupType: String) {
        resetGroupPropertiesForFlags(groupType: groupType)
    }

    /// Internal implementation for resetting group properties.
    private func resetGroupPropertiesForFlags(groupType: String?) {
        if !isEnabled() {
            return
        }

        guard hasPersonProcessing() else {
            return
        }

        remoteConfig?.resetGroupPropertiesForFlags(groupType)
    }

    @objc public func reloadFeatureFlags() {
        reloadFeatureFlags {
            // No use case
        }
    }

    @objc(reloadFeatureFlagsWithCallback:)
    public func reloadFeatureFlags(_ callback: @escaping () -> Void) {
        if !isEnabled() {
            return
        }

        remoteConfig?.reloadFeatureFlags { _ in
            self.flagCallReportedLock.withLock {
                self.flagCallReported.removeAll()
            }
            callback()
        }
    }

    @objc public func getFeatureFlag(_ key: String) -> Any? {
        if !isEnabled() {
            return nil
        }

        guard let remoteConfig else {
            return nil
        }

        let value = remoteConfig.getFeatureFlag(key)

        if config.sendFeatureFlagEvent {
            reportFeatureFlagCalled(flagKey: key, flagValue: value)
        }

        return value
    }

    @objc public func isFeatureEnabled(_ key: String) -> Bool {
        let result = getFeatureFlag(key)
        return result is String ? true : (result as? Bool) ?? false
    }

    @objc public func getFeatureFlagPayload(_ key: String) -> Any? {
        if !isEnabled() {
            return nil
        }

        guard let remoteConfig else {
            return nil
        }

        return remoteConfig.getFeatureFlagPayload(key)
    }

    private func reportFeatureFlagCalled(flagKey: String, flagValue: Any?) {
        var shouldCapture = false

        flagCallReportedLock.withLock {
            if !flagCallReported.contains(flagKey) {
                flagCallReported.insert(flagKey)
                shouldCapture = true
            }
        }

        if shouldCapture {
            let requestId = remoteConfig?.lastRequestId ?? ""
            let details = remoteConfig?.getFeatureFlagDetails(flagKey)

            var properties = [
                "$feature_flag": flagKey,
                "$feature_flag_response": flagValue ?? NSNull(),
                "$feature_flag_request_id": requestId,
            ]

            if let details = details as? [String: Any] {
                if let reason = details["reason"] as? [String: Any] {
                    properties["$feature_flag_reason"] = reason["description"] ?? NSNull()
                }

                if let metadata = details["metadata"] as? [String: Any] {
                    properties["$feature_flag_id"] = metadata["id"] ?? NSNull()
                    properties["$feature_flag_version"] = metadata["version"] ?? NSNull()
                }
            }

            capture("$feature_flag_called", properties: properties)
        }
    }

    private func isEnabled() -> Bool {
        if !enabled {
            hedgeLog("PostHog method was called without `setup` being complete. Call wil be ignored.")
        }
        return enabled
    }

    @objc public func optIn() {
        if !isEnabled() {
            return
        }

        if !isOptOut() {
            return
        }

        optOutLock.withLock {
            config.optOut = false
            storage?.setBool(forKey: .optOut, contents: false)
        }

        setupLock.withLock {
            installIntegrations()
        }
    }

    @objc public func optOut() {
        if !isEnabled() {
            return
        }

        if isOptOut() {
            return
        }

        optOutLock.withLock {
            config.optOut = true
            storage?.setBool(forKey: .optOut, contents: true)
        }

        setupLock.withLock {
            uninstallIntegrations()
        }
    }

    @objc public func isOptOut() -> Bool {
        if !isEnabled() {
            return true
        }

        return config.optOut
    }

    @objc public func close() {
        if !isEnabled() {
            return
        }

        setupLock.withLock {
            enabled = false
            PostHogSDK.apiKeys.remove(config.apiKey)

            queue?.stop()
            replayQueue?.stop()

            queue = nil
            replayQueue = nil
            config.storageManager?.reset(keepAnonymousId: config.reuseAnonymousId)
            config.storageManager = nil
            config = PostHogConfig(apiKey: "")
            remoteConfig = nil
            storage = nil
            #if !os(watchOS)
                self.reachability?.stopNotifier()
                reachability = nil
            #endif
            flagCallReportedLock.withLock {
                flagCallReported.removeAll()
            }
            context = nil
            PostHogSessionManager.shared.endSession()
            toggleHedgeLog(false)

            uninstallIntegrations()
        }
    }

    #if os(iOS)
        /**
         Starts session recording.
         This method will have no effect if PostHog is not enabled, or if session replay is disabled in your project settings

         ## Note:
         - Calling this method will resume the current session or create a new one if it doesn't exist
         */
        @objc(startSessionRecording)
        public func startSessionRecording() {
            startSessionRecording(resumeCurrent: true)
        }

        /**
         Starts session recording.
         This method will have no effect if PostHog is not enabled, or if session replay is disabled in your project settings

         - Parameter resumeCurrent:
            Whether to resume recording of current session (true) or start a new session (false).
         */
        @objc(startSessionRecordingWithResumeCurrent:)
        public func startSessionRecording(resumeCurrent: Bool) {
            if !isEnabled() {
                return
            }

            if isOptOutState() {
                return
            }

            if replayIntegration == nil {
                // replay integration was not previously installed (probably disabled in config), attempt to install it
                setupLock.withLock {
                    installReplayIntegration()
                }
            }

            guard let replayIntegration else {
                return
            }

            if resumeCurrent, replayIntegration.isActive() {
                // nothing to resume, already active
                return
            }

            guard let remoteConfig, remoteConfig.isSessionReplayFlagActive() else {
                return hedgeLog("Could not start recording. Session replay feature flag is disabled.")
            }

            let sessionId = resumeCurrent
                ? PostHogSessionManager.shared.getSessionId()
                : PostHogSessionManager.shared.getNextSessionId()

            guard let sessionId else {
                return hedgeLog("Could not start recording. Missing session id.")
            }

            replayIntegration.start()
            hedgeLog("Session replay recording started. Session id is \(sessionId)")
        }

        /**
         Stops the current session recording if one is in progress.

         This method will have no effect if PostHog is not enabled
         */
        @objc public func stopSessionRecording() {
            if !isEnabled() {
                return
            }

            guard let replayIntegration, replayIntegration.isActive() else {
                return
            }

            replayIntegration.stop()
            hedgeLog("Session replay recording stopped.")
        }
    #endif

    @objc public static func with(_ config: PostHogConfig) -> PostHogSDK {
        let postHog = PostHogSDK(config)
        postHog.setup(config)
        return postHog
    }

    #if os(iOS)
        @objc public func isSessionReplayActive() -> Bool {
            if !isEnabled() {
                return false
            }

            guard let replayIntegration, let remoteConfig else {
                return false
            }

            return replayIntegration.isActive()
                && !PostHogSessionManager.shared.getSessionId(readOnly: true).isNilOrEmpty
                && remoteConfig.isSessionReplayFlagActive()
        }
    #endif

    #if os(iOS) || targetEnvironment(macCatalyst)
        @objc public func isAutocaptureActive() -> Bool {
            isEnabled() && config.captureElementInteractions
        }
    #endif

    private func installIntegrations() {
        guard installedIntegrations.isEmpty else {
            hedgeLog("Integrations already installed. Call uninstallIntegrations() first.")
            return
        }

        let integrations = config.getIntegrations()
        var installed: [PostHogIntegration] = []

        for integration in integrations {
            do {
                try integration.install(self)
                installed.append(integration)

                #if os(iOS)
                    // TODO: Decouple these two integrations from PostHogSDK intance
                    if let replayIntegration = integration as? PostHogReplayIntegration {
                        self.replayIntegration = replayIntegration
                    }

                    if let surveysIntegration = integration as? PostHogSurveyIntegration {
                        self.surveysIntegration = surveysIntegration
                    }
                #endif

                hedgeLog("Integration \(type(of: integration)) installed")
            } catch {
                hedgeLog("Integration \(type(of: integration)) failed to install: \(error)")
            }
        }

        installedIntegrations = installed
    }

    #if os(iOS)
        private func installReplayIntegration() {
            guard replayIntegration == nil else { return }

            let integration = PostHogReplayIntegration()
            do {
                try integration.install(self)
                installedIntegrations.append(integration)
                replayIntegration = integration

                hedgeLog("Integration \(type(of: integration)) installed")
            } catch {
                hedgeLog("Integration \(type(of: integration)) failed to install: \(error)")
            }
        }
    #endif

    private func uninstallIntegrations() {
        for integration in installedIntegrations {
            integration.uninstall(self)
            hedgeLog("Integration \(type(of: integration)) uninstalled")
        }
        installedIntegrations = []

        #if os(iOS)
            replayIntegration = nil
            surveysIntegration = nil
        #endif
    }
}

#if TESTING
    extension PostHogSDK {
        #if os(iOS) || targetEnvironment(macCatalyst)
            func getAutocaptureIntegration() -> PostHogAutocaptureIntegration? {
                installedIntegrations.compactMap {
                    $0 as? PostHogAutocaptureIntegration
                }.first
            }
        #endif

        #if os(iOS)
            func getReplayIntegration() -> PostHogReplayIntegration? {
                installedIntegrations.compactMap {
                    $0 as? PostHogReplayIntegration
                }.first
            }
        #endif

        func getAppLifeCycleIntegration() -> PostHogAppLifeCycleIntegration? {
            installedIntegrations.compactMap {
                $0 as? PostHogAppLifeCycleIntegration
            }.first
        }

        func getScreenViewIntegration() -> PostHogScreenViewIntegration? {
            installedIntegrations.compactMap {
                $0 as? PostHogScreenViewIntegration
            }.first
        }
    }
#endif

// swiftlint:enable file_length cyclomatic_complexity
