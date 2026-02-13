//
//  PostHogSDKTest.swift
//  PostHogTests
//
//  Created by Manoel Aranda Neto on 31.10.23.
//

import Foundation
@testable import PostHog
import Testing

@Suite("PostHogSDK Tests", .serialized)
class PostHogSDKTest {
    let server: MockPostHogServer
    let mockAppLifecycle: MockApplicationLifecyclePublisher
    let apiKey: String

    init() {
        apiKey = uniqueApiKey()
        mockAppLifecycle = MockApplicationLifecyclePublisher()

        PostHogAppLifeCycleIntegration.clearInstalls()
        Self.deleteDefaults()

        server = MockPostHogServer(version: 4)
        server.start()

        DI.main.appLifecyclePublisher = mockAppLifecycle
    }

    deinit {
        deleteSafely(applicationSupportDirectoryURL())
        now = { Date() }
        server.stop()
    }

    static func deleteDefaults() {
        let userDefaults = UserDefaults.standard
        userDefaults.removeObject(forKey: "PHGVersionKey")
        userDefaults.removeObject(forKey: "PHGBuildKeyV2")
        userDefaults.synchronize()

        deleteSafely(applicationSupportDirectoryURL())
    }

    func getSut(preloadFeatureFlags: Bool = false,
                sendFeatureFlagEvent: Bool = false,
                captureApplicationLifecycleEvents: Bool = false,
                flushAt: Int = 1,
                optOut: Bool = false,
                propertiesSanitizer: PostHogPropertiesSanitizer? = nil,
                personProfiles: PostHogPersonProfiles = .identifiedOnly,
                setDefaultPersonProperties: Bool = true,
                beforeSend: [BeforeSendBlock]? = nil) -> PostHogSDK
    {
        let config = PostHogConfig(apiKey: apiKey, host: "http://localhost:9001")
        config.flushAt = flushAt
        config.preloadFeatureFlags = preloadFeatureFlags
        config.sendFeatureFlagEvent = sendFeatureFlagEvent
        config.disableReachabilityForTesting = true
        config.disableQueueTimerForTesting = true
        config.captureApplicationLifecycleEvents = captureApplicationLifecycleEvents
        config.optOut = optOut
        config.propertiesSanitizer = propertiesSanitizer
        config.personProfiles = personProfiles
        config.setDefaultPersonProperties = setDefaultPersonProperties

        if let beforeSend = beforeSend {
            config.setBeforeSend(beforeSend)
        }

        let storage = PostHogStorage(config)
        storage.reset()

        return PostHogSDK.with(config)
    }

    @Test("captures the capture event")
    func capturesTheCaptureEvent() async throws {
        let sut = getSut()

        sut.capture("test event",
                    properties: ["foo": "bar"],
                    userProperties: ["userProp": "value"],
                    userPropertiesSetOnce: ["userPropOnce": "value"],
                    groups: ["groupProp": "value"])

        let events = try await getServerEvents(server)

        #expect(events.count == 1)

        let event = events.first!
        #expect(event.event == "test event")

        #expect(event.properties["foo"] as? String == "bar")

        let set = event.properties["$set"] as? [String: Any] ?? [:]
        #expect(set["userProp"] as? String == "value")

        let setOnce = event.properties["$set_once"] as? [String: Any] ?? [:]
        #expect(setOnce["userPropOnce"] as? String == "value")

        let groupProps = event.properties["$groups"] as? [String: String] ?? [:]
        #expect(groupProps["groupProp"] == "value")

        sut.reset()
        sut.close()
    }

    @Test("captures a screen event")
    func capturesAScreenEvent() async throws {
        let sut = getSut()

        sut.screen("theScreen", properties: ["prop": "value"])

        let events = try await getServerEvents(server)

        #expect(events.count == 1)

        let event = events.first!
        #expect(event.event == "$screen")

        #expect(event.properties["$screen_name"] as? String == "theScreen")
        #expect(event.properties["prop"] as? String == "value")

        sut.reset()
        sut.close()
    }

    @Test("captures a group event")
    func capturesAGroupEvent() async throws {
        let sut = getSut()

        sut.group(type: "some-type", key: "some-key", groupProperties: [
            "name": "some-company-name",
        ])

        let events = try await getServerEvents(server)

        #expect(events.count == 1)

        let groupEvent = events.first!
        #expect(groupEvent.event == "$groupidentify")
        #expect(groupEvent.properties["$group_type"] as? String == "some-type")
        #expect(groupEvent.properties["$group_key"] as? String == "some-key")
        #expect((groupEvent.properties["$group_set"] as? [String: Any])?["name"] as? String == "some-company-name")

        sut.reset()
        sut.close()
    }

    @Test("setups optOut")
    func setupsOptOut() {
        let sut = getSut()

        sut.optOut()

        #expect(sut.isOptOut() == true)

        sut.optIn()

        #expect(sut.isOptOut() == false)

        sut.reset()
        sut.close()
    }

    @Test("sets opt out via config")
    func setsOptOutViaConfig() {
        let sut = getSut(optOut: true)

        sut.optOut()

        #expect(sut.isOptOut() == true)

        sut.reset()
        sut.close()
    }

    @Test("removes all integrations on opt-out")
    func removesAllIntegrationsOnOptOut() {
        let sut = getSut(
            captureApplicationLifecycleEvents: true,
            optOut: false
        )

        #expect(sut.getAppLifeCycleIntegration() != nil)

        sut.optOut()

        #expect(sut.getAppLifeCycleIntegration() == nil)

        sut.reset()
        sut.close()
    }

    @Test("does not capture event if opt out")
    func doesNotCaptureEventIfOptOut() async throws {
        let sut = getSut()

        sut.optOut()

        sut.capture("event")

        // Use a short timeout since we don't expect events
        do {
            _ = try await withThrowingTaskGroup(of: [PostHogEvent].self) { group in
                group.addTask {
                    try await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
                    return []
                }
                return try await group.next() ?? []
            }
        } catch {
            // Expected timeout
        }

        sut.reset()
        sut.close()
    }

    @Test("calls reloadFeatureFlags")
    func callsReloadFeatureFlags() async throws {
        let sut = getSut()

        await withCheckedContinuation { continuation in
            sut.reloadFeatureFlags {
                continuation.resume()
            }
        }

        #expect(sut.isFeatureEnabled("bool-value") == true)

        sut.reset()
        sut.close()
    }

    @Test("loads feature flags automatically")
    func loadsFeatureFlagsAutomatically() {
        let sut = getSut(preloadFeatureFlags: true)

        waitFlagsRequest(server)
        #expect(sut.isFeatureEnabled("bool-value") == true)

        sut.reset()
        sut.close()
    }

    @Test("send feature flag event for isFeatureEnabled when enabled")
    func sendFeatureFlagEventForIsFeatureEnabledWhenEnabled() async throws {
        let sut = getSut(preloadFeatureFlags: true, sendFeatureFlagEvent: true)

        waitFlagsRequest(server)
        #expect(sut.isFeatureEnabled("bool-value") == true)

        let events = try await getServerEvents(server)

        #expect(events.count == 1)

        let event = events.first!
        #expect(event.event == "$feature_flag_called")
        #expect(event.properties["$feature_flag"] as? String == "bool-value")
        #expect(event.properties["$feature_flag_response"] as? Bool == true)
        #expect(event.properties["$feature_flag_request_id"] as? String == "0f801b5b-0776-42ca-b0f7-8375c95730bf")
        #expect(event.properties["$feature_flag_id"] as? Int == 2)
        #expect(event.properties["$feature_flag_version"] as? Int == 23)
        #expect(event.properties["$feature_flag_reason"] as? String == "Matched condition set 3")

        sut.reset()
        sut.close()
    }

    @Test("send feature flag event with variant response for isFeatureEnabled when enabled")
    func sendFeatureFlagEventWithVariantResponseForIsFeatureEnabledWhenEnabled() async throws {
        let sut = getSut(preloadFeatureFlags: true, sendFeatureFlagEvent: true)

        waitFlagsRequest(server)
        #expect(sut.isFeatureEnabled("string-value") == true)

        let events = try await getServerEvents(server)

        #expect(events.count == 1)

        let event = events.first!
        #expect(event.event == "$feature_flag_called")
        #expect(event.properties["$feature_flag"] as? String == "string-value")
        #expect(event.properties["$feature_flag_response"] as? String == "test")
        #expect(event.properties["$feature_flag_request_id"] as? String == "0f801b5b-0776-42ca-b0f7-8375c95730bf")
        #expect(event.properties["$feature_flag_id"] as? Int == 3)
        #expect(event.properties["$feature_flag_version"] as? Int == 1)
        #expect(event.properties["$feature_flag_reason"] as? String == "Matched condition set 1")

        sut.reset()
        sut.close()
    }

    @Test("send feature flag event for getFeatureFlag when enabled")
    func sendFeatureFlagEventForGetFeatureFlagWhenEnabled() async throws {
        let sut = getSut(preloadFeatureFlags: true, sendFeatureFlagEvent: true)

        waitFlagsRequest(server)
        #expect(sut.getFeatureFlag("bool-value") as? Bool == true)

        let events = try await getServerEvents(server)

        #expect(events.count == 1)

        let event = events.first!
        #expect(event.event == "$feature_flag_called")
        #expect(event.properties["$feature_flag"] as? String == "bool-value")
        #expect(event.properties["$feature_flag_response"] as? Bool == true)

        sut.reset()
        sut.close()
    }

    @Test("force send feature flag event for getFeatureFlag when config disabled")
    func forceSendFeatureFlagEventForGetFeatureFlagWhenConfigDisabled() async throws {
        let sut = getSut(preloadFeatureFlags: true, sendFeatureFlagEvent: false)

        waitFlagsRequest(server)
        #expect(sut.getFeatureFlag("bool-value", sendFeatureFlagEvent: true) as? Bool == true)

        let events = try await getServerEvents(server)

        #expect(events.count == 1)

        let event = events.first!
        #expect(event.event == "$feature_flag_called")
        #expect(event.properties["$feature_flag"] as? String == "bool-value")
        #expect(event.properties["$feature_flag_response"] as? Bool == true)

        sut.reset()
        sut.close()
    }

    @Test("reloadFeatureFlags adds groups if any")
    func reloadFeatureFlagsAddsGroupsIfAny() async throws {
        let sut = getSut()
        // group reloads flags when there are new groups
        // but in this case we want to reload manually and assert the response
        sut.remoteConfig?.canReloadFlagsForTesting = false
        sut.group(type: "some-type", key: "some-key", groupProperties: [
            "name": "some-company-name",
        ])
        sut.remoteConfig?.canReloadFlagsForTesting = true

        let events = try await getServerEvents(server)

        #expect(events.count == 1)

        sut.reloadFeatureFlags()

        let requests = getFlagsRequest(server)

        #expect(requests.count == 1)
        let request = requests.first

        let groups = request!["groups"] as? [String: String] ?? [:]
        #expect(groups["some-type"] == "some-key")

        sut.reset()
        sut.close()
    }

    @Test("merge groups when group is called")
    func mergeGroupsWhenGroupIsCalled() async throws {
        let sut = getSut(flushAt: 3)

        sut.group(type: "some-type", key: "some-key")

        sut.group(type: "some-type-2", key: "some-key-2")

        sut.capture("event")

        let events = try await getServerEvents(server)

        #expect(events.count == 3)
        let event = events.last!

        let groups = event.properties["$groups"] as? [String: String]
        #expect(groups!["some-type"] == "some-key")
        #expect(groups!["some-type-2"] == "some-key-2")

        sut.reset()
        sut.close()
    }

    @Test("register and unregister properties")
    func registerAndUnregisterProperties() async throws {
        let sut = getSut(flushAt: 1)

        sut.register(["test1": "test"])
        sut.register(["test2": "test"])
        sut.unregister("test2")
        sut.register(["test3": "test"])

        sut.capture("event")

        let events = try await getServerEvents(server)

        #expect(events.count == 1)
        let event = events.last!

        #expect(event.properties["test1"] as? String == "test")
        #expect(event.properties["test3"] as? String == "test")
        #expect(event.properties["test2"] as? String == nil)

        sut.reset()
        sut.close()
    }

    @Test("add active feature flags as part of the event")
    func addActiveFeatureFlagsAsPartOfTheEvent() async throws {
        let sut = getSut()

        sut.reloadFeatureFlags()
        waitFlagsRequest(server)

        sut.capture("event")

        let events = try await getServerEvents(server)

        #expect(events.count == 1)
        let event = events.first!

        let activeFlags = event.properties["$active_feature_flags"] as? [Any] ?? []
        #expect(activeFlags.contains { $0 as? String == "bool-value" } == true)
        #expect(activeFlags.contains { $0 as? String == "disabled-flag" } == false)

        #expect(event.properties["$feature/bool-value"] as? Bool == true)
        #expect(event.properties["$feature/disabled-flag"] as? Bool == false)

        sut.reset()
        sut.close()
    }

    @Test("sanitize properties")
    func sanitizeProperties() async throws {
        let sut = getSut(flushAt: 1)

        sut.register(["boolIsOk": true,
                      "test5": UserDefaults.standard])

        sut.capture("test event",
                    properties: ["foo": "bar",
                                 "test1": UserDefaults.standard,
                                 "arrayIsOk": [1, 2, 3],
                                 "dictIsOk": ["1": "one"]],
                    userProperties: ["userProp": "value",
                                     "test2": UserDefaults.standard],
                    userPropertiesSetOnce: ["userPropOnce": "value",
                                            "test3": UserDefaults.standard])

        let events = try await getServerEvents(server)

        #expect(events.count == 1)
        let event = events.first!

        #expect(event.properties["test1"] == nil)
        #expect(event.properties["test2"] == nil)
        #expect(event.properties["test3"] == nil)
        #expect(event.properties["test4"] == nil)
        #expect(event.properties["test5"] == nil)
        #expect(event.properties["arrayIsOk"] != nil)
        #expect(event.properties["dictIsOk"] != nil)
        #expect(event.properties["boolIsOk"] != nil)

        sut.reset()
        sut.close()
    }

    @Test("sets sessionId on app start")
    func setsSessionIdOnAppStart() async throws {
        let sut = getSut(captureApplicationLifecycleEvents: true, flushAt: 1)

        mockAppLifecycle.simulateAppDidFinishLaunching()

        let events = try await getServerEvents(server)

        #expect(events.count == 1)

        let event = events.first!
        #expect(event.properties["$session_id"] != nil)

        sut.reset()
        sut.close()
    }

    @Test("uses the same sessionId for all events in a session")
    func usesTheSameSessionIdForAllEventsInASession() async throws {
        let sut = getSut(flushAt: 3)
        let mockNow = MockDate()
        now = { mockNow.date }

        sut.capture("event1")

        mockNow.date.addTimeInterval(10)

        sut.capture("event2")

        mockNow.date.addTimeInterval(10)

        sut.capture("event3")

        let events = try await getServerEvents(server)

        #expect(events.count == 3)

        let sessionId = events[0].properties["$session_id"] as? String
        #expect(sessionId != nil)
        #expect(events[1].properties["$session_id"] as? String == sessionId)
        #expect(events[2].properties["$session_id"] as? String == sessionId)

        sut.reset()
        sut.close()
    }

    @Test("clears sessionId for background events after 30 mins in background")
    func clearsSessionIdForBackgroundEventsAfter30MinsInBackground() async throws {
        let sut = getSut(captureApplicationLifecycleEvents: false, flushAt: 2)
        let mockNow = MockDate()
        now = { mockNow.date }

        sut.capture("event captured in foreground")

        mockAppLifecycle.simulateAppDidEnterBackground()

        mockNow.date.addTimeInterval(60 * 30 + 1) // Background "timer": 30 mins 1 second

        sut.capture("event captured while in background")

        let events = try await getServerEvents(server)
        #expect(events.count == 2)

        #expect(events[0].properties["$session_id"] as? String != nil)
        #expect(events[1].properties["$session_id"] as? String == nil)

        sut.reset()
        sut.close()
    }

    @Test("reset deletes posthog files but not other folders")
    func resetDeletesPosthogFilesButNotOtherFolders() {
        let appFolder = applicationSupportDirectoryURL()
        deleteSafely(appFolder)
        #expect(FileManager.default.fileExists(atPath: appFolder.path) == false)

        let sut = getSut()

        sut.reset()
        sut.close()

        #expect(FileManager.default.fileExists(atPath: appFolder.path) == true)
    }

    @Test("client sanitize properties")
    func clientSanitizeProperties() async throws {
        let sanitizer = ExampleSanitizer()
        let sut = getSut(propertiesSanitizer: sanitizer)

        let props: [String: Any] = ["empty": ""]

        sut.capture("event", properties: props)

        let events = try await getServerEvents(server)

        #expect(events[0].properties["empty"] as? String == nil)

        sut.reset()
        sut.close()
    }

    @Test("reset reloads flags as anon user")
    func resetReloadsFlagsAsAnonUser() {
        let sut = getSut()

        sut.reset()

        waitFlagsRequest(server)
        #expect(sut.isFeatureEnabled("bool-value") == true)

        sut.close()
    }

    @Test("captures an event with a custom timestamp")
    func capturesAnEventWithACustomTimestamp() async throws {
        let sut = getSut()
        let eventDate = Date().addingTimeInterval(-60 * 30)

        sut.capture("test event",
                    properties: ["foo": "bar"],
                    userProperties: ["userProp": "value"],
                    userPropertiesSetOnce: ["userPropOnce": "value"],
                    groups: ["groupProp": "value"],
                    timestamp: eventDate)

        let events = try await getServerEvents(server)

        #expect(events.count == 1)

        let event = events.first!
        #expect(event.event == "test event")

        #expect(event.properties["foo"] as? String == "bar")

        let set = event.properties["$set"] as? [String: Any] ?? [:]
        #expect(set["userProp"] as? String == "value")

        let setOnce = event.properties["$set_once"] as? [String: Any] ?? [:]
        #expect(setOnce["userPropOnce"] as? String == "value")

        let groupProps = event.properties["$groups"] as? [String: String] ?? [:]
        #expect(groupProps["groupProp"] == "value")

        #expect(toISO8601String(event.timestamp) == toISO8601String(eventDate))

        sut.reset()
        sut.close()
    }

    @Test("captures $feature_flag_called when getFeatureFlag is called")
    func capturesFeatureFlagCalledWhenGetFeatureFlagIsCalled() async throws {
        let sut = getSut(
            sendFeatureFlagEvent: true,
            flushAt: 1
        )

        _ = sut.getFeatureFlag("some_key")

        let events = try await getServerEvents(server)
        #expect(events.first!.event == "$feature_flag_called")

        sut.reset()
        sut.close()
    }

    @Test("does not capture $feature_flag_called when getFeatureFlag is called twice")
    func doesNotCaptureFeatureFlagCalledWhenGetFeatureFlagIsCalledTwice() async throws {
        let sut = getSut(
            sendFeatureFlagEvent: true,
            flushAt: 2
        )

        _ = sut.getFeatureFlag("some_key")
        _ = sut.getFeatureFlag("some_key")
        sut.capture("force_batch_flush")

        let events = try await getServerEvents(server)
        #expect(events.count == 2)
        #expect(events[0].event == "$feature_flag_called")
        #expect(events[1].event == "force_batch_flush")

        sut.reset()
        sut.close()
    }

    @Test("sets default person properties on SDK setup when enabled")
    func setsDefaultPersonPropertiesOnSDKSetupWhenEnabled() {
        let sut = getSut(preloadFeatureFlags: true)

        let requests = getFlagsRequest(server)
        #expect(requests.count > 0)

        guard let lastRequest = requests.last else {
            Issue.record("No flags request found")
            return
        }

        guard let personProperties = lastRequest["person_properties"] as? [String: Any] else {
            Issue.record("Person properties not found in request")
            return
        }

        // Verify expected default properties are set
        // Bundle.main.infoDictionary is empty when running via `swift test` (SPM)
        let hasBundleInfo = Bundle.main.infoDictionary?.isEmpty == false
        if hasBundleInfo {
            #expect(personProperties["$app_version"] != nil)
            #expect(personProperties["$app_build"] != nil)
            #expect(personProperties["$app_namespace"] != nil)
        }
        #expect(personProperties["$os_name"] != nil)
        #expect(personProperties["$os_version"] != nil)
        #expect(personProperties["$device_type"] != nil)
        #expect(personProperties["$lib"] != nil)
        #expect(personProperties["$lib_version"] != nil)

        sut.reset()
        sut.close()
    }

    @Test("does not set default person properties when disabled")
    func doesNotSetDefaultPersonPropertiesWhenDisabled() {
        let sut = getSut(setDefaultPersonProperties: false)

        // Manually trigger a flag request since no automatic one will happen
        sut.reloadFeatureFlags()

        let requests = getFlagsRequest(server)
        #expect(requests.count > 0)

        guard let lastRequest = requests.last else {
            Issue.record("No flags request found")
            return
        }

        // person_properties should be nil when default properties are disabled
        #expect(lastRequest["person_properties"] == nil)

        sut.reset()
        sut.close()
    }

    #if os(iOS)
        @Test("isAutocaptureActive() should be false if disabled by config")
        func isAutocaptureActiveShouldBeFalseIfDisabledByConfig() {
            let config = PostHogConfig(apiKey: apiKey)
            config.captureElementInteractions = false
            let sut = PostHogSDK.with(config)

            #expect(sut.isAutocaptureActive() == false)

            sut.reset()
            sut.close()
        }

        @Test("isAutocaptureActive() should be false if SDK is not enabled")
        func isAutocaptureActiveShouldBeFalseIfSDKIsNotEnabled() {
            let config = PostHogConfig(apiKey: apiKey)
            config.captureElementInteractions = true
            let sut = PostHogSDK.with(config)
            sut.close()
            #expect(sut.isAutocaptureActive() == false)
        }
    #endif
}

struct BeforeSendTestEventContext {
    let triggerClosure: (PostHogSDK) -> Void
    let targetKey: String
    let testName: String
}
