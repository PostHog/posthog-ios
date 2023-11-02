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
    #if !os(watchOS)
        private var reachability: Reachability?
    #endif
    private var flagCallReported = Set<String>()
    private var featureFlags: PostHogFeatureFlags?
    private var context: PostHogContext?
    private static var apiKeys = Set<String>()
    private var capturedAppInstalled = false
    private var appFromBackground = false

    @objc public static let shared: PostHogSDK = {
        let instance = PostHogSDK(PostHogConfig(apiKey: ""))
        return instance
    }()

    deinit {
        #if !os(watchOS)
            self.reachability?.stopNotifier()
        #endif
    }

    @objc public func debug(_ enabled: Bool = true) {
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
            sessionManager = PostHogSessionManager(config)
            #if !os(watchOS)
                do {
                    reachability = try Reachability()
                } catch {
                    // ignored
                }
                context = PostHogContext(reachability)
            #endif

            optOutLock.withLock {
                let optOut = theStorage.getBool(forKey: .optOut)
                config.optOut = optOut ?? config.optOut
            }

            #if !os(watchOS)
                queue = PostHogQueue(config, theStorage, theApi, reachability)
            #else
                queue = PostHogQueue(config, theStorage, theApi)
            #endif

            queue?.start(disableReachabilityForTesting: config.disableReachabilityForTesting,
                         disableQueueTimerForTesting: config.disableQueueTimerForTesting)

            registerNotifications()
            captureScreenViews()

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

        guard let flags = featureFlags?.getFeatureFlags() as? [String: Any] else {
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

    private func buildProperties(properties: [String: Any]?,
                                 userProperties: [String: Any]? = nil,
                                 userPropertiesSetOnce: [String: Any]? = nil,
                                 groupProperties: [String: Any]? = nil) -> [String: Any]
    {
        var props: [String: Any] = [:]

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
        if groupProperties != nil {
            // $groups are also set via the dynamicContext
            let currentGroups = props["$groups"] as? [String: Any] ?? [:]
            let mergedGroups = currentGroups.merging(groupProperties ?? [:]) { current, _ in current }
            props["$groups"] = mergedGroups
        }
        props = props.merging(properties ?? [:]) { current, _ in current }

        return props
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

        let sanitizedProps = sanitizeDicionary(properties)
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

        guard let queue = queue, let sessionManager = sessionManager else {
            return
        }
        let oldDistinctId = getDistinctId()

        queue.add(PostHogEvent(
            event: "$identify",
            distinctId: distinctId,
            properties: buildProperties(properties: [
                "distinct_id": distinctId,
                "$anon_distinct_id": getAnonymousId(),
            ], userProperties: sanitizeDicionary(userProperties), userPropertiesSetOnce: sanitizeDicionary(userPropertiesSetOnce))
        ))

        if distinctId != oldDistinctId {
            // We keep the AnonymousId to be used by decide calls and identify to link the previousId
            sessionManager.setAnonymousId(oldDistinctId)
            sessionManager.setDistinctId(distinctId)

            reloadFeatureFlags()
        }
    }

    @objc public func capture(_ event: String) {
        capture(event, properties: nil, userProperties: nil, userPropertiesSetOnce: nil, groupProperties: nil)
    }

    @objc(captureWithEvent:properties:)
    public func capture(_ event: String,
                        properties: [String: Any]? = nil)
    {
        capture(event, properties: properties, userProperties: nil, userPropertiesSetOnce: nil, groupProperties: nil)
    }

    @objc(captureWithEvent:properties:userProperties:)
    public func capture(_ event: String,
                        properties: [String: Any]? = nil,
                        userProperties: [String: Any]? = nil)
    {
        capture(event, properties: properties, userProperties: userProperties, userPropertiesSetOnce: nil, groupProperties: nil)
    }

    @objc(captureWithEvent:properties:userProperties:userPropertiesSetOnce:)
    public func capture(_ event: String,
                        properties: [String: Any]? = nil,
                        userProperties: [String: Any]? = nil,
                        userPropertiesSetOnce: [String: Any]? = nil)
    {
        capture(event, properties: properties, userProperties: userProperties, userPropertiesSetOnce: userPropertiesSetOnce, groupProperties: nil)
    }

    @objc(captureWithEvent:properties:userProperties:userPropertiesSetOnce:groupProperties:)
    public func capture(_ event: String,
                        properties: [String: Any]? = nil,
                        userProperties: [String: Any]? = nil,
                        userPropertiesSetOnce: [String: Any]? = nil,
                        groupProperties: [String: Any]? = nil)
    {
        if !isEnabled() {
            return
        }

        guard let queue = queue else {
            return
        }
        queue.add(PostHogEvent(
            event: event,
            distinctId: getDistinctId(),
            properties: buildProperties(properties: sanitizeDicionary(properties),
                                        userProperties: sanitizeDicionary(userProperties),
                                        userPropertiesSetOnce: sanitizeDicionary(userPropertiesSetOnce),
                                        groupProperties: sanitizeDicionary(groupProperties))
        ))
    }

    @objc public func screen(_ screenTitle: String) {
        screen(screenTitle, properties: nil)
    }

    @objc(screenWithTitle:properties:)
    public func screen(_ screenTitle: String, properties: [String: Any]? = nil) {
        if !isEnabled() {
            return
        }

        guard let queue = queue else {
            return
        }

        let props = [
            "$screen_name": screenTitle,
        ].merging(sanitizeDicionary(properties) ?? [:]) { prop, _ in prop }

        queue.add(PostHogEvent(
            event: "$screen",
            distinctId: getDistinctId(),
            properties: buildProperties(properties: props)
        ))
    }

    @objc public func alias(_ alias: String) {
        if !isEnabled() {
            return
        }

        guard let queue = queue else {
            return
        }

        let props = ["alias": alias]

        queue.add(PostHogEvent(
            event: "$create_alias",
            distinctId: getDistinctId(),
            properties: buildProperties(properties: props)
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

    private func groupIdentify(type: String, key: String, groupProperties: [String: Any]? = nil) {
        if !isEnabled() {
            return
        }

        guard let queue = queue else {
            return
        }

        var props: [String: Any] = ["$group_type": type,
                                    "$group_key": key]

        let groupProps = sanitizeDicionary(groupProperties)

        if groupProps != nil {
            props["$group_set"] = groupProps
        }

        // Same as .group but without associating the current user with the group
        queue.add(PostHogEvent(
            event: "$groupidentify",
            distinctId: getDistinctId(),
            properties: buildProperties(properties: props)
        ))
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

        _ = groups([type: key])

        groupIdentify(type: type, key: key, groupProperties: sanitizeDicionary(groupProperties))
    }

    // FEATURE FLAGS
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
            callback: callback
        )
    }

    @objc public func getFeatureFlag(_ key: String) -> Any? {
        if !isEnabled() {
            return nil
        }

        guard let featureFlags = featureFlags else {
            return nil
        }

        let value = featureFlags.getFeatureFlag(key)

        if config.sendFeatureFlagEvent {
            reportFeatureFlagCalled(flagKey: key, flagValue: value)
        }

        return value
    }

    @objc public func isFeatureEnabled(_ key: String) -> Bool {
        if !isEnabled() {
            return false
        }

        guard let featureFlags = featureFlags else {
            return false
        }

        let value = featureFlags.isFeatureEnabled(key)

        if config.sendFeatureFlagEvent {
            reportFeatureFlagCalled(flagKey: key, flagValue: value)
        }

        return value
    }

    @objc public func getFeatureFlagPayload(_ key: String) -> Any? {
        if !isEnabled() {
            return nil
        }

        guard let featureFlags = featureFlags else {
            return nil
        }

        return featureFlags.getFeatureFlagPayload(key)
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
            #if !os(watchOS)
                self.reachability?.stopNotifier()
                reachability = nil
            #endif
            flagCallReported.removeAll()
            featureFlags = nil
        }
    }

    @objc public static func with(_ config: PostHogConfig) -> PostHogSDK {
        let postHog = PostHogSDK(config)
        postHog.setup(config)
        return postHog
    }

    private func registerNotifications() {
        let defaultCenter = NotificationCenter.default

        #if os(iOS) || os(tvOS)
            defaultCenter.addObserver(self,
                                      selector: #selector(captureAppLifecycle),
                                      name: UIApplication.didFinishLaunchingNotification,
                                      object: nil)
            defaultCenter.addObserver(self,
                                      selector: #selector(captureAppBackgrounded),
                                      name: UIApplication.didEnterBackgroundNotification,
                                      object: nil)
            defaultCenter.addObserver(self,
                                      selector: #selector(captureAppOpenedFromBackground),
                                      name: UIApplication.willEnterForegroundNotification,
                                      object: nil)
        #endif
    }

    private func captureScreenViews() {
        if config.captureScreenViews {
            #if os(iOS) || os(tvOS)
                UIViewController.swizzleScreenView()
            #endif
        }
    }

    func captureAppInstalled() {
        let bundle = Bundle.main

        let versionName = bundle.infoDictionary?["CFBundleShortVersionString"] as? String
        let versionCode = bundle.infoDictionary?["CFBundleVersion"] as? String

        // capture app installed/updated
        if !capturedAppInstalled {
            let userDefaults = UserDefaults.standard

            let previousVersion = userDefaults.string(forKey: "PHGVersionKey")
            let previousVersionCode = userDefaults.string(forKey: "PHGBuildKeyV2")

            var props: [String: Any] = [:]
            var event: String
            if previousVersionCode == nil {
                // installed
                event = "Application Installed"
            } else {
                event = "Application Updated"

                // Do not send version updates if its the same
                if previousVersionCode == versionCode {
                    return
                }

                if previousVersion != nil {
                    props["previous_version"] = previousVersion
                }
                props["previous_build"] = previousVersionCode
            }

            var syncDefaults = false
            if versionName != nil {
                props["version"] = versionName
                userDefaults.setValue(versionName, forKey: "PHGVersionKey")
                syncDefaults = true
            }

            if versionCode != nil {
                props["build"] = versionCode
                userDefaults.setValue(versionCode, forKey: "PHGBuildKeyV2")
                syncDefaults = true
            }

            if syncDefaults {
                userDefaults.synchronize()
            }

            capture(event, properties: props)

            capturedAppInstalled = true
        }
    }

    func captureAppOpened() {
        var props: [String: Any] = [:]
        props["from_background"] = false

        let bundle = Bundle.main

        let versionName = bundle.infoDictionary?["CFBundleShortVersionString"] as? String
        let versionCode = bundle.infoDictionary?["CFBundleVersion"] as? String

        if versionName != nil {
            props["version"] = versionName
        }
        if versionCode != nil {
            props["build"] = versionCode
        }

        capture("Application Opened", properties: props)
    }

    @objc func captureAppOpenedFromBackground() {
        var props: [String: Any] = [:]
        props["from_background"] = appFromBackground

        if !appFromBackground {
            appFromBackground = true
        }

        capture("Application Opened", properties: props)
    }

    @objc private func captureAppLifecycle() {
        if !config.captureApplicationLifecycleEvents {
            return
        }

        captureAppInstalled()
        captureAppOpened()
    }

    @objc func captureAppBackgrounded() {
        if !config.captureApplicationLifecycleEvents {
            return
        }
        capture("Application Backgrounded")
    }
}
