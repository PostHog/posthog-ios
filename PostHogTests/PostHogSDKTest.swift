//
//  PostHogSDKTest.swift
//  PostHogTests
//
//  Created by Manoel Aranda Neto on 31.10.23.
//

import Foundation
import Nimble
import Quick

@testable import PostHog

class PostHogSDKTest: QuickSpec {
    func getSut(preloadFeatureFlags: Bool = false,
                sendFeatureFlagEvent: Bool = false,
                captureApplicationLifecycleEvents: Bool = false,
                flushAt: Int = 1,
                optOut: Bool = false,
                propertiesSanitizer: PostHogPropertiesSanitizer? = nil,
                personProfiles: PostHogPersonProfiles = .identifiedOnly) -> PostHogSDK
    {
        let config = PostHogConfig(apiKey: testAPIKey, host: "http://localhost:9001")
        config.flushAt = flushAt
        config.preloadFeatureFlags = preloadFeatureFlags
        config.sendFeatureFlagEvent = sendFeatureFlagEvent
        config.disableReachabilityForTesting = true
        config.disableQueueTimerForTesting = true
        config.captureApplicationLifecycleEvents = captureApplicationLifecycleEvents
        config.optOut = optOut
        config.propertiesSanitizer = propertiesSanitizer
        config.personProfiles = personProfiles
        return PostHogSDK.with(config)
    }

    override func spec() {
        var server: MockPostHogServer!

        func deleteDefaults() {
            let userDefaults = UserDefaults.standard
            userDefaults.removeObject(forKey: "PHGVersionKey")
            userDefaults.removeObject(forKey: "PHGBuildKeyV2")
            userDefaults.synchronize()

            deleteSafely(applicationSupportDirectoryURL())
        }

        beforeEach {
            deleteDefaults()
            server = MockPostHogServer()
            server.start()
        }
        afterEach {
            now = { Date() }
            server.stop()
            server = nil
            PostHogSessionManager.shared.endSession {}
        }

        it("captures the capture event") {
            let sut = self.getSut()

            sut.capture("test event",
                        properties: ["foo": "bar"],
                        userProperties: ["userProp": "value"],
                        userPropertiesSetOnce: ["userPropOnce": "value"],
                        groups: ["groupProp": "value"])

            let events = getBatchedEvents(server)

            expect(events.count) == 1

            let event = events.first!
            expect(event.event) == "test event"

            expect(event.properties["foo"] as? String) == "bar"

            let set = event.properties["$set"] as? [String: Any] ?? [:]
            expect(set["userProp"] as? String) == "value"

            let setOnce = event.properties["$set_once"] as? [String: Any] ?? [:]
            expect(setOnce["userPropOnce"] as? String) == "value"

            let groupProps = event.properties["$groups"] as? [String: String] ?? [:]
            expect(groupProps["groupProp"]) == "value"

            sut.reset()
            sut.close()
        }

        it("captures the capture event with a custom distinctId") {
            let sut = self.getSut()

            sut.capture("event",
                        distinctId: "the_custom_distinct_id",
                        properties: ["foo": "bar"],
                        userProperties: ["userProp": "value"],
                        userPropertiesSetOnce: ["userPropOnce": "value"],
                        groups: ["groupProp": "value"])

            let events = getBatchedEvents(server)

            expect(events.count) == 1
            expect(events.first!.distinctId) == "the_custom_distinct_id"

            sut.reset()
            sut.close()
        }

        it("captures an identify event") {
            let sut = self.getSut()

            sut.identify("distinctId",
                         userProperties: ["userProp": "value"],
                         userPropertiesSetOnce: ["userPropOnce": "value"])

            let events = getBatchedEvents(server)

            expect(events.count) == 1

            let event = events.first!
            expect(event.event) == "$identify"

            expect(event.distinctId) == "distinctId"
            let anonId = sut.getAnonymousId()
            expect(event.properties["$anon_distinct_id"] as? String) == anonId
            expect(event.properties["$is_identified"] as? Bool) == true

            let set = event.properties["$set"] as? [String: Any] ?? [:]
            expect(set["userProp"] as? String) == "value"

            let setOnce = event.properties["$set_once"] as? [String: Any] ?? [:]
            expect(setOnce["userPropOnce"] as? String) == "value"

            sut.reset()
            sut.close()
        }

        it("captures an event with is identified false") {
            let sut = self.getSut()

            sut.capture("test",
                        userProperties: ["userProp": "value"],
                        userPropertiesSetOnce: ["userPropOnce": "value"])

            let events = getBatchedEvents(server)

            expect(events.count) == 1

            let event = events.first!

            expect(event.properties["$is_identified"] as? Bool) == false

            sut.reset()
            sut.close()
        }

        it("does not capture identify event if already identified") {
            let sut = self.getSut(
                flushAt: 2
            )

            sut.identify("distinctId",
                         userProperties: ["userProp": "value"],
                         userPropertiesSetOnce: ["userPropOnce": "value"])

            sut.identify("distinctId")
            sut.capture("satisfy_queue")

            let events = getBatchedEvents(server)

            expect(events.count) == 2

            expect(events[0].event) == "$identify"
            expect(events[1].event) == "satisfy_queue"

            expect(events[0].distinctId) == "distinctId"
            let anonId = sut.getAnonymousId()
            expect(events[0].properties["$anon_distinct_id"] as? String) == anonId
            expect(events[0].properties["$is_identified"] as? Bool) == true

            let set = events[0].properties["$set"] as? [String: Any] ?? [:]
            expect(set["userProp"] as? String) == "value"

            let setOnce = events[0].properties["$set_once"] as? [String: Any] ?? [:]
            expect(setOnce["userPropOnce"] as? String) == "value"

            sut.reset()
            sut.close()
        }

        it("updates user props if already identified but user properties are set") {
            let sut = self.getSut(
                flushAt: 2
            )

            sut.identify("distinctId",
                         userProperties: ["userProp": "value"],
                         userPropertiesSetOnce: ["userPropOnce": "value"])

            sut.identify("distinctId",
                         userProperties: ["userProp2": "value2"],
                         userPropertiesSetOnce: ["userPropOnce2": "value2"])

            let events = getBatchedEvents(server)

            expect(events.count) == 2

            expect(events[0].event) == "$identify"
            expect(events[1].event) == "$set"

            expect(events[0].distinctId) == "distinctId"
            expect(events[1].distinctId) == events[0].distinctId

            let anonId = sut.getAnonymousId()
            expect(events[0].properties["$anon_distinct_id"] as? String) == anonId
            expect(events[0].properties["$is_identified"] as? Bool) == true

            let set0 = events[0].properties["$set"] as? [String: Any] ?? [:]
            expect(set0["userProp"] as? String) == "value"

            let set1 = events[1].properties["$set"] as? [String: Any] ?? [:]
            expect(set1["userProp2"] as? String) == "value2"

            let setOnce0 = events[0].properties["$set_once"] as? [String: Any] ?? [:]
            expect(setOnce0["userPropOnce"] as? String) == "value"

            let setOnce1 = events[1].properties["$set_once"] as? [String: Any] ?? [:]
            expect(setOnce1["userPropOnce2"] as? String) == "value2"

            sut.reset()
            sut.close()
        }

        it("does not capture user props for another distinctId even if user properties are set") {
            let sut = self.getSut(
                flushAt: 2
            )

            sut.identify("distinctId",
                         userProperties: ["userProp": "value"],
                         userPropertiesSetOnce: ["userPropOnce": "value"])

            sut.identify("distinctId2",
                         userProperties: ["userProp2": "value2"],
                         userPropertiesSetOnce: ["userPropOnce2": "value2"])

            sut.capture("satisfy_queue")

            let events = getBatchedEvents(server)

            expect(events.count) == 2

            expect(events[0].event) == "$identify"
            expect(events[1].event) == "satisfy_queue"

            expect(events[0].distinctId) == "distinctId"
            let anonId = sut.getAnonymousId()
            expect(events[0].properties["$anon_distinct_id"] as? String) == anonId
            expect(events[0].properties["$is_identified"] as? Bool) == true

            let set = events[0].properties["$set"] as? [String: Any] ?? [:]
            expect(set["userProp"] as? String) == "value"

            let setOnce = events[0].properties["$set_once"] as? [String: Any] ?? [:]
            expect(setOnce["userPropOnce"] as? String) == "value"

            sut.reset()
            sut.close()
        }

        it("captures an alias event") {
            let sut = self.getSut()

            sut.alias("theAlias")

            let events = getBatchedEvents(server)

            expect(events.count) == 1

            let event = events.first!
            expect(event.event) == "$create_alias"

            expect(event.properties["alias"] as? String) == "theAlias"

            sut.reset()
            sut.close()
        }

        it("captures a screen event") {
            let sut = self.getSut()

            sut.screen("theScreen", properties: ["prop": "value"])

            let events = getBatchedEvents(server)

            expect(events.count) == 1

            let event = events.first!
            expect(event.event) == "$screen"

            expect(event.properties["$screen_name"] as? String) == "theScreen"
            expect(event.properties["prop"] as? String) == "value"

            sut.reset()
            sut.close()
        }

        it("captures a group event") {
            let sut = self.getSut()

            sut.group(type: "some-type", key: "some-key", groupProperties: [
                "name": "some-company-name",
            ])

            let events = getBatchedEvents(server)

            expect(events.count) == 1

            let groupEvent = events.first!
            expect(groupEvent.event) == "$groupidentify"
            expect(groupEvent.properties["$group_type"] as? String?) == "some-type"
            expect(groupEvent.properties["$group_key"] as? String?) == "some-key"
            expect((groupEvent.properties["$group_set"] as? [String: Any])?["name"] as? String) == "some-company-name"

            sut.reset()
            sut.close()
        }

        it("setups default IDs") {
            let sut = self.getSut()

            expect(sut.getAnonymousId()).toNot(beNil())
            expect(sut.getDistinctId()) == sut.getAnonymousId()

            sut.reset()
            sut.close()
        }

        it("setups optOut") {
            let sut = self.getSut()

            sut.optOut()

            expect(sut.isOptOut()) == true

            sut.optIn()

            expect(sut.isOptOut()) == false

            sut.reset()
            sut.close()
        }

        it("sets opt out via config") {
            let sut = self.getSut(optOut: true)

            sut.optOut()

            expect(sut.isOptOut()) == true

            sut.reset()
            sut.close()
        }

        it("does not capture event if opt out") {
            let sut = self.getSut()

            sut.optOut()

            sut.capture("event")

            // no need to await 15s
            let events = getBatchedEvents(server, timeout: 1.0, failIfNotCompleted: false)
            expect(events.count) == 0

            sut.reset()
            sut.close()
        }

        it("calls reloadFeatureFlags") {
            let sut = self.getSut()

            let group = DispatchGroup()
            group.enter()

            sut.reloadFeatureFlags {
                group.leave()
            }

            group.wait()

            expect(sut.isFeatureEnabled("bool-value")) == true

            sut.reset()
            sut.close()
        }

        it("identify sets distinct and anon Ids") {
            let sut = self.getSut()

            let distId = sut.getDistinctId()

            sut.identify("newDistinctId")

            expect(sut.getDistinctId()) == "newDistinctId"
            expect(sut.getAnonymousId()) == distId

            sut.reset()
            sut.close()
        }

        it("loads feature flags automatically") {
            let sut = self.getSut(preloadFeatureFlags: true)

            waitDecideRequest(server)
            expect(sut.isFeatureEnabled("bool-value")) == true

            sut.reset()
            sut.close()
        }

        it("send feature flag event for isFeatureEnabled when enabled") {
            let sut = self.getSut(preloadFeatureFlags: true, sendFeatureFlagEvent: true)

            waitDecideRequest(server)
            expect(sut.isFeatureEnabled("bool-value")) == true

            let events = getBatchedEvents(server)

            expect(events.count) == 1

            let event = events.first!
            expect(event.event) == "$feature_flag_called"
            expect(event.properties["$feature_flag"] as? String) == "bool-value"
            expect(event.properties["$feature_flag_response"] as? Bool) == true

            sut.reset()
            sut.close()
        }

        it("send feature flag event for getFeatureFlag when enabled") {
            let sut = self.getSut(preloadFeatureFlags: true, sendFeatureFlagEvent: true)

            waitDecideRequest(server)
            expect(sut.getFeatureFlag("bool-value") as? Bool) == true

            let events = getBatchedEvents(server)

            expect(events.count) == 1

            let event = events.first!
            expect(event.event) == "$feature_flag_called"
            expect(event.properties["$feature_flag"] as? String) == "bool-value"
            expect(event.properties["$feature_flag_response"] as? Bool) == true

            sut.reset()
            sut.close()
        }

        it("capture AppBackgrounded") {
            let sut = self.getSut(captureApplicationLifecycleEvents: true)

            sut.handleAppDidEnterBackground()

            let events = getBatchedEvents(server)

            expect(events.count) == 1

            let event = events.first!
            expect(event.event) == "Application Backgrounded"

            sut.reset()
            sut.close()
        }

        it("capture AppInstalled") {
            let sut = self.getSut(captureApplicationLifecycleEvents: true)

            sut.handleAppDidFinishLaunching()

            let events = getBatchedEvents(server)

            expect(events.count) == 1

            let event = events.first!
            expect(event.event) == "Application Installed"
            expect(event.properties["version"] as? String) != nil
            expect(event.properties["build"] as? String) != nil

            sut.reset()
            sut.close()
        }

        it("capture AppUpdated") {
            let sut = self.getSut(captureApplicationLifecycleEvents: true)

            let userDefaults = UserDefaults.standard
            userDefaults.setValue("1.0.0", forKey: "PHGVersionKey")
            userDefaults.setValue("1", forKey: "PHGBuildKeyV2")
            userDefaults.synchronize()

            sut.handleAppDidFinishLaunching()

            let events = getBatchedEvents(server)

            expect(events.count) == 1

            let event = events.first!
            expect(event.event) == "Application Updated"
            expect(event.properties["version"] as? String) != nil
            expect(event.properties["build"] as? String) != nil
            expect(event.properties["previous_version"] as? String) != nil
            expect(event.properties["previous_build"] as? String) != nil

            sut.reset()
            sut.close()
        }

        it("capture AppOpenedFromBackground from_background should be false") {
            let sut = self.getSut(captureApplicationLifecycleEvents: true)

            sut.handleAppDidBecomeActive()

            let events = getBatchedEvents(server)

            expect(events.count) == 1

            let event = events.first!
            expect(event.event) == "Application Opened"
            expect(event.properties["from_background"] as? Bool) == false

            sut.reset()
            sut.close()
        }

        it("capture AppOpenedFromBackground from_background should be true") {
            let sut = self.getSut(captureApplicationLifecycleEvents: true, flushAt: 2)

            sut.handleAppDidBecomeActive()
            sut.handleAppDidBecomeActive()

            let events = getBatchedEvents(server)

            expect(events.count) == 2

            let event = events.last!
            expect(event.event) == "Application Opened"
            expect(event.properties["from_background"] as? Bool) == true

            sut.reset()
            sut.close()
        }

        it("capture captureAppOpened") {
            let sut = self.getSut(captureApplicationLifecycleEvents: true)

            sut.handleAppDidBecomeActive()

            let events = getBatchedEvents(server)

            expect(events.count) == 1

            let event = events.first!
            expect(event.event) == "Application Opened"
            expect(event.properties["from_background"] as? Bool) == false
            expect(event.properties["version"] as? String) != nil
            expect(event.properties["build"] as? String) != nil

            sut.reset()
            sut.close()
        }

        it("does not capture life cycle events") {
            let sut = self.getSut()

            sut.handleAppDidFinishLaunching()
            sut.handleAppDidBecomeActive()
            sut.handleAppDidEnterBackground()

            sut.screen("test")

            let events = getBatchedEvents(server)

            expect(events.count) == 1

            let event = events.first!
            expect(event.event) == "$screen"

            sut.reset()
            sut.close()
        }

        it("reloadFeatureFlags adds groups if any") {
            let sut = self.getSut()
            // group reloads flags when there are new groups
            // but in this case we want to reload manually and assert the response
            // sut.shouldReloadFlagsForTesting = false
            sut.remoteConfig?.canReloadFlagsForTesting = false
            sut.group(type: "some-type", key: "some-key", groupProperties: [
                "name": "some-company-name",
            ])
            sut.remoteConfig?.canReloadFlagsForTesting = true

            let events = getBatchedEvents(server)

            expect(events.count) == 1

            sut.reloadFeatureFlags()

            let requests = getDecideRequest(server)

            expect(requests.count) == 1
            let request = requests.first

            let groups = request!["$groups"] as? [String: String] ?? [:]
            expect(groups["some-type"]) == "some-key"

            sut.reset()
            sut.close()
        }

        it("merge groups when group is called") {
            let sut = self.getSut(flushAt: 3)

            sut.group(type: "some-type", key: "some-key")

            sut.group(type: "some-type-2", key: "some-key-2")

            sut.capture("event")

            let events = getBatchedEvents(server)

            expect(events.count) == 3
            let event = events.last!

            let groups = event.properties["$groups"] as? [String: String]
            expect(groups!["some-type"]) == "some-key"
            expect(groups!["some-type-2"]) == "some-key-2"

            sut.reset()
            sut.close()
        }

        it("register and unregister properties") {
            let sut = self.getSut(flushAt: 1)

            sut.register(["test1": "test"])
            sut.register(["test2": "test"])
            sut.unregister("test2")
            sut.register(["test3": "test"])

            sut.capture("event")

            let events = getBatchedEvents(server)

            expect(events.count) == 1
            let event = events.last!

            expect(event.properties["test1"] as? String) == "test"
            expect(event.properties["test3"] as? String) == "test"
            expect(event.properties["test2"] as? String) == nil

            sut.reset()
            sut.close()
        }

        it("add active feature flags as part of the event") {
            let sut = self.getSut()

            sut.reloadFeatureFlags()
            waitDecideRequest(server)

            sut.capture("event")

            let events = getBatchedEvents(server)

            expect(events.count) == 1
            let event = events.first!

            let activeFlags = event.properties["$active_feature_flags"] as? [Any] ?? []
            expect(activeFlags.contains { $0 as? String == "bool-value" }) == true
            expect(activeFlags.contains { $0 as? String == "disabled-flag" }) == false

            expect(event.properties["$feature/bool-value"] as? Bool) == true
            expect(event.properties["$feature/disabled-flag"] as? Bool) == false

            sut.reset()
            sut.close()
        }

        it("sanitize properties") {
            let sut = self.getSut(flushAt: 1)

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

            let events = getBatchedEvents(server)

            expect(events.count) == 1
            let event = events.first!

            expect(event.properties["test1"]) == nil
            expect(event.properties["test2"]) == nil
            expect(event.properties["test3"]) == nil
            expect(event.properties["test4"]) == nil
            expect(event.properties["test5"]) == nil
            expect(event.properties["arrayIsOk"]) != nil
            expect(event.properties["dictIsOk"]) != nil
            expect(event.properties["boolIsOk"]) != nil

            sut.reset()
            sut.close()
        }

        it("sets sessionId on app start") {
            let sut = self.getSut(captureApplicationLifecycleEvents: true)

            sut.handleAppDidBecomeActive()

            let events = getBatchedEvents(server)

            expect(events.count) == 1

            let event = events.first!
            expect(event.properties["$session_id"]).toNot(beNil())

            sut.reset()
            sut.close()
        }

        it("uses the same sessionId for all events in a session") {
            let sut = self.getSut(flushAt: 3)
            let mockNow = MockDate()
            now = { mockNow.date }

            sut.capture("event1")

            mockNow.date.addTimeInterval(10)

            sut.capture("event2")

            mockNow.date.addTimeInterval(10)

            sut.capture("event3")

            let events = getBatchedEvents(server)

            expect(events.count) == 3

            let sessionId = events[0].properties["$session_id"] as? String
            expect(sessionId).toNot(beNil())
            expect(events[1].properties["$session_id"] as? String).to(equal(sessionId))
            expect(events[2].properties["$session_id"] as? String).to(equal(sessionId))

            sut.reset()
            sut.close()
        }

        it("clears sessionId for background events after 30 mins in background") {
            let sut = self.getSut(captureApplicationLifecycleEvents: true, flushAt: 2)
            let mockNow = MockDate()
            now = { mockNow.date }

            sut.handleAppDidEnterBackground() // Background "timer": 0 mins

            mockNow.date.addTimeInterval(60 * 30 + 1) // Background "timer": 30 mins 1 second

            sut.capture("event captured while in background")

            let events = getBatchedEvents(server)
            expect(events.count) == 2

            expect(events[0].properties["$session_id"] as? String).toNot(beNil())
            expect(events[1].properties["$session_id"] as? String).to(beNil())

            sut.reset()
            sut.close()
        }

        it("reset sessionId after reset") {
            let sut = self.getSut(captureApplicationLifecycleEvents: true, flushAt: 1)
            let mockNow = MockDate()
            now = { mockNow.date }

            sut.capture("event captured with session")

            var events = getBatchedEvents(server)
            expect(events.count) == 1

            let currentSessionId = events[0].properties["$session_id"] as? String
            expect(currentSessionId).toNot(beNil())

            sut.reset()

            server.stop()
            server = nil
            server = MockPostHogServer()
            server.start()

            sut.capture("event captured w/o session")

            events = getBatchedEvents(server)
            expect(events.count) == 1

            let newSessionId = events[0].properties["$session_id"] as? String
            expect(newSessionId).toNot(beNil())

            expect(currentSessionId).toNot(equal(newSessionId))

            sut.reset()
            sut.close()
        }

        it("reset deletes posthog files but not other folders") {
            let appFolder = applicationSupportDirectoryURL()
            expect(FileManager.default.fileExists(atPath: appFolder.path)) == false

            let sut = self.getSut()

            sut.reset()
            sut.close()

            expect(FileManager.default.fileExists(atPath: appFolder.path)) == true
        }

        it("client sanitize properties") {
            let sanitizer = ExampleSanitizer()
            let sut = self.getSut(propertiesSanitizer: sanitizer)

            let props: [String: Any] = ["empty": ""]

            sut.capture("event", properties: props)

            let events = getBatchedEvents(server)

            expect(events[0].properties["empty"] as? String).to(beNil())

            sut.reset()
            sut.close()
        }

        it("reset reloads flags as anon user") {
            let sut = self.getSut()

            sut.reset()

            waitDecideRequest(server)
            expect(sut.isFeatureEnabled("bool-value")) == true

            sut.close()
        }

        it("captures an event with a custom timestamp") {
            let sut = self.getSut()
            let eventDate = Date().addingTimeInterval(-60 * 30)

            sut.capture("test event",
                        properties: ["foo": "bar"],
                        userProperties: ["userProp": "value"],
                        userPropertiesSetOnce: ["userPropOnce": "value"],
                        groups: ["groupProp": "value"],
                        timestamp: eventDate)

            let events = getBatchedEvents(server)

            expect(events.count) == 1

            let event = events.first!
            expect(event.event) == "test event"

            expect(event.properties["foo"] as? String) == "bar"

            let set = event.properties["$set"] as? [String: Any] ?? [:]
            expect(set["userProp"] as? String) == "value"

            let setOnce = event.properties["$set_once"] as? [String: Any] ?? [:]
            expect(setOnce["userPropOnce"] as? String) == "value"

            let groupProps = event.properties["$groups"] as? [String: String] ?? [:]
            expect(groupProps["groupProp"]) == "value"

            expect(toISO8601String(event.timestamp)).to(equal(toISO8601String(eventDate)))

            sut.reset()
            sut.close()
        }

        it("captures $feature_flag_called when getFeatureFlag is called") {
            let sut = self.getSut(
                sendFeatureFlagEvent: true,
                flushAt: 1
            )

            _ = sut.getFeatureFlag("some_key")

            let event = getBatchedEvents(server)
            expect(event.first!.event).to(equal("$feature_flag_called"))
        }

        it("does not capture $feature_flag_called when getFeatureFlag is called twice") {
            let sut = self.getSut(
                sendFeatureFlagEvent: true,
                flushAt: 2
            )

            _ = sut.getFeatureFlag("some_key")
            _ = sut.getFeatureFlag("some_key")
            sut.capture("force_batch_flush")

            let event = getBatchedEvents(server)
            expect(event.count).to(equal(2))
            expect(event[0].event).to(equal("$feature_flag_called"))
            expect(event[1].event).to(equal("force_batch_flush"))
        }

        it("captures $feature_flag_called when getFeatureFlag called twice after reloading flags") {
            let sut = self.getSut(
                sendFeatureFlagEvent: true,
                flushAt: 2
            )

            _ = sut.getFeatureFlag("some_key")

            sut.reloadFeatureFlags {
                _ = sut.getFeatureFlag("some_key")
            }

            let event = getBatchedEvents(server)
            expect(event.count).to(equal(2))
            expect(event[0].event).to(equal("$feature_flag_called"))
            expect(event[1].event).to(equal("$feature_flag_called"))
        }

        #if os(iOS)
            context("autocapture") {
                it("isAutocaptureActive() should be false if disabled by config") {
                    let config = PostHogConfig(apiKey: testAPIKey)
                    config.captureElementInteractions = false
                    let sut = PostHogSDK.with(config)

                    expect(sut.isAutocaptureActive()).to(beFalse())
                }

                it("isAutocaptureActive() should be false if SDK is not enabled") {
                    let config = PostHogConfig(apiKey: testAPIKey)
                    config.captureElementInteractions = true
                    let sut = PostHogSDK.with(config)
                    sut.close()
                    expect(sut.isAutocaptureActive()).to(beFalse())
                }
            }
        #endif
    }
}
