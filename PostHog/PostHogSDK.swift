//
//  PostHogSDK.swift
//  PostHogSDK
//
//  Created by Ben White on 07.02.23.
//

import Foundation

#if os(iOS) || os(tvOS)
    import UIKit
#endif

let retryDelay = 5.0
let maxRetryDelay = 30.0

// renamed to PostHogSDK due to https://github.com/apple/swift/issues/56573
@objc public class PostHogSDK: NSObject {
    private var config: PostHogConfig

    private init(_ config: PostHogConfig) {
        self.config = config
    }

    private var enabled = false
    private let setupLock = NSLock()
    private let optOutLock = NSLock()
    private let groupsLock = NSLock()
    private let personPropsLock = NSLock()

    private var queue: PostHogQueue?
    private var api: PostHogApi?
    private var storage: PostHogStorage?
    private var sessionManager: PostHogSessionManager?
    private var reachability: Reachability?
    private var flagCallReported = Set<String>()
    private var featureFlags: PostHogFeatureFlags?
    private var context: PostHogContext?
    private static var apiKeys = Set<String>()

    @objc public static let shared: PostHogSDK = {
        let instance = PostHogSDK(PostHogConfig(apiKey: ""))
        return instance
    }()

    deinit {
        self.reachability?.stopNotifier()
    }

    @objc public func debug(enabled: Bool = true) {
        if !isEnabled() {
            return
        }

        toggleHedgeLog(enabled)
    }

    @objc public func setup(_ config: PostHogConfig) {
        setupLock.withLock {
            if enabled {
                hedgeLog("Setup called despite already being setup!")
                return
            }

            if PostHogSDK.apiKeys.contains(config.apiKey) {
                hedgeLog("API Key: ${config.apiKey} already has a PostHog instance.")
            } else {
                PostHogSDK.apiKeys.insert(config.apiKey)
            }

            enabled = true
            self.config = config
            let theStorage = PostHogStorage(config)
            storage = theStorage
            let theApi = PostHogApi(config)
            api = theApi
            featureFlags = PostHogFeatureFlags(config, theStorage, theApi)
            sessionManager = PostHogSessionManager(config: config)
            do {
                reachability = try Reachability()
            } catch {
                // ignored
            }
            context = PostHogContext(reachability)

            optOutLock.withLock {
                let optOut = theStorage.getBool(forKey: .optOut)
                config.optOut = optOut ?? config.optOut
            }

            queue = PostHogQueue(config, theStorage, theApi, reachability)

            // TODO: Decide if we definitely want to reset the session on load or not
            sessionManager?.resetSession()

            queue?.start()

            DispatchQueue.main.async {
                NotificationCenter.default.post(name: PostHogSDK.didStartNotification, object: nil)
            }

            if config.preloadFeatureFlags {
                reloadFeatureFlags()
            }
        }
    }

    @objc public func getDistinctId() -> String {
        if !isEnabled() {
            return ""
        }

        return sessionManager?.getDistinctId() ?? ""
    }

    @objc public func getAnonymousId() -> String {
        if !isEnabled() {
            return ""
        }

        return sessionManager?.getAnonymousId() ?? ""
    }

    @objc public func getSessionId() -> String? {
        if !isEnabled() {
            return nil
        }

        return sessionManager?.getSessionId()
    }

    // EVENT CAPTURE

    private func dynamicContext() -> [String: Any] {
        var properties: [String: Any] = [:]

        properties["$session_id"] = getSessionId()
        var groups: [String: String]?
        groupsLock.withLock {
            groups = getGroups()
        }
        properties["$groups"] = groups ?? [:]

        guard let flags = featureFlags?.getFeatureFlags() as? [String: Any] else {
            return [:]
        }

        var keys: [String] = []
        for (key, value) in flags {
            properties["$feature/\(key)"] = value

            let boolValue = value as? Bool ?? false
            let active = boolValue ? boolValue : true

            if active {
                keys.append(key)
            }
        }

        if !keys.isEmpty {
            properties["$active_feature_flags"] = keys
        }

        return properties
    }

    private func buildProperties(_ properties: [String: Any]?) -> [String: Any] {
        // TODO: Add property coersion to ensure everything is codable
        (properties ?? [:])
            .merging(context?.staticContext() ?? [:]) { current, _ in current }
            .merging(context?.dynamicContext() ?? [:]) { current, _ in current }
            .merging(dynamicContext()) { current, _ in current }
    }

    @objc public func flush() {
        if !isEnabled() {
            return
        }

        queue?.flush()
    }

    @objc public func reset() {
        if !isEnabled() {
            return
        }

        storage?.reset()
        queue?.clear()
        flagCallReported.removeAll()
    }

    private func getGroups() -> [String: String] {
        guard let groups = storage?.getDictionary(forKey: .groups) as? [String: String] else {
            return [:]
        }
        return groups
    }

    private func getRegisteredProperties() -> [String: Any] {
        guard let props = storage?.getDictionary(forKey: .registerProperties) as? [String: String] else {
            return [:]
        }
        return props
    }

    @objc public func register(_ properties: [String: Any]) {
        if !isEnabled() {
            return
        }

        personPropsLock.withLock {
            // TODO: Sanitise props for storage
            let props = getRegisteredProperties()
            let mergedProps = props.merging(properties) { _, new in new }
            storage?.setDictionary(forKey: .registerProperties, contents: mergedProps)
        }
    }

    @objc public func unregister(_ key: String) {
        personPropsLock.withLock {
            var props = getRegisteredProperties()
            props.removeValue(forKey: key)
            storage?.setDictionary(forKey: .registerProperties, contents: props)
        }
    }

    @objc public func identify(_ distinctId: String, userProperties: [String: Any]? = nil) {
        if !isEnabled() {
            return
        }

        guard let queue = queue, let sessionManager = sessionManager else {
            return
        }
        let oldDistinctId = getDistinctId()

        queue.add(PostHogEvent(
            event: "$identify",
            distinctId: distinctId,
            properties: buildProperties([
                "distinct_id": distinctId,
                "$anon_distinct_id": getAnonymousId(),
                "$set": userProperties ?? [:],
            ])
        ))

        if distinctId != oldDistinctId {
            // We keep the AnonymousId to be used by decide calls and identify to link the previousId
            sessionManager.setAnonymousId(oldDistinctId)
            sessionManager.setDistinctId(distinctId)

            reloadFeatureFlags()
        }
    }

    @objc public func capture(_ event: String, properties: [String: Any]? = nil) {
        if !isEnabled() {
            return
        }

        guard let queue = queue else {
            return
        }
        queue.add(PostHogEvent(
            event: event,
            distinctId: getDistinctId(),
            properties: buildProperties(properties)
        ))
    }

    @objc public func screen(_ screenTitle: String, properties: [String: Any]? = nil) {
        if !isEnabled() {
            return
        }

        guard let queue = queue else {
            return
        }

        let props = [
            "$screen_name": screenTitle,
        ].merging(properties ?? [:]) { prop, _ in prop }

        queue.add(PostHogEvent(
            event: "$screen",
            distinctId: getDistinctId(),
            properties: buildProperties(props)
        ))
    }

    @objc public func alias(_ alias: String, properties: [String: Any]? = nil) {
        if !isEnabled() {
            return
        }

        guard let queue = queue else {
            return
        }

        let props = [
            "alias": alias,
        ].merging(properties ?? [:]) { prop, _ in prop }

        queue.add(PostHogEvent(
            event: "$create_alias",
            distinctId: getDistinctId(),
            properties: buildProperties(props)
        ))
    }

    private func groups(_ newGroups: [String: String]) -> [String: String] {
        guard let storage = storage else {
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
            reloadFeatureFlags()
        }

        return mergedGroups ?? [:]
    }

    @objc public func groupIdentify(type: String, key: String, groupProperties: [String: Any]? = nil) {
        if !isEnabled() {
            return
        }

        guard let queue = queue else {
            return
        }
        // Same as .group but without associating the current user with the group
        queue.add(PostHogEvent(
            event: "$groupidentify",
            distinctId: getDistinctId(),
            properties: buildProperties([
                "$group_type": type,
                "$group_key": key,
                "$group_set": groupProperties ?? [],
            ])
        ))
    }

    @objc public func group(type: String, key: String, groupProperties: [String: Any]? = nil) {
        if !isEnabled() {
            return
        }

        _ = groups([type: key])

        if groupProperties != nil {
            groupIdentify(type: type, key: key, groupProperties: groupProperties)
        }
    }

    // FEATURE FLAGS
    @objc public func reloadFeatureFlags() {
        reloadFeatureFlags { _, _ in
            // No use case
        }
    }

    @objc public func reloadFeatureFlags(_ completion: @escaping ([String: Any]?, [String: Any]?) -> Void) {
        if !isEnabled() {
            return
        }

        guard let featureFlags = featureFlags, let sessionManager = sessionManager else {
            return
        }

        var groups: [String: String]?
        groupsLock.withLock {
            groups = getGroups()
        }
        featureFlags.loadFeatureFlags(
            distinctId: sessionManager.getDistinctId(),
            anonymousId: sessionManager.getAnonymousId(),
            groups: groups ?? [:],
            completion: completion
        )
    }

    @objc public func getFeatureFlag(_ flagKey: String) -> Any? {
        if !isEnabled() {
            return nil
        }

        guard let featureFlags = featureFlags else {
            return nil
        }

        let value = featureFlags.getFeatureFlag(flagKey)

        if config.sendFeatureFlagEvent {
            reportFeatureFlagCalled(flagKey: flagKey, flagValue: value)
        }

        return value
    }

    @objc public func isFeatureEnabled(_ flagKey: String) -> Bool {
        if !isEnabled() {
            return false
        }

        guard let featureFlags = featureFlags else {
            return false
        }

        return featureFlags.isFeatureEnabled(flagKey)
    }

    @objc public func getFeatureFlagPayload(_ flagKey: String) -> Any? {
        if !isEnabled() {
            return nil
        }

        guard let featureFlags = featureFlags else {
            return nil
        }

        return featureFlags.getFeatureFlagPayload(flagKey)
    }

    private func reportFeatureFlagCalled(flagKey: String, flagValue: Any?) {
        if !flagCallReported.contains(flagKey) {
            let properties: [String: Any] = [
                "$feature_flag": flagKey,
                "$feature_flag_response": flagValue ?? "",
            ]

            flagCallReported.insert(flagKey)

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

        optOutLock.withLock {
            config.optOut = false
            storage?.setBool(forKey: .optOut, contents: false)
        }
    }

    @objc public func optOut() {
        if !isEnabled() {
            return
        }

        optOutLock.withLock {
            config.optOut = true
            storage?.setBool(forKey: .optOut, contents: true)
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
            queue = nil
            sessionManager = nil
            config = PostHogConfig(apiKey: "")
            api = nil
            self.reachability?.stopNotifier()
            reachability = nil
            flagCallReported.removeAll()
            featureFlags = nil
        }
    }

    @objc public static func with(_ config: PostHogConfig) -> PostHogSDK {
        let postHog = PostHogSDK(config)
        postHog.setup(config)
        return postHog
    }
}
