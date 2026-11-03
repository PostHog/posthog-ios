//
//  PostHogSDKPersonProfilesTest.swift
//  PostHogTests
//
//  Created by Manoel Aranda Neto on 10.09.24.
//

import Foundation
@testable import PostHog
import Testing

@Suite("PostHogSDK person profiles", .serialized, .resetsGlobalState)
final class PostHogSDKPersonProfilesTest {
    private var server: MockPostHogServer!

    init() {
        deleteDefaults()
        server = MockPostHogServer()
        server.start()
    }

    deinit {
        server.stop()
        server = nil
    }

    private func deleteDefaults() {
        let userDefaults = UserDefaults.standard
        userDefaults.removeObject(forKey: "PHGVersionKey")
        userDefaults.removeObject(forKey: "PHGBuildKeyV2")
        userDefaults.synchronize()

        deleteSafely(applicationSupportDirectoryURL())
    }

    private func getSut(flushAt: Int = 1,
                        personProfiles: PostHogPersonProfiles = .identifiedOnly) -> PostHogSDK
    {
        let config = PostHogConfig(projectToken: testProjectToken, host: "http://localhost:9001")
        config.flushAt = flushAt
        config.preloadFeatureFlags = false
        config.sendFeatureFlagEvent = false
        config.disableReachabilityForTesting = true
        config.disableQueueTimerForTesting = true
        config.disableFlushOnBackgroundForTesting = true
        config.captureApplicationLifecycleEvents = false
        config.personProfiles = personProfiles
        return PostHogSDK.with(config)
    }

    @Test("capture sets process person to false if identified only and not identified")
    func captureSetsProcessPersonFalseIfIdentifiedOnlyAndNotIdentified() throws {
        let sut = getSut()

        sut.capture("test event")

        let events = getBatchedEvents(server)

        #expect(events.count == 1)

        let event = try #require(events.first)

        #expect(event.properties["$process_person_profile"] as? Bool == false)

        sut.reset()
        sut.close()
    }

    @Test("caller can't override $process_person_profile")
    func callerCannotOverrideProcessPersonProfile() throws {
        let sut = getSut(personProfiles: .never)

        sut.capture("test event", properties: ["$process_person_profile": true])

        let event = try #require(getBatchedEvents(server).first)
        #expect(event.properties["$process_person_profile"] as? Bool == false)

        sut.reset()
        sut.close()
    }

    @Test("capture sets process person to true if identified only and with user props")
    func captureSetsProcessPersonTrueIfIdentifiedOnlyWithUserProps() throws {
        let sut = getSut()

        sut.capture("test event",
                    userProperties: ["userProp": "value"])

        let events = getBatchedEvents(server)

        #expect(events.count == 1)

        let event = try #require(events.first)

        #expect(event.properties["$process_person_profile"] as? Bool == true)

        sut.reset()
        sut.close()
    }

    @Test("capture sets process person to true if identified only and with user set once props")
    func captureSetsProcessPersonTrueIfIdentifiedOnlyWithUserSetOnceProps() throws {
        let sut = getSut()

        sut.capture("test event",
                    userPropertiesSetOnce: ["userProp": "value"])

        let events = getBatchedEvents(server)

        #expect(events.count == 1)

        let event = try #require(events.first)

        #expect(event.properties["$process_person_profile"] as? Bool == true)

        sut.reset()
        sut.close()
    }

    @Test("capture sets process person to true if identified only and with group props")
    func captureSetsProcessPersonTrueIfIdentifiedOnlyWithGroupProps() throws {
        let sut = getSut()

        sut.capture("test event",
                    groups: ["groupProp": "value"])

        let events = getBatchedEvents(server)

        #expect(events.count == 1)

        let event = try #require(events.first)

        #expect(event.properties["$process_person_profile"] as? Bool == true)

        sut.reset()
        sut.close()
    }

    @Test("capture sets process person to true if identified only and identified")
    func captureSetsProcessPersonTrueIfIdentifiedOnlyAndIdentified() throws {
        let sut = getSut(flushAt: 2)

        sut.identify("distinctId")

        sut.capture("test event")

        let events = getBatchedEvents(server)

        #expect(events.count == 2)

        let event = try #require(events.last)

        #expect(event.properties["$process_person_profile"] as? Bool == true)

        sut.reset()
        sut.close()
    }

    @Test("capture sets process person to true if identified only and with alias")
    func captureSetsProcessPersonTrueIfIdentifiedOnlyWithAlias() throws {
        let sut = getSut(flushAt: 2)

        sut.alias("distinctId")

        sut.capture("test event")

        let events = getBatchedEvents(server)

        #expect(events.count == 2)

        let event = try #require(events.last)

        #expect(event.properties["$process_person_profile"] as? Bool == true)

        sut.reset()
        sut.close()
    }

    @Test("capture sets process person to true if identified only and with groups")
    func captureSetsProcessPersonTrueIfIdentifiedOnlyWithGroups() throws {
        let sut = getSut(flushAt: 2)

        sut.group(type: "theType", key: "theKey")

        sut.capture("test event")

        let events = getBatchedEvents(server)

        #expect(events.count == 2)

        let event = try #require(events.last)

        #expect(event.properties["$process_person_profile"] as? Bool == true)

        sut.reset()
        sut.close()
    }

    @Test("capture sets process person to true if always")
    func captureSetsProcessPersonTrueIfAlways() throws {
        let sut = getSut(personProfiles: .always)

        sut.capture("test event")

        let events = getBatchedEvents(server)

        #expect(events.count == 1)

        let event = try #require(events.first)

        #expect(event.properties["$process_person_profile"] as? Bool == true)

        sut.reset()
        sut.close()
    }

    @Test("capture sets process person to false if never and identify called")
    func captureSetsProcessPersonFalseIfNeverAndIdentifyCalled() throws {
        let sut = getSut(personProfiles: .never)

        sut.identify("distinctId")

        sut.capture("test event")

        let events = getBatchedEvents(server)

        // identify will be ignored here hence only 1
        #expect(events.count == 1)

        let event = try #require(events.first)

        #expect(event.properties["$process_person_profile"] as? Bool == false)

        sut.reset()
        sut.close()
    }

    @Test("capture sets process person to false if never and alias called")
    func captureSetsProcessPersonFalseIfNeverAndAliasCalled() throws {
        let sut = getSut(personProfiles: .never)

        sut.alias("distinctId")

        sut.capture("test event")

        let events = getBatchedEvents(server)

        // alias will be ignored here hence only 1
        #expect(events.count == 1)

        let event = try #require(events.first)

        #expect(event.properties["$process_person_profile"] as? Bool == false)

        sut.reset()
        sut.close()
    }

    @Test("capture sets process person to false if never and group called")
    func captureSetsProcessPersonFalseIfNeverAndGroupCalled() throws {
        let sut = getSut(personProfiles: .never)

        sut.group(type: "theType", key: "theKey")

        sut.capture("test event")

        let events = getBatchedEvents(server)

        // group will be ignored here hence only 1
        #expect(events.count == 1)

        let event = try #require(events.first)

        #expect(event.properties["$process_person_profile"] as? Bool == false)

        sut.reset()
        sut.close()
    }
}
