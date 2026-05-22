//
//  PostHogScreenNameTest.swift
//  PostHogTests
//

import Foundation
import Nimble
@testable import PostHog
import Quick

class PostHogScreenNameTest: QuickSpec {
    final class CapturedEvents {
        var events: [PostHogEvent] = []
    }

    func getSut(captured: CapturedEvents) -> PostHogSDK {
        let config = PostHogConfig(projectToken: testProjectToken, host: "http://localhost:9001")
        config.flushAt = 1
        config.preloadFeatureFlags = false
        config.sendFeatureFlagEvent = false
        config.disableReachabilityForTesting = true
        config.disableQueueTimerForTesting = true
        config.disableFlushOnBackgroundForTesting = true
        config.captureApplicationLifecycleEvents = false
        config.setBeforeSend { event in
            captured.events.append(event)
            return nil
        }

        let storage = PostHogStorage(config)
        storage.reset()

        return PostHogSDK.with(config)
    }

    override func spec() {
        var captured: CapturedEvents!

        beforeEach {
            captured = CapturedEvents()
        }

        it("event captured before screen has no screen_name") {
            let sut = self.getSut(captured: captured)

            sut.capture("event")

            let event = captured.events.first { $0.event == "event" }!
            expect(event.properties["$screen_name"]).to(beNil())

            sut.reset()
            sut.close()
        }

        it("event captured after screen carries screen_name") {
            let sut = self.getSut(captured: captured)

            sut.screen("Home")
            sut.capture("event")

            let event = captured.events.first { $0.event == "event" }!
            expect(event.properties["$screen_name"] as? String) == "Home"

            sut.reset()
            sut.close()
        }

        it("caller-supplied screen_name overrides cached value") {
            let sut = self.getSut(captured: captured)

            sut.screen("Home")
            sut.capture("event", properties: ["$screen_name": "Override"])

            let event = captured.events.first { $0.event == "event" }!
            expect(event.properties["$screen_name"] as? String) == "Override"

            sut.reset()
            sut.close()
        }

        it("reset clears screen_name from subsequent events") {
            let sut = self.getSut(captured: captured)

            sut.screen("Home")
            sut.reset()
            sut.capture("event")

            let event = captured.events.first { $0.event == "event" }!
            expect(event.properties["$screen_name"]).to(beNil())

            sut.close()
        }

        it("exception event carries screen_name") {
            let sut = self.getSut(captured: captured)

            sut.screen("Home")
            sut.captureException(NSError(domain: "test", code: 1))

            let event = captured.events.first { $0.event == "$exception" }!
            expect(event.properties["$screen_name"] as? String) == "Home"

            sut.reset()
            sut.close()
        }

        it("snapshot event does not carry screen_name") {
            let sut = self.getSut(captured: captured)

            sut.screen("Home")
            sut.capture("$snapshot", properties: ["$session_id": "test-session-id"])

            let event = captured.events.first { $0.event == "$snapshot" }!
            expect(event.properties["$screen_name"]).to(beNil())

            sut.reset()
            sut.close()
        }
    }
}
