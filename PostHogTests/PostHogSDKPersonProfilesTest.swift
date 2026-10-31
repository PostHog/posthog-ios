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

    @Test("capture sets the process person option to false if identified only and not identified")
    func captureSetsProcessPersonFalseIfIdentifiedOnlyAndNotIdentified() throws {
        let sut = getSut()

        sut.capture("test event")

        let events = getBatchedEvents(server)

        #expect(events.count == 1)

        let event = try #require(events.first)

        #expect(event.options["process_person_profile"] as? Bool == false)

        sut.reset()
        sut.close()
    }

    @Test("a caller $process_person_profile property overrides the SDK")
    func callerOverridesProcessPersonProfile() throws {
        let sut = getSut(personProfiles: .never)

        sut.capture("test event", properties: ["$process_person_profile": true])

        let event = try #require(getBatchedEvents(server).first)
        #expect(event.options["process_person_profile"] as? Bool == true)

        sut.reset()
        sut.close()
    }

    @Test("capture sends no process person option if identified only and with user props")
    func captureSendsNoProcessPersonOptionIfIdentifiedOnlyWithUserProps() throws {
        let sut = getSut()

        sut.capture("test event",
                    userProperties: ["userProp": "value"])

        let events = getBatchedEvents(server)

        #expect(events.count == 1)

        let event = try #require(events.first)

        #expect(event.options["process_person_profile"] == nil)

        sut.reset()
        sut.close()
    }

    @Test("capture sends no process person option if identified only and with user set once props")
    func captureSendsNoProcessPersonOptionIfIdentifiedOnlyWithUserSetOnceProps() throws {
        let sut = getSut()

        sut.capture("test event",
                    userPropertiesSetOnce: ["userProp": "value"])

        let events = getBatchedEvents(server)

        #expect(events.count == 1)

        let event = try #require(events.first)

        #expect(event.options["process_person_profile"] == nil)

        sut.reset()
        sut.close()
    }

    @Test("capture sends no process person option if identified only and with group props")
    func captureSendsNoProcessPersonOptionIfIdentifiedOnlyWithGroupProps() throws {
        let sut = getSut()

        sut.capture("test event",
                    groups: ["groupProp": "value"])

        let events = getBatchedEvents(server)

        #expect(events.count == 1)

        let event = try #require(events.first)

        #expect(event.options["process_person_profile"] == nil)

        sut.reset()
        sut.close()
    }

    @Test("capture sends no process person option if identified only and identified")
    func captureSendsNoProcessPersonOptionIfIdentifiedOnlyAndIdentified() throws {
        let sut = getSut(flushAt: 2)

        sut.identify("distinctId")

        sut.capture("test event")

        let events = getBatchedEvents(server)

        #expect(events.count == 2)

        let event = try #require(events.last)

        #expect(event.options["process_person_profile"] == nil)

        sut.reset()
        sut.close()
    }

    @Test("capture sends no process person option if identified only and with alias")
    func captureSendsNoProcessPersonOptionIfIdentifiedOnlyWithAlias() throws {
        let sut = getSut(flushAt: 2)

        sut.alias("distinctId")

        sut.capture("test event")

        let events = getBatchedEvents(server)

        #expect(events.count == 2)

        let event = try #require(events.last)

        #expect(event.options["process_person_profile"] == nil)

        sut.reset()
        sut.close()
    }

    @Test("capture sends no process person option if identified only and with groups")
    func captureSendsNoProcessPersonOptionIfIdentifiedOnlyWithGroups() throws {
        let sut = getSut(flushAt: 2)

        sut.group(type: "theType", key: "theKey")

        sut.capture("test event")

        let events = getBatchedEvents(server)

        #expect(events.count == 2)

        let event = try #require(events.last)

        #expect(event.options["process_person_profile"] == nil)

        sut.reset()
        sut.close()
    }

    @Test("capture sends no process person option if always")
    func captureSendsNoProcessPersonOptionIfAlways() throws {
        let sut = getSut(personProfiles: .always)

        sut.capture("test event")

        let events = getBatchedEvents(server)

        #expect(events.count == 1)

        let event = try #require(events.first)

        #expect(event.options["process_person_profile"] == nil)

        sut.reset()
        sut.close()
    }

    @Test("capture sets the process person option to false if never and identify called")
    func captureSetsProcessPersonFalseIfNeverAndIdentifyCalled() throws {
        let sut = getSut(personProfiles: .never)

        sut.identify("distinctId")

        sut.capture("test event")

        let events = getBatchedEvents(server)

        // identify will be ignored here hence only 1
        #expect(events.count == 1)

        let event = try #require(events.first)

        #expect(event.options["process_person_profile"] as? Bool == false)

        sut.reset()
        sut.close()
    }

    @Test("capture sets the process person option to false if never and alias called")
    func captureSetsProcessPersonFalseIfNeverAndAliasCalled() throws {
        let sut = getSut(personProfiles: .never)

        sut.alias("distinctId")

        sut.capture("test event")

        let events = getBatchedEvents(server)

        // alias will be ignored here hence only 1
        #expect(events.count == 1)

        let event = try #require(events.first)

        #expect(event.options["process_person_profile"] as? Bool == false)

        sut.reset()
        sut.close()
    }

    @Test("capture sets the process person option to false if never and group called")
    func captureSetsProcessPersonFalseIfNeverAndGroupCalled() throws {
        let sut = getSut(personProfiles: .never)

        sut.group(type: "theType", key: "theKey")

        sut.capture("test event")

        let events = getBatchedEvents(server)

        // group will be ignored here hence only 1
        #expect(events.count == 1)

        let event = try #require(events.first)

        #expect(event.options["process_person_profile"] as? Bool == false)

        sut.reset()
        sut.close()
    }
}
