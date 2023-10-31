//
//  CaptureTests.swift
//  PostHogTests
//
//  Created by Ben White on 21.03.23.
//

import Foundation
import Nimble
import Quick

@testable import PostHog

// As E2E as possible tests
class CaptureTest: QuickSpec {
    func getSut() -> PostHogSDK {
        let config = PostHogConfig(apiKey: "123", host: "http://localhost:9001")
        config.flushAt = 1
        config.preloadFeatureFlags = false
        config.sendFeatureFlagEvent = false
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

        it(".capture") {
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

        it(".identify") {
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

        it(".alias") {
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

        it(".screen") {
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

        it(".group") {
            let sut = self.getSut()

            sut.group(type: "some-type", key: "some-key", groupProperties: [
                "name": "some-company-name",
            ])

            let groupEvent = getBatchedEvents(server)[0]
            expect(groupEvent.event) == "$groupidentify"
            expect(groupEvent.properties["$group_type"] as? String?) == "some-type"
            expect(groupEvent.properties["$group_key"] as? String?) == "some-key"
            expect((groupEvent.properties["$group_set"] as? [String: String])?["name"] as? String) == "some-company-name"
        }
    }
}
