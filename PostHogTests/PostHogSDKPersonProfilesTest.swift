//
//  PostHogSDKPersonProfilesTest.swift
//  PostHogTests
//
//  Created by Manoel Aranda Neto on 10.09.24.
//

import Foundation
@testable import PostHog
import Testing

@Suite("PostHogSDK Person Profiles Tests", .serialized)
class PostHogSDKPersonProfilesTest {
    let server: MockPostHogServer
    let apiKey: String

    init() {
        apiKey = uniqueApiKey()
        server = MockPostHogServer()

        Self.deleteDefaults()
        server.start()
    }

    deinit {
        deleteSafely(applicationSupportDirectoryURL())
        server.stop()
    }

    static func deleteDefaults() {
        let userDefaults = UserDefaults.standard
        userDefaults.removeObject(forKey: "PHGVersionKey")
        userDefaults.removeObject(forKey: "PHGBuildKeyV2")
        userDefaults.synchronize()

        deleteSafely(applicationSupportDirectoryURL())
    }

    func getSut(flushAt: Int = 1,
                personProfiles: PostHogPersonProfiles = .identifiedOnly) -> PostHogSDK
    {
        let config = PostHogConfig(apiKey: apiKey, host: "http://localhost:9001")
        config.flushAt = flushAt
        config.preloadFeatureFlags = false
        config.sendFeatureFlagEvent = false
        config.disableReachabilityForTesting = true
        config.disableQueueTimerForTesting = true
        config.captureApplicationLifecycleEvents = false
        config.personProfiles = personProfiles
        return PostHogSDK.with(config)
    }

    @Test("capture sets process person to false if identified only and not identified")
    func captureProcessPersonFalseIfIdentifiedOnlyAndNotIdentified() async throws {
        let sut = getSut()

        sut.capture("test event")

        let events = try await getServerEvents(server)

        #expect(events.count == 1)

        let event = events.first!

        #expect(event.properties["$process_person_profile"] as? Bool == false)

        sut.reset()
        sut.close()
    }

    @Test("capture sets process person to true if identified only and with user props")
    func captureProcessPersonTrueIfIdentifiedOnlyAndWithUserProps() async throws {
        let sut = getSut()

        sut.capture("test event",
                    userProperties: ["userProp": "value"])

        let events = try await getServerEvents(server)

        #expect(events.count == 1)

        let event = events.first!

        #expect(event.properties["$process_person_profile"] as? Bool == true)

        sut.reset()
        sut.close()
    }

    @Test("capture sets process person to true if identified only and with user set once props")
    func captureProcessPersonTrueIfIdentifiedOnlyAndWithUserSetOnceProps() async throws {
        let sut = getSut()

        sut.capture("test event",
                    userPropertiesSetOnce: ["userProp": "value"])

        let events = try await getServerEvents(server)

        #expect(events.count == 1)

        let event = events.first!

        #expect(event.properties["$process_person_profile"] as? Bool == true)

        sut.reset()
        sut.close()
    }

    @Test("capture sets process person to true if identified only and with group props")
    func captureProcessPersonTrueIfIdentifiedOnlyAndWithGroupProps() async throws {
        let sut = getSut()

        sut.capture("test event",
                    groups: ["groupProp": "value"])

        let events = try await getServerEvents(server)

        #expect(events.count == 1)

        let event = events.first!

        #expect(event.properties["$process_person_profile"] as? Bool == true)

        sut.reset()
        sut.close()
    }

    @Test("capture sets process person to true if identified only and identified")
    func captureProcessPersonTrueIfIdentifiedOnlyAndIdentified() async throws {
        let sut = getSut(flushAt: 2)

        sut.identify("distinctId")

        sut.capture("test event")

        let events = try await getServerEvents(server)

        #expect(events.count == 2)

        let event = events.last!

        #expect(event.properties["$process_person_profile"] as? Bool == true)

        sut.reset()
        sut.close()
    }

    @Test("capture sets process person to true if identified only and with alias")
    func captureProcessPersonTrueIfIdentifiedOnlyAndWithAlias() async throws {
        let sut = getSut(flushAt: 2)

        sut.alias("distinctId")

        sut.capture("test event")

        let events = try await getServerEvents(server)

        #expect(events.count == 2)

        let event = events.last!

        #expect(event.properties["$process_person_profile"] as? Bool == true)

        sut.reset()
        sut.close()
    }

    @Test("capture sets process person to true if identified only and with groups")
    func captureProcessPersonTrueIfIdentifiedOnlyAndWithGroups() async throws {
        let sut = getSut(flushAt: 2)

        sut.group(type: "theType", key: "theKey")

        sut.capture("test event")

        let events = try await getServerEvents(server)

        #expect(events.count == 2)

        let event = events.last!

        #expect(event.properties["$process_person_profile"] as? Bool == true)

        sut.reset()
        sut.close()
    }

    @Test("capture sets process person to true if always")
    func captureProcessPersonTrueIfAlways() async throws {
        let sut = getSut(personProfiles: .always)

        sut.capture("test event")

        let events = try await getServerEvents(server)

        #expect(events.count == 1)

        let event = events.first!

        #expect(event.properties["$process_person_profile"] as? Bool == true)

        sut.reset()
        sut.close()
    }

    @Test("capture sets process person to false if never and identify called")
    func captureProcessPersonFalseIfNeverAndIdentifyCalled() async throws {
        let sut = getSut(personProfiles: .never)

        sut.identify("distinctId")

        sut.capture("test event")

        let events = try await getServerEvents(server)

        // identify will be ignored here hence only 1
        #expect(events.count == 1)

        let event = events.first!

        #expect(event.properties["$process_person_profile"] as? Bool == false)

        sut.reset()
        sut.close()
    }

    @Test("capture sets process person to false if never and alias called")
    func captureProcessPersonFalseIfNeverAndAliasCalled() async throws {
        let sut = getSut(personProfiles: .never)

        sut.alias("distinctId")

        sut.capture("test event")

        let events = try await getServerEvents(server)

        // alias will be ignored here hence only 1
        #expect(events.count == 1)

        let event = events.first!

        #expect(event.properties["$process_person_profile"] as? Bool == false)

        sut.reset()
        sut.close()
    }

    @Test("capture sets process person to false if never and group called")
    func captureProcessPersonFalseIfNeverAndGroupCalled() async throws {
        let sut = getSut(personProfiles: .never)

        sut.group(type: "theType", key: "theKey")

        sut.capture("test event")

        let events = try await getServerEvents(server)

        // group will be ignored here hence only 1
        #expect(events.count == 1)

        let event = events.first!

        #expect(event.properties["$process_person_profile"] as? Bool == false)

        sut.reset()
        sut.close()
    }
}
