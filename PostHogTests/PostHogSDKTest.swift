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
                sendFeatureFlagEvent: Bool = false) -> PostHogSDK
    {
        let config = PostHogConfig(apiKey: "123", host: "http://localhost:9001")
        config.flushAt = 1
        config.preloadFeatureFlags = preloadFeatureFlags
        config.sendFeatureFlagEvent = sendFeatureFlagEvent
        config.disableReachabilityForTesting = true
        config.disableQueueTimerForTesting = true
        return PostHogSDK.with(config)
    }

    override func spec() {
        var server: MockPostHogServer!

        beforeEach {
            server = MockPostHogServer()
            server.start()
        }
        afterEach {
            server.stop()
            server = nil
        }

        it("captures the capture event") {
            let sut = self.getSut()

            sut.capture("test event",
                        properties: ["foo": "bar"],
                        userProperties: ["userProp": "value"],
                        userPropertiesSetOnce: ["userPropOnce": "value"],
                        groupProperties: ["groupProp": "value"])

            let events = getBatchedEvents(server)

            expect(events.count) == 1

            let event = events.first!
            expect(event.event) == "test event"

            expect(event.properties["foo"] as? String) == "bar"

            let set = event.properties["$set"] as? [String: Any] ?? [:]
            expect(set["userProp"] as? String) == "value"

            let setOnce = event.properties["$set_once"] as? [String: Any] ?? [:]
            expect(setOnce["userPropOnce"] as? String) == "value"

            let groupProps = event.properties["$groups"] as? [String: Any] ?? [:]
            expect(groupProps["groupProp"] as? String) == "value"

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

            let set = event.properties["$set"] as? [String: Any] ?? [:]
            expect(set["userProp"] as? String) == "value"

            let setOnce = event.properties["$set_once"] as? [String: Any] ?? [:]
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
            expect((groupEvent.properties["$group_set"] as? [String: String])?["name"] as? String) == "some-company-name"

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

        it("send feature flag event when enabled") {
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
    }
}
