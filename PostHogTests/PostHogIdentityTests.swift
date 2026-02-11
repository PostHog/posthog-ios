//
//  PostHogIdentityTests.swift
//  PostHog
//
//  Created by Ioannis Josephides on 14/04/2025.
//

import Foundation
@testable import PostHog
import Testing

@Suite("Identity tests", .serialized)
class PostHogIdentityTests {
    let server: MockPostHogServer
    let storageTracker = TestStorageTracker()

    var cleanupJobs: [() -> Void]

    func getSut(
        apiKey: String = uniqueApiKey(),
        reuseAnonymousId: Bool = false,
        flushAt: Int = 1
    ) -> PostHogSDK {
        let config = PostHogConfig(apiKey: apiKey, host: "http://localhost:9001")
        storageTracker.track(config)
        config.captureApplicationLifecycleEvents = false
        config.reuseAnonymousId = reuseAnonymousId
        config.flushAt = flushAt
        config.maxBatchSize = flushAt
        let sut = PostHogSDK.with(config)
        cleanupJobs.append {
            sut.reset()
            sut.close()
        }
        return sut
    }

    init() throws {
        server = MockPostHogServer()
        server.start()
        cleanupJobs = []
    }

    deinit {
        server.reset()
        for cleanup in cleanupJobs {
            cleanup()
        }
        storageTracker.cleanup()
    }

    @Test("does not clear anonymousId on reset()")
    func doesNotClearAnonymousIdOnReset() async throws {
        let sut = getSut(reuseAnonymousId: true)
        let oldAnonId = sut.getAnonymousId()
        sut.reset()
        let newAnonId = sut.getAnonymousId()
        #expect(oldAnonId == newAnonId)
    }

    @Test("does not clear anonymousId on close()")
    func doesNotClearAnonymousIdOnClose() async throws {
        let sharedKey = uniqueApiKey()
        var sut = getSut(apiKey: sharedKey, reuseAnonymousId: true)

        let oldAnonId = sut.getAnonymousId()
        sut.close()

        sut = getSut(apiKey: sharedKey, reuseAnonymousId: true)
        let newAnonId = sut.getAnonymousId()

        #expect(oldAnonId == newAnonId)
    }

    @Test("anonymousId is not overwritten on re-identify when reuseAnonymousId is true")
    func anonymousIdIsNotOverwrittenOnReIdentifyWhenReuseAnonymousIdIsTrue() async throws {
        let sut = getSut(reuseAnonymousId: true)
        let oldAnonId = sut.getAnonymousId()
        sut.identify("my_user_id")
        #expect(sut.getDistinctId() == "my_user_id")
        sut.identify("my_user_id2")
        #expect(sut.getDistinctId() == "my_user_id")
        sut.reset()
        let newAnonId = sut.getAnonymousId()
        #expect(oldAnonId == newAnonId)
        #expect(oldAnonId == sut.getDistinctId())
    }

    @Test("anonymousId is retained across series of identify() and reset() reuseAnonymousId is true")
    func anonymousIdIsRetailainedAcrossSeriesOfIdentifyAndResetReuseAnonymousIdIsTrue() async throws {
        let sharedKey = uniqueApiKey()
        var sut = getSut(apiKey: sharedKey, reuseAnonymousId: true)
        let oldAnonId = sut.getAnonymousId()
        sut.identify("my_user_id")
        #expect(sut.getDistinctId() == "my_user_id")
        sut.reset()
        #expect(oldAnonId == sut.getAnonymousId())

        sut = getSut(apiKey: sharedKey, reuseAnonymousId: true)
        sut.identify("my_user_id2")
        #expect(sut.getDistinctId() == "my_user_id2")
        sut.reset()
        #expect(oldAnonId == sut.getDistinctId())
    }

    @Test("skip $anon_distinct_id in $identify event when flag reuseAnonymousId is true")
    func skipAnonDistinctIdInIdentifyEventWhenFlagReuseAnonymousIdIsTrue() async throws {
        let sut = getSut(reuseAnonymousId: true)
        sut.identify("my_user_id")

        let events = try await getServerEvents(server)

        #expect(events.count == 1)
        #expect(events[0].properties["distinct_id"] as? String == "my_user_id")
        #expect(events[0].properties["$anon_distinct_id"] == nil)
    }

    @Test("identify sets distinct and anon Ids")
    func identifySetsDistinctAndAnonIds() async throws {
        let sut = getSut()
        let distId = sut.getDistinctId()

        sut.identify("newDistinctId")

        #expect(sut.getDistinctId() == "newDistinctId")
        #expect(sut.getAnonymousId() == distId)
    }

    @Test("captures the capture event with a custom distinctId")
    func capturesCaptureEventWithCustomDistinctId() async throws {
        let sut = getSut()

        sut.capture("event",
                    distinctId: "the_custom_distinct_id",
                    properties: ["foo": "bar"],
                    userProperties: ["userProp": "value"],
                    userPropertiesSetOnce: ["userPropOnce": "value"],
                    groups: ["groupProp": "value"])

        let events = try await getServerEvents(server)

        #expect(events.count == 1)
        #expect(events.first!.distinctId == "the_custom_distinct_id")
    }

    @Test("captures an identify event")
    func capturesIdentifyEvent() async throws {
        let sut = getSut()

        sut.identify("distinctId",
                     userProperties: ["userProp": "value"],
                     userPropertiesSetOnce: ["userPropOnce": "value"])

        let events = try await getServerEvents(server)

        #expect(events.count == 1)

        let event = events.first!
        #expect(event.event == "$identify")

        #expect(event.distinctId == "distinctId")
        let anonId = sut.getAnonymousId()
        #expect(event.properties["$anon_distinct_id"] as? String == anonId)
        #expect(event.properties["$is_identified"] as? Bool == true)

        let set = event.properties["$set"] as? [String: Any] ?? [:]
        #expect(set["userProp"] as? String == "value")

        let setOnce = event.properties["$set_once"] as? [String: Any] ?? [:]
        #expect(setOnce["userPropOnce"] as? String == "value")
    }

    @Test("captures an event with is identified false")
    func capturesEventWithIsIdentifiedFalse() async throws {
        let sut = getSut()

        sut.capture("test",
                    userProperties: ["userProp": "value"],
                    userPropertiesSetOnce: ["userPropOnce": "value"])

        let events = try await getServerEvents(server)

        #expect(events.count == 1)

        let event = events.first!

        #expect(event.properties["$is_identified"] as? Bool == false)
    }

    @Test("does not capture identify event if already identified")
    func doesNotCaptureIdentifyEventIfAlreadyIdentified() async throws {
        let sut = getSut(
            flushAt: 2
        )

        sut.identify("distinctId",
                     userProperties: ["userProp": "value"],
                     userPropertiesSetOnce: ["userPropOnce": "value"])

        sut.identify("distinctId")
        sut.capture("satisfy_queue")

        let events = try await getServerEvents(server)

        #expect(events.count == 2)

        #expect(events[0].event == "$identify")
        #expect(events[1].event == "satisfy_queue")

        #expect(events[0].distinctId == "distinctId")
        let anonId = sut.getAnonymousId()
        #expect(events[0].properties["$anon_distinct_id"] as? String == anonId)
        #expect(events[0].properties["$is_identified"] as? Bool == true)

        let set = events[0].properties["$set"] as? [String: Any] ?? [:]
        #expect(set["userProp"] as? String == "value")

        let setOnce = events[0].properties["$set_once"] as? [String: Any] ?? [:]
        #expect(setOnce["userPropOnce"] as? String == "value")
    }

    @Test("updates user props if already identified but user properties are set")
    func updatesUserPropsWhenAlreadyIdentified() async throws {
        let sut = getSut(
            flushAt: 2
        )

        sut.identify("distinctId",
                     userProperties: ["userProp": "value"],
                     userPropertiesSetOnce: ["userPropOnce": "value"])

        sut.identify("distinctId",
                     userProperties: ["userProp2": "value2"],
                     userPropertiesSetOnce: ["userPropOnce2": "value2"])

        let events = try await getServerEvents(server)

        #expect(events.count == 2)

        #expect(events[0].event == "$identify")
        #expect(events[1].event == "$set")

        #expect(events[0].distinctId == "distinctId")
        #expect(events[1].distinctId == events[0].distinctId)

        let anonId = sut.getAnonymousId()
        #expect(events[0].properties["$anon_distinct_id"] as? String == anonId)
        #expect(events[0].properties["$is_identified"] as? Bool == true)

        let set0 = events[0].properties["$set"] as? [String: Any] ?? [:]
        #expect(set0["userProp"] as? String == "value")

        let set1 = events[1].properties["$set"] as? [String: Any] ?? [:]
        #expect(set1["userProp2"] as? String == "value2")

        let setOnce0 = events[0].properties["$set_once"] as? [String: Any] ?? [:]
        #expect(setOnce0["userPropOnce"] as? String == "value")

        let setOnce1 = events[1].properties["$set_once"] as? [String: Any] ?? [:]
        #expect(setOnce1["userPropOnce2"] as? String == "value2")
    }

    @Test("does not capture user props for another distinctId even if user properties are set")
    func doesNotCaptureUserPropsForDifferentDistinctId() async throws {
        let sut = getSut(
            flushAt: 2
        )

        sut.identify("distinctId",
                     userProperties: ["userProp": "value"],
                     userPropertiesSetOnce: ["userPropOnce": "value"])

        sut.identify("distinctId2",
                     userProperties: ["userProp2": "value2"],
                     userPropertiesSetOnce: ["userPropOnce2": "value2"])

        sut.capture("satisfy_queue")

        let events = try await getServerEvents(server)

        #expect(events.count == 2)

        #expect(events[0].event == "$identify")
        #expect(events[1].event == "satisfy_queue")

        #expect(events[0].distinctId == "distinctId")
        let anonId = sut.getAnonymousId()
        #expect(events[0].properties["$anon_distinct_id"] as? String == anonId)
        #expect(events[0].properties["$is_identified"] as? Bool == true)

        let set = events[0].properties["$set"] as? [String: Any] ?? [:]
        #expect(set["userProp"] as? String == "value")

        let setOnce = events[0].properties["$set_once"] as? [String: Any] ?? [:]
        #expect(setOnce["userPropOnce"] as? String == "value")
    }

    @Test("captures an alias event")
    func capturesAliasEvent() async throws {
        let sut = getSut()

        sut.alias("theAlias")

        let events = getBatchedEvents(server)

        #expect(events.count == 1)

        let event = events.first!
        #expect(event.event == "$create_alias")
        #expect(event.properties["alias"] as? String == "theAlias")
    }

    @Test("setups default IDs")
    func setupsDefaultIds() async throws {
        let sut = getSut()

        #expect(sut.getAnonymousId() != "")
        #expect(sut.getDistinctId() == sut.getAnonymousId())
    }

    // MARK: - setPersonProperties tests

    @Test("setPersonProperties sends $set event with properties")
    func setPersonPropertiesSendsSetEvent() async throws {
        let sut = getSut()

        sut.setPersonProperties(
            userPropertiesToSet: ["name": "John", "age": 30],
            userPropertiesToSetOnce: ["created_at": "2024-01-01"]
        )

        let events = try await getServerEvents(server)

        #expect(events.count == 1)

        let event = events.first!
        #expect(event.event == "$set")

        let set = event.properties["$set"] as? [String: Any] ?? [:]
        #expect(set["name"] as? String == "John")
        #expect(set["age"] as? Int == 30)

        let setOnce = event.properties["$set_once"] as? [String: Any] ?? [:]
        #expect(setOnce["created_at"] as? String == "2024-01-01")
    }

    @Test("setPersonProperties deduplicates identical calls")
    func setPersonPropertiesDeduplicatesIdenticalCalls() async throws {
        let sut = getSut(flushAt: 2)

        // Call twice with same properties
        sut.setPersonProperties(userPropertiesToSet: ["name": "John"])
        sut.setPersonProperties(userPropertiesToSet: ["name": "John"])

        // Add a different event to trigger flush
        sut.capture("test_event")

        let events = try await getServerEvents(server)

        // Should only have 1 $set event + 1 test_event
        #expect(events.count == 2)
        #expect(events[0].event == "$set")
        #expect(events[1].event == "test_event")
    }

    @Test("setPersonProperties allows different property values")
    func setPersonPropertiesAllowsDifferentPropertyValues() async throws {
        let sut = getSut(flushAt: 2)

        sut.setPersonProperties(userPropertiesToSet: ["name": "John"])
        sut.setPersonProperties(userPropertiesToSet: ["name": "Jane"])

        let events = try await getServerEvents(server)

        #expect(events.count == 2)
        #expect(events[0].event == "$set")
        #expect(events[1].event == "$set")

        let set0 = events[0].properties["$set"] as? [String: Any] ?? [:]
        #expect(set0["name"] as? String == "John")

        let set1 = events[1].properties["$set"] as? [String: Any] ?? [:]
        #expect(set1["name"] as? String == "Jane")
    }

    @Test("setPersonProperties with only setOnce properties")
    func setPersonPropertiesWithOnlySetOnceProperties() async throws {
        let sut = getSut()

        sut.setPersonProperties(
            userPropertiesToSet: nil,
            userPropertiesToSetOnce: ["first_seen": "2024-01-01"]
        )

        let events = try await getServerEvents(server)

        #expect(events.count == 1)

        let event = events.first!
        #expect(event.event == "$set")

        let setOnce = event.properties["$set_once"] as? [String: Any] ?? [:]
        #expect(setOnce["first_seen"] as? String == "2024-01-01")
    }

    @Test("setPersonProperties ignores empty properties")
    func setPersonPropertiesIgnoresEmptyProperties() async throws {
        let sut = getSut(flushAt: 1)

        sut.setPersonProperties(userPropertiesToSet: [:], userPropertiesToSetOnce: [:])
        sut.setPersonProperties(userPropertiesToSet: nil, userPropertiesToSetOnce: nil)

        // Add event to ensure flush happens
        sut.capture("test_event")

        let events = try await getServerEvents(server)

        // Should only have the test_event, no $set events
        #expect(events.count == 1)
        #expect(events[0].event == "test_event")
    }

    @Test("setPersonProperties uses current distinctId")
    func setPersonPropertiesUsesCurrentDistinctId() async throws {
        let sut = getSut(flushAt: 2)

        sut.identify("my_user_id")
        sut.setPersonProperties(userPropertiesToSet: ["plan": "premium"])

        let events = try await getServerEvents(server)

        #expect(events.count == 2)
        #expect(events[0].event == "$identify")
        #expect(events[1].event == "$set")
        #expect(events[1].distinctId == "my_user_id")
    }

    @Test("setPersonProperties deduplicates nested dictionaries with different key order")
    func setPersonPropertiesDeduplicatesNestedDictionariesWithDifferentKeyOrder() async throws {
        let sut = getSut(flushAt: 2)

        // First call with nested dictionary in one key order
        sut.setPersonProperties(userPropertiesToSet: [
            "z_key": "value",
            "a_key": "value",
            "nested": [
                "z_inner": 1,
                "a_inner": 2,
            ] as [String: Any],
        ])

        // Second call with same values but different key insertion order
        sut.setPersonProperties(userPropertiesToSet: [
            "z_key": "value",
            "nested": [
                "a_inner": 2,
                "z_inner": 1,
            ] as [String: Any],
            "a_key": "value",
        ])

        // Add a different event to trigger flush
        sut.capture("test_event")

        let events = try await getServerEvents(server)

        // Should only have 1 $set event (second was deduplicated) + 1 test_event
        #expect(events.count == 2)
        #expect(events[0].event == "$set")
        #expect(events[1].event == "test_event")
    }

    // MARK: - Identify Deduplication Tests

    @Test("identify deduplicates $set event when called with same properties for same user")
    func identifyDeduplicatesSetEventWithSameProperties() async throws {
        let sut = getSut(flushAt: 2)

        // First identify creates the user
        sut.identify("user123")

        // Second identify with same distinctId sends $set
        sut.identify("user123", userProperties: ["name": "John"])

        // Third identify with same properties should be deduplicated
        sut.identify("user123", userProperties: ["name": "John"])

        let events = try await getServerEvents(server)

        // Should have: $identify + 1 $set (second $set deduplicated)
        #expect(events.count == 2)
        #expect(events[0].event == "$identify")
        #expect(events[1].event == "$set")
    }

    @Test("identify does not deduplicate $set event when properties differ")
    func identifyDoesNotDeduplicateSetEventWithDifferentProperties() async throws {
        let sut = getSut(flushAt: 3)

        // First identify creates the user
        sut.identify("user123")

        // Second identify with properties
        sut.identify("user123", userProperties: ["name": "John"])

        // Third identify with different properties - should NOT be deduplicated
        sut.identify("user123", userProperties: ["name": "Jane"])

        let events = try await getServerEvents(server)

        // Should have: $identify + 2 $set events
        #expect(events.count == 3)
        #expect(events[0].event == "$identify")
        #expect(events[1].event == "$set")
        #expect(events[2].event == "$set")

        let set1 = events[1].properties["$set"] as? [String: Any] ?? [:]
        #expect(set1["name"] as? String == "John")

        let set2 = events[2].properties["$set"] as? [String: Any] ?? [:]
        #expect(set2["name"] as? String == "Jane")
    }

    @Test("identify and setPersonProperties share deduplication cache")
    func identifyAndSetPersonPropertiesShareDeduplicationCache() async throws {
        let sut = getSut(flushAt: 2)

        // First identify creates the user
        sut.identify("user123")

        // Set properties via identify
        sut.identify("user123", userProperties: ["name": "John"])

        // Same properties via setPersonProperties - should be deduplicated
        sut.setPersonProperties(userPropertiesToSet: ["name": "John"])

        let events = try await getServerEvents(server)

        // Should have: $identify + 1 $set (setPersonProperties deduplicated)
        #expect(events.count == 2)
        #expect(events[0].event == "$identify")
        #expect(events[1].event == "$set")
    }

    @Test("identify deduplicates with setOnce properties")
    func identifyDeduplicatesWithSetOnceProperties() async throws {
        let sut = getSut(flushAt: 2)

        sut.identify("user123")

        sut.identify("user123",
                     userProperties: ["name": "John"],
                     userPropertiesSetOnce: ["first_seen": "2024-01-01"])

        // Same properties again - should be deduplicated
        sut.identify("user123",
                     userProperties: ["name": "John"],
                     userPropertiesSetOnce: ["first_seen": "2024-01-01"])

        let events = try await getServerEvents(server)

        #expect(events.count == 2)
        #expect(events[0].event == "$identify")
        #expect(events[1].event == "$set")
    }
}
