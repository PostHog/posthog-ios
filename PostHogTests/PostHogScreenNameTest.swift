//
//  PostHogScreenNameTest.swift
//  PostHogTests
//

import Foundation
@testable import PostHog
import Testing

@Suite("Screen name", .serialized, .resetsGlobalState)
final class PostHogScreenNameTest {
    final class CapturedEvents {
        var events: [PostHogEvent] = []
    }

    private let captured: CapturedEvents

    init() {
        deleteSafely(applicationSupportDirectoryURL())
        captured = CapturedEvents()
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

    @Test("event captured before screen has no screen_name")
    func eventBeforeScreenHasNoScreenName() throws {
        let sut = getSut(captured: captured)

        sut.capture("event")

        let event = try #require(captured.events.first { $0.event == "event" })
        #expect(event.properties["$screen_name"] == nil)

        sut.reset()
        sut.close()
    }

    @Test("event captured after screen carries screen_name")
    func eventAfterScreenCarriesScreenName() throws {
        let sut = getSut(captured: captured)

        sut.screen("Home")
        sut.capture("event")

        let event = try #require(captured.events.first { $0.event == "event" })
        #expect(event.properties["$screen_name"] as? String == "Home")

        sut.reset()
        sut.close()
    }

    @Test("caller-supplied screen_name overrides cached value")
    func callerSuppliedScreenNameOverridesCachedValue() throws {
        let sut = getSut(captured: captured)

        sut.screen("Home")
        sut.capture("event", properties: ["$screen_name": "Override"])

        let event = try #require(captured.events.first { $0.event == "event" })
        #expect(event.properties["$screen_name"] as? String == "Override")

        sut.reset()
        sut.close()
    }

    @Test("blank caller-supplied screen_name keeps cached value", arguments: ["", "  "])
    func blankCallerScreenNameKeepsCachedValue(screenName: String) throws {
        let sut = getSut(captured: captured)

        sut.screen("Home")
        sut.capture("event", properties: ["$screen_name": screenName])

        let event = try #require(captured.events.first { $0.event == "event" })
        #expect(event.properties["$screen_name"] as? String == "Home")

        sut.reset()
        sut.close()
    }

    @Test("reset clears screen_name from subsequent events")
    func resetClearsScreenName() throws {
        let sut = getSut(captured: captured)

        sut.screen("Home")
        sut.reset()
        sut.capture("event")

        let event = try #require(captured.events.first { $0.event == "event" })
        #expect(event.properties["$screen_name"] == nil)

        sut.close()
    }

    @Test("exception event carries screen_name")
    func exceptionEventCarriesScreenName() throws {
        let sut = getSut(captured: captured)

        sut.screen("Home")
        sut.captureException(NSError(domain: "test", code: 1))

        let event = try #require(captured.events.first { $0.event == "$exception" })
        #expect(event.properties["$screen_name"] as? String == "Home")

        sut.reset()
        sut.close()
    }

    @Test("snapshot event does not carry screen_name")
    func snapshotEventDoesNotCarryScreenName() throws {
        let sut = getSut(captured: captured)

        sut.screen("Home")
        sut.capture("$snapshot", properties: ["$session_id": "test-session-id"])

        let event = try #require(captured.events.first { $0.event == "$snapshot" })
        #expect(event.properties["$screen_name"] == nil)

        sut.reset()
        sut.close()
    }
}

@Suite("Screen name precedence")
struct PostHogScreenNamePrecedenceTest {
    @Test("screen title wins over a $screen_name property")
    func screenTitleWinsOverProperty() throws {
        let captured = PostHogScreenNameTest.CapturedEvents()
        let config = PostHogConfig(projectToken: "screen_name_\(UUID().uuidString)", host: "http://localhost:9001")
        config.preloadFeatureFlags = false
        config.disableReachabilityForTesting = true
        config.disableQueueTimerForTesting = true
        config.captureApplicationLifecycleEvents = false
        config.setBeforeSend { event in
            captured.events.append(event)
            return nil
        }
        let sut = PostHogSDK.with(config)
        defer { sut.close() }

        sut.screen("Home", properties: ["$screen_name": "Override"])

        let event = try #require(captured.events.first { $0.event == "$screen" })
        #expect(event.properties["$screen_name"] as? String == "Home")
    }
}
