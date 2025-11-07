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
                personProfiles: PostHogPersonProfiles = .identifiedOnly,
                setDefaultPersonProperties: Bool = true,
                beforeSend: [BeforeSendBlock]? = nil) -> PostHogSDK
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
        config.setDefaultPersonProperties = setDefaultPersonProperties

        if let beforeSend = beforeSend {
            config.setBeforeSend(beforeSend)
        }

        let storage = PostHogStorage(config)
        storage.reset()

        return PostHogSDK.with(config)
    }

    func getBeforeSendEventsConfig() -> [BeforeSendTestEventContext] {
        [
            .init(
                triggerClosure: { $0.capture("test_event") },
                targetKey: "test_event",
                testName: "capture"
            ),
            .init(
                triggerClosure: { $0.screen("screen_name") },
                targetKey: "$screen",
                testName: "screen"
            ),
            .init(
                triggerClosure: { $0.autocapture(eventType: "test_type", elementsChain: "chain", properties: [:]) },
                targetKey: "$autocapture",
                testName: "autocapture"
            ),
            .init(
                triggerClosure: { $0.identify("user_id") },
                targetKey: "$identify",
                testName: "identify"
            ),
            .init(
                triggerClosure: { $0.group(type: "test_type", key: "test_key") },
                targetKey: "$groupidentify",
                testName: "group"
            ),
            .init(
                triggerClosure: { $0.alias("test_alias") },
                targetKey: "$create_alias",
                testName: "alias"
            ),
            .init(
                triggerClosure: { _ = $0.getFeatureFlag("key") },
                targetKey: "$feature_flag_called",
                testName: "get feature flag"
            ),
        ]
    }

    override func spec() {
        var server: MockPostHogServer!
        let mockAppLifecycle = MockApplicationLifecyclePublisher()

        func deleteDefaults() {
            let userDefaults = UserDefaults.standard
            userDefaults.removeObject(forKey: "PHGVersionKey")
            userDefaults.removeObject(forKey: "PHGBuildKeyV2")
            userDefaults.synchronize()

            deleteSafely(applicationSupportDirectoryURL())
        }

        beforeEach {
            PostHogAppLifeCycleIntegration.clearInstalls()

            deleteDefaults()
            server = MockPostHogServer(version: 4)
            server.start()

            DI.main.appLifecyclePublisher = mockAppLifecycle
        }
        afterEach {
            now = { Date() }
            server.stop()
            server = nil
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

        it("removes all integrations on opt-out") {
            let sut = self.getSut(
                captureApplicationLifecycleEvents: true,
                optOut: false
            )

            expect(sut.getAppLifeCycleIntegration()).notTo(beNil())

            sut.optOut()

            expect(sut.getAppLifeCycleIntegration()).to(beNil())

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

        it("loads feature flags automatically") {
            let sut = self.getSut(preloadFeatureFlags: true)

            waitFlagsRequest(server)
            expect(sut.isFeatureEnabled("bool-value")) == true

            sut.reset()
            sut.close()
        }

        it("send feature flag event for isFeatureEnabled when enabled") {
            let sut = self.getSut(preloadFeatureFlags: true, sendFeatureFlagEvent: true)

            waitFlagsRequest(server)
            expect(sut.isFeatureEnabled("bool-value")) == true

            let events = getBatchedEvents(server)

            expect(events.count) == 1

            let event = events.first!
            expect(event.event) == "$feature_flag_called"
            expect(event.properties["$feature_flag"] as? String) == "bool-value"
            expect(event.properties["$feature_flag_response"] as? Bool) == true
            expect(event.properties["$feature_flag_request_id"] as? String) == "0f801b5b-0776-42ca-b0f7-8375c95730bf"
            expect(event.properties["$feature_flag_id"] as? Int) == 2
            expect(event.properties["$feature_flag_version"] as? Int) == 23
            expect(event.properties["$feature_flag_reason"] as? String) == "Matched condition set 3"

            sut.reset()
            sut.close()
        }

        it("send feature flag event with variant response for isFeatureEnabled when enabled") {
            let sut = self.getSut(preloadFeatureFlags: true, sendFeatureFlagEvent: true)

            waitFlagsRequest(server)
            expect(sut.isFeatureEnabled("string-value")) == true

            let events = getBatchedEvents(server)

            expect(events.count) == 1

            let event = events.first!
            expect(event.event) == "$feature_flag_called"
            expect(event.properties["$feature_flag"] as? String) == "string-value"
            expect(event.properties["$feature_flag_response"] as? String) == "test"
            expect(event.properties["$feature_flag_request_id"] as? String) == "0f801b5b-0776-42ca-b0f7-8375c95730bf"
            expect(event.properties["$feature_flag_id"] as? Int) == 3
            expect(event.properties["$feature_flag_version"] as? Int) == 1
            expect(event.properties["$feature_flag_reason"] as? String) == "Matched condition set 1"

            sut.reset()
            sut.close()
        }

        it("send feature flag event for getFeatureFlag when enabled") {
            let sut = self.getSut(preloadFeatureFlags: true, sendFeatureFlagEvent: true)

            waitFlagsRequest(server)
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

        it("reloadFeatureFlags adds groups if any") {
            let sut = self.getSut()
            // group reloads flags when there are new groups
            // but in this case we want to reload manually and assert the response
            sut.remoteConfig?.canReloadFlagsForTesting = false
            sut.group(type: "some-type", key: "some-key", groupProperties: [
                "name": "some-company-name",
            ])
            sut.remoteConfig?.canReloadFlagsForTesting = true

            let events = getBatchedEvents(server)

            expect(events.count) == 1

            sut.reloadFeatureFlags()

            let requests = getFlagsRequest(server)

            expect(requests.count) == 1
            let request = requests.first

            let groups = request!["groups"] as? [String: String] ?? [:]
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
            waitFlagsRequest(server)

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
            let sut = self.getSut(captureApplicationLifecycleEvents: true, flushAt: 1)

            mockAppLifecycle.simulateAppDidFinishLaunching()

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
            let sut = self.getSut(captureApplicationLifecycleEvents: false, flushAt: 2)
            let mockNow = MockDate()
            now = { mockNow.date }

            sut.capture("event captured in foreground")

            mockAppLifecycle.simulateAppDidEnterBackground()

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
            let sut = self.getSut(captureApplicationLifecycleEvents: false, flushAt: 1)
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

            waitFlagsRequest(server)
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

        describe("beforeSend hook") {
            let eventTriggers = getBeforeSendEventsConfig()
            let testOtherEventKey = "other_event"
            var sut: PostHogSDK!

            afterEach {
                sut?.reset()
                sut?.close()
            }

            for eventTrigger in eventTriggers {
                context("returns nil") {
                    beforeEach {
                        sut = self.getSut(
                            sendFeatureFlagEvent: true,
                            flushAt: 1,
                            beforeSend: [{
                                $0.event == eventTrigger.targetKey ? nil : $0
                            }]
                        )
                    }

                    describe(eventTrigger.testName) {
                        it("skips the event") {
                            sut.capture(testOtherEventKey)
                            eventTrigger.triggerClosure(sut)

                            let events = getBatchedEvents(server)
                            let eventNames = events.map(\.event)

                            expect(events.count).to(equal(1))
                            expect(eventNames).notTo(contain(eventTrigger.targetKey))
                        }

                        it("preserves other events") {
                            sut.capture(testOtherEventKey)
                            eventTrigger.triggerClosure(sut)

                            let event = getBatchedEvents(server)

                            expect(event.count).to(equal(1))
                            expect(event[0].event).to(equal(testOtherEventKey))
                        }
                    }
                }

                context("event is updated") {
                    let testUpdatedEventKey = "updated_event"

                    beforeEach {
                        sut = self.getSut(
                            sendFeatureFlagEvent: true,
                            flushAt: 2,
                            beforeSend: [{
                                if $0.event == eventTrigger.targetKey {
                                    $0.event = testUpdatedEventKey
                                }

                                return $0
                            }]
                        )
                    }

                    describe(eventTrigger.testName) {
                        it("updates the event") {
                            sut.capture(testOtherEventKey)
                            eventTrigger.triggerClosure(sut)

                            let events = getBatchedEvents(server)
                            let eventNames = events.map(\.event)

                            expect(events.count).to(equal(2))
                            expect(eventNames).to(contain(testUpdatedEventKey))
                        }

                        it("preserves all events") {
                            sut.capture(testOtherEventKey)
                            eventTrigger.triggerClosure(sut)

                            let event = getBatchedEvents(server)

                            expect(event.count).to(equal(2))
                            expect(event[0].event).to(equal(testOtherEventKey))
                        }
                    }
                }

                context("default hook") {
                    beforeEach {
                        sut = self.getSut(
                            sendFeatureFlagEvent: true,
                            flushAt: 2
                        )
                    }

                    describe(eventTrigger.testName) {
                        it("keeps the events intact") {
                            sut.capture(testOtherEventKey)
                            eventTrigger.triggerClosure(sut)

                            let events = getBatchedEvents(server)
                            let eventNames = events.map(\.event)

                            expect(events.count).to(equal(2))
                            expect(eventNames[0]).to(equal(testOtherEventKey))
                            expect(eventNames[1]).to(equal(eventTrigger.targetKey))
                        }
                    }
                }
            }

            it("skip updated to $session event") {
                let testKey = "test_key"
                sut = self.getSut(
                    sendFeatureFlagEvent: true,
                    flushAt: 1,
                    beforeSend: [{
                        if $0.event == testKey {
                            $0.event = "$snapshot"
                        }
                        return $0
                    }]
                )

                sut.capture(testKey)
                sut.capture("other_test")

                let events = getBatchedEvents(server)
                expect(events.count).to(equal(1))
                expect(events[0].event).to(equal("other_test"))
            }

            describe("array edge cases") {
                it("properly handles empty beforeSend array") {
                    sut = self.getSut(
                        sendFeatureFlagEvent: true,
                        flushAt: 2,
                        beforeSend: []
                    )

                    let expectedEvents = [
                        "first_event",
                        "second_event",
                    ]

                    for event in expectedEvents {
                        sut.capture(event)
                    }

                    let events = getBatchedEvents(server)
                    expect(events.count).to(equal(expectedEvents.count))
                    expect(events.map(\.event)).to(equal(expectedEvents))
                }

                it("supports trailing closure syntax for single block") {
                    let sut = self.getSut(
                        sendFeatureFlagEvent: true,
                        flushAt: 1
                    )

                    sut.config.setBeforeSend { $0.event == "first_event" ? nil : $0 }

                    sut.capture("first_event")
                    sut.capture("second_event")

                    let events = getBatchedEvents(server)
                    expect(events.count).to(equal(1))
                    expect(events[0].event).to(equal("second_event"))
                }

                it("supports multiple beforeSend blocks") {
                    let sut = self.getSut(
                        sendFeatureFlagEvent: true,
                        flushAt: 2,
                        beforeSend: [
                            { $0.event == "first_event" ? nil : $0 },
                            { $0.event = "modified_event"
                                return $0 },
                            { $0.event == "second_event" ? nil : $0 },
                        ]
                    )

                    sut.capture("first_event")
                    sut.capture("second_event")
                    sut.capture("third_event")

                    // first event is skipped by the first block
                    // second event is modified by the second block and not skipped by the third block(because it became "modified_event")
                    // third event is modified by the second block
                    let expectedEvents = [
                        "modified_event",
                        "modified_event",
                    ]

                    let events = getBatchedEvents(server)
                    expect(events.count).to(equal(expectedEvents.count))
                    expect(events.map(\.event)).to(equal(expectedEvents))
                }
            }
        }

        context("automatic person properties") {
            it("sets default person properties on SDK setup when enabled") {
                let sut = self.getSut(preloadFeatureFlags: true)

                let requests = getFlagsRequest(server)
                expect(requests.count).to(beGreaterThan(0))

                guard let lastRequest = requests.last else {
                    fail("No flags request found")
                    return
                }

                guard let personProperties = lastRequest["person_properties"] as? [String: Any] else {
                    fail("Person properties not found in request")
                    return
                }

                // Verify expected default properties are set
                expect(personProperties["$app_version"]).toNot(beNil())
                expect(personProperties["$app_build"]).toNot(beNil())
                expect(personProperties["$app_namespace"]).toNot(beNil())
                expect(personProperties["$os_name"]).toNot(beNil())
                expect(personProperties["$os_version"]).toNot(beNil())
                expect(personProperties["$device_type"]).toNot(beNil())
                expect(personProperties["$lib"]).toNot(beNil())
                expect(personProperties["$lib_version"]).toNot(beNil())
            }

            it("does not set default person properties when disabled") {
                let sut = self.getSut(setDefaultPersonProperties: false)

                // Manually trigger a flag request since no automatic one will happen
                sut.reloadFeatureFlags()

                let requests = getFlagsRequest(server)
                expect(requests.count).to(beGreaterThan(0))

                guard let lastRequest = requests.last else {
                    fail("No flags request found")
                    return
                }

                // person_properties should be nil when default properties are disabled
                expect(lastRequest["person_properties"]).to(beNil())
            }
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

struct BeforeSendTestEventContext {
    let triggerClosure: (PostHogSDK) -> Void
    let targetKey: String
    let testName: String
}
