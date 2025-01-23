//
//  PostHogSDKPersonProfilesTest.swift
//  PostHogTests
//
//  Created by Manoel Aranda Neto on 10.09.24.
//

import Foundation
import Nimble
import Quick

@testable import PostHog

class PostHogSDKPersonProfilesTest: QuickSpec {
    func getSut(flushAt: Int = 1,
                personProfiles: PostHogPersonProfiles = .identifiedOnly) -> PostHogSDK
    {
        let config = PostHogConfig(apiKey: testAPIKey, host: "http://localhost:9001")
        config.flushAt = flushAt
        config.preloadFeatureFlags = false
        config.sendFeatureFlagEvent = false
        config.disableReachabilityForTesting = true
        config.disableQueueTimerForTesting = true
        config.captureApplicationLifecycleEvents = false
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
            server.stop()
            server = nil
        }

        it("capture sets process person to false if identified only and not identified") {
            let sut = self.getSut()

            sut.capture("test event")

            let events = getBatchedEvents(server)

            expect(events.count) == 1

            let event = events.first!

            expect(event.properties["$process_person_profile"] as? Bool) == false

            sut.reset()
            sut.close()
        }

        it("capture sets process person to true if identified only and with user props") {
            let sut = self.getSut()

            sut.capture("test event",
                        userProperties: ["userProp": "value"])

            let events = getBatchedEvents(server)

            expect(events.count) == 1

            let event = events.first!

            expect(event.properties["$process_person_profile"] as? Bool) == true

            sut.reset()
            sut.close()
        }

        it("capture sets process person to true if identified only and with user set once props") {
            let sut = self.getSut()

            sut.capture("test event",
                        userPropertiesSetOnce: ["userProp": "value"])

            let events = getBatchedEvents(server)

            expect(events.count) == 1

            let event = events.first!

            expect(event.properties["$process_person_profile"] as? Bool) == true

            sut.reset()
            sut.close()
        }

        it("capture sets process person to true if identified only and with group props") {
            let sut = self.getSut()

            sut.capture("test event",
                        groups: ["groupProp": "value"])

            let events = getBatchedEvents(server)

            expect(events.count) == 1

            let event = events.first!

            expect(event.properties["$process_person_profile"] as? Bool) == true

            sut.reset()
            sut.close()
        }

        it("capture sets process person to true if identified only and identified") {
            let sut = self.getSut(flushAt: 2)

            sut.identify("distinctId")

            sut.capture("test event")

            let events = getBatchedEvents(server)

            expect(events.count) == 2

            let event = events.last!

            expect(event.properties["$process_person_profile"] as? Bool) == true

            sut.reset()
            sut.close()
        }

        it("capture sets process person to true if identified only and with alias") {
            let sut = self.getSut(flushAt: 2)

            sut.alias("distinctId")

            sut.capture("test event")

            let events = getBatchedEvents(server)

            expect(events.count) == 2

            let event = events.last!

            expect(event.properties["$process_person_profile"] as? Bool) == true

            sut.reset()
            sut.close()
        }

        it("capture sets process person to true if identified only and with groups") {
            let sut = self.getSut(flushAt: 2)

            sut.group(type: "theType", key: "theKey")

            sut.capture("test event")

            let events = getBatchedEvents(server)

            expect(events.count) == 2

            let event = events.last!

            expect(event.properties["$process_person_profile"] as? Bool) == true

            sut.reset()
            sut.close()
        }

        it("capture sets process person to true if always") {
            let sut = self.getSut(personProfiles: .always)

            sut.capture("test event")

            let events = getBatchedEvents(server)

            expect(events.count) == 1

            let event = events.first!

            expect(event.properties["$process_person_profile"] as? Bool) == true

            sut.reset()
            sut.close()
        }

        it("capture sets process person to false if never and identify called") {
            let sut = self.getSut(personProfiles: .never)

            sut.identify("distinctId")

            sut.capture("test event")

            let events = getBatchedEvents(server)

            // identify will be ignored here hence only 1
            expect(events.count) == 1

            let event = events.first!

            expect(event.properties["$process_person_profile"] as? Bool) == false

            sut.reset()
            sut.close()
        }

        it("capture sets process person to false if never and alias called") {
            let sut = self.getSut(personProfiles: .never)

            sut.alias("distinctId")

            sut.capture("test event")

            let events = getBatchedEvents(server)

            // alias will be ignored here hence only 1
            expect(events.count) == 1

            let event = events.first!

            expect(event.properties["$process_person_profile"] as? Bool) == false

            sut.reset()
            sut.close()
        }

        it("capture sets process person to false if never and group called") {
            let sut = self.getSut(personProfiles: .never)

            sut.group(type: "theType", key: "theKey")

            sut.capture("test event")

            let events = getBatchedEvents(server)

            // group will be ignored here hence only 1
            expect(events.count) == 1

            let event = events.first!

            expect(event.properties["$process_person_profile"] as? Bool) == false

            sut.reset()
            sut.close()
        }
    }
}
