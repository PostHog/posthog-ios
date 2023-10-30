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
    override func spec() {
        var harness: TestPostHog!
        var posthog: PostHogSDK!

        beforeEach {
            harness = TestPostHog()
            posthog = harness.posthog
            posthog.reset()
        }
        afterEach {
            harness.stop()
        }

//        it(".capture") {
//            posthog.capture("test event")
//            posthog.capture("test event2", properties: ["foo": "bar"])
//
//            let events = harness.getBatchedEvents()
//
//            expect(events.count) == 2
//
//            expect(events[0].event) == "test event"
//            expect(Set(events[0].properties.keys)) == ["$device_id", "$os_name", "$app_version", "$lib_version", "$screen_height", "$app_name", "$timezone", "$screen_width", "$app_namespace", "$network_cellular", "$os_version", "$device_name", "$network_wifi", "distinct_id", "$lib", "$session_id", "$locale", "$app_build", "$device_type", "$groups"]
//
//            expect(events[1].event) == "test event2"
//            expect(events[1].properties["foo"] as? String) == "bar"
//        }
//
//        it(".identify") {
//            let anonymousId = posthog.getAnonymousId()
//            posthog.identify("testDistinctId1", userProperties: [
//                "firstName": "Peter",
//            ])
//
//            let event = harness.getBatchedEvents()[0]
//            expect(event.event) == "$identify"
//            expect(event.properties["distinct_id"] as? String) == "testDistinctId1"
//            expect(event.properties["$anon_distinct_id"] as? String) == anonymousId
//            expect((event.properties["$set"] as? [String: String])?["firstName"] as? String) == "Peter"
//        }
//
//        it(".alias") {
//            posthog.alias("persistentDistinctId")
//
//            let event = harness.getBatchedEvents()[0]
//            expect(event.event) == "$create_alias"
//            expect(event.properties["alias"] as? String) == "persistentDistinctId"
//        }
//
//        it(".screen") {
//            posthog.screen("Home", properties: [
//                "referrer": "Google",
//            ])
//
//            let event = harness.getBatchedEvents()[0]
//            expect(event.event) == "$screen"
//            expect(event.properties["$screen_name"] as? String) == "Home"
//            expect(event.properties["referrer"] as? String) == "Google"
//        }
//
//        it(".group") {
//            posthog.group(type: "some-type", key: "some-key", groupProperties: [
//                "name": "some-company-name",
//            ])
//
//            let groupEvent = harness.getBatchedEvents()[0]
//            expect(groupEvent.event) == "$groupidentify"
//            expect(groupEvent.properties["$group_type"] as? String?) == "some-type"
//            expect(groupEvent.properties["$group_key"] as? String?) == "some-key"
//            expect((groupEvent.properties["$group_set"] as? [String: String])?["name"] as? String) == "some-company-name"
//
//            posthog.capture("test-event")
//            let event = harness.getBatchedEvents()[0]
//
//            // Verify that subsequent call has the groups
//            let groups = event.properties["$groups"] as? [String: String]
//            expect(groups?["some-type"]) == "some-key"
//        }
    }
}
