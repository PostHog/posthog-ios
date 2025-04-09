//
//  PostHogSessionManagerTest.swift
//  PostHog
//
//  Created by Yiannis Josephides on 16/12/2024.
//

import Foundation
import Testing

@testable import PostHog
import XCTest

@Suite(.serialized)
enum PostHogSessionManagerTest {
    @Suite("Test session id rotation logic")
    struct SessionRotation {
        let mockAppLifecycle: MockApplicationLifecyclePublisher

        init() {
            mockAppLifecycle = MockApplicationLifecyclePublisher()
            DI.main.appLifecyclePublisher = mockAppLifecycle
            DI.main.sessionManager = PostHogSessionManager()
        }

        @Test("Session id is cleared after 30 min of background time")
        func testSessionClearedBackgrounded() throws {
            let mockNow = MockDate()
            now = { mockNow.date }

            let originalSessionId = PostHogSessionManager.shared.getNextSessionId()

            try #require(originalSessionId != nil)

            PostHogSessionManager.shared.touchSession()
            var newSessionId: String?

            newSessionId = PostHogSessionManager.shared.getSessionId()

            #expect(newSessionId == originalSessionId)

            mockAppLifecycle.simulateAppDidEnterBackground()
            mockNow.date.addTimeInterval(60 * 30) // +30 minutes (session should not rotate)
            newSessionId = PostHogSessionManager.shared.getSessionId()

            #expect(newSessionId == originalSessionId)

            mockNow.date.addTimeInterval(60 * 1) // past 30 minutes (session should clear)
            newSessionId = PostHogSessionManager.shared.getSessionId()

            #expect(newSessionId == nil)
        }

        @Test("Session id is rotated after 30 min of inactivity")
        func testSessionRotatedWhenInactive() throws {
            let mockNow = MockDate()
            now = { mockNow.date }

            // session start
            let originalSessionId = PostHogSessionManager.shared.getNextSessionId()
            // app foregrounded
            mockAppLifecycle.simulateAppDidBecomeActive()

            try #require(originalSessionId != nil)

            // activity
            PostHogSessionManager.shared.touchSession()
            var newSessionId: String?

            // inactivity
            mockNow.date.addTimeInterval(60 * 30) // 30 minutes inactivity (session should not rotate)
            newSessionId = PostHogSessionManager.shared.getSessionId()

            #expect(newSessionId == originalSessionId)

            mockNow.date.addTimeInterval(20) // past 30 minutes of inactivity (session should rotate)
            newSessionId = PostHogSessionManager.shared.getSessionId()

            #expect(newSessionId != nil)
            #expect(newSessionId != originalSessionId)
        }

        @Test("Session id is rotated after max session length is reached")
        func testSessionRotatedWhenPastMaxSessionLength() throws {
            let mockNow = MockDate()
            now = { mockNow.date }

            // session start
            let originalSessionId = PostHogSessionManager.shared.getNextSessionId()
            // app foregrounded
            mockAppLifecycle.simulateAppDidBecomeActive()

            try #require(originalSessionId != nil)

            var newSessionId: String?

            for _ in 0 ..< 49 {
                // activity
                mockNow.date.addTimeInterval(60 * 29) // +23 hours, 40 minutes (session should not rotate)
                PostHogSessionManager.shared.touchSession()
            }

            newSessionId = PostHogSessionManager.shared.getSessionId()

            #expect(newSessionId == originalSessionId)

            mockNow.date.addTimeInterval(60 * 10) // +10 minutes (session should not rotate)
            newSessionId = PostHogSessionManager.shared.getSessionId()

            #expect(newSessionId == originalSessionId)

            mockNow.date.addTimeInterval(60 * 10) // +10 minutes (session should rotate)
            newSessionId = PostHogSessionManager.shared.getSessionId()

            #expect(newSessionId != originalSessionId)
        }
    }

    @Suite("Test $session_id property in events")
    class PostHogSDKEvents {
        let mockAppLifecycle: MockApplicationLifecyclePublisher
        var server: MockPostHogServer!

        init() {
            mockAppLifecycle = MockApplicationLifecyclePublisher()
            DI.main.appLifecyclePublisher = mockAppLifecycle
            DI.main.sessionManager = PostHogSessionManager()

            server = MockPostHogServer()
            server.start()

            // important!
            deleteSafely(applicationSupportDirectoryURL())
        }

        deinit {
            now = { Date() }
            server.stop()
            server = nil
            PostHogSessionManager.shared.endSession {}
        }

        func getSut(
            preloadFeatureFlags: Bool = false,
            sendFeatureFlagEvent: Bool = false,
            captureApplicationLifecycleEvents: Bool = false,
            flushAt: Int = 1,
            optOut: Bool = false,
            propertiesSanitizer: PostHogPropertiesSanitizer? = nil,
            personProfiles: PostHogPersonProfiles = .identifiedOnly
        ) -> PostHogSDK {
            let config = PostHogConfig(apiKey: testAPIKey, host: "http://localhost:9001")
            config.flushAt = flushAt
            config.preloadFeatureFlags = preloadFeatureFlags
            config.sendFeatureFlagEvent = sendFeatureFlagEvent
            config.disableReachabilityForTesting = true
            config.disableQueueTimerForTesting = true
            config.captureApplicationLifecycleEvents = captureApplicationLifecycleEvents
            config.optOut = optOut
            config.propertiesSanitizer = propertiesSanitizer
            config.personProfiles = personProfiles
            config.maxBatchSize = max(flushAt, config.maxBatchSize)
            return PostHogSDK.with(config)
        }

        @Test("Clears $session_id after 30 mins of background inactivity")
        func testSessionClearedAfterBackgroundInactivity() async throws {
            let sut = getSut(flushAt: 2)
            let mockNow = MockDate()
            now = { mockNow.date }

            defer {
                sut.reset()
                sut.close()
            }

            // open app
            mockAppLifecycle.simulateAppDidBecomeActive()

            // some activity
            PostHogSessionManager.shared.touchSession()
            sut.capture("event captured", timestamp: mockNow.date)

            // background app
            mockAppLifecycle.simulateAppDidEnterBackground()

            mockNow.date.addTimeInterval(60 * 31) // +31 mins of inactivity
            sut.capture("event captured after 31 mins in background", timestamp: mockNow.date)

            let events = try await getServerEvents(server)

            #expect(events.count == 2)
            #expect(events[0].event == "event captured")
            #expect(events[1].event == "event captured after 31 mins in background")
            #expect(events[0].properties["$session_id"] != nil)
            #expect(events[1].properties["$session_id"] == nil) // no session
        }

        @Test("Rotates $session_id after 30 mins of inactivity")
        func testSessionRotatedAfterInactivity() async throws {
            let sut = getSut(flushAt: 2)
            let mockNow = MockDate()
            now = { mockNow.date }

            defer {
                sut.reset()
                sut.close()
            }

            // open app
            mockAppLifecycle.simulateAppDidFinishLaunching()
            mockAppLifecycle.simulateAppDidBecomeActive()

            // some activity
            PostHogSessionManager.shared.touchSession()
            sut.capture("event captured")

            mockNow.date.addTimeInterval(60 * 31) // +31 mins of inactivity
            sut.capture("event captured after 31 mins in background")

            let events = try await getServerEvents(server)

            #expect(events.count == 2)

            let sessionId1 = events[0].properties["$session_id"] as? String
            let sessionId2 = events[1].properties["$session_id"] as? String

            try #require(sessionId1 != nil)
            try #require(sessionId2 != nil)

            #expect(sessionId1 != sessionId2)

            sut.reset()
            sut.close()
        }

        @Test("Rotates $session_id after max session length of 24 hours")
        func testSessionRotatedAfterMaxSessionLength() async throws {
            let sut = getSut(flushAt: 52)
            let mockNow = MockDate()
            var compoundedTime: TimeInterval = 0
            now = { mockNow.date }

            defer {
                sut.reset()
                sut.close()
            }

            // open app
            mockAppLifecycle.simulateAppDidFinishLaunching()
            mockAppLifecycle.simulateAppDidBecomeActive()

            // activity
            PostHogSessionManager.shared.touchSession()
            sut.capture("event 0 captured", timestamp: mockNow.date)

            let originalSessionId = PostHogSessionManager.shared.getSessionId(readOnly: true)

            // 23 hours, 41 minutes worth of activity
            for i in 0 ..< 49 {
                // activity
                compoundedTime += 60 * 29
                mockNow.date.addTimeInterval(60 * 29)
                PostHogSessionManager.shared.touchSession()
                sut.capture("event \(i) captured", timestamp: mockNow.date)
            }

            compoundedTime += 60 * 10
            mockNow.date.addTimeInterval(60 * 10)
            PostHogSessionManager.shared.touchSession()
            sut.capture("event 51 captured", timestamp: mockNow.date)

            compoundedTime += 60 * 10
            mockNow.date.addTimeInterval(60 * 10)
            PostHogSessionManager.shared.touchSession()
            sut.capture("event 52 captured", timestamp: mockNow.date)

            let events = try await getServerEvents(server)

            try #require(events.count == 52)

            let firstEvent = events[0]
            let nextToLastEvent = events[50]
            let lastEvent = events[51]

            try #require(firstEvent != nil)
            try #require(nextToLastEvent != nil)
            try #require(lastEvent != nil)

            let firstEventId = firstEvent.properties["$session_id"] as? String
            let nextToLastEventId = nextToLastEvent.properties["$session_id"] as? String
            let lastEventId = lastEvent.properties["$session_id"] as? String

            try #require(firstEventId != nil)
            try #require(nextToLastEventId != nil)
            try #require(lastEventId != nil)

            #expect(firstEvent.event == "event 0 captured")
            #expect(nextToLastEvent.event == "event 51 captured")
            #expect(lastEvent.event == "event 52 captured")

            #expect(firstEventId == originalSessionId)
            #expect(lastEventId != firstEventId)
            #expect(nextToLastEventId == firstEventId)
        }
    }

    @Suite("Test utility classes")
    struct UtilityTests {
        class LifeCycleSub {
            let token: RegistrationToken

            init(_ publisher: MockApplicationLifecyclePublisher) {
                token = publisher.onDidBecomeActive {
                    // handle here
                }
            }
        }

        @Test("ApplicationLifecyclePublisher handles token deallocation correctly")
        func testApplicationLifecyclePublisherHandlesTokenDeallocationCorrectly() {
            let sut = MockApplicationLifecyclePublisher()

            var registrations = [
                LifeCycleSub(sut),
                LifeCycleSub(sut),
                LifeCycleSub(sut),
                LifeCycleSub(sut),
                LifeCycleSub(sut),
            ]

            #expect(sut.didBecomeActiveHandlers.count == 5)
            registrations.removeFirst(2)
            #expect(sut.didBecomeActiveHandlers.count == 3)
            registrations.removeAll()
            #expect(sut.didBecomeActiveHandlers.isEmpty)
        }
    }

    @Suite("Test React Native session management")
    struct ReactNativeTests {
        let mockAppLifecycle: MockApplicationLifecyclePublisher

        init() {
            postHogSdkName = "posthog-react-native"
            mockAppLifecycle = MockApplicationLifecyclePublisher()
            DI.main.appLifecyclePublisher = mockAppLifecycle
            DI.main.sessionManager = PostHogSessionManager()
        }

        @Test("Session id is NOT cleared after 30 min of background time")
        func testSessionNotClearedBackgrounded() throws {
            let mockNow = MockDate()
            now = { mockNow.date }

            // RN sets custom session id
            let rnSessionId = UUID().uuidString
            PostHogSessionManager.shared.setSessionId(rnSessionId)

            PostHogSessionManager.shared.touchSession()
            var newSessionId: String?

            newSessionId = PostHogSessionManager.shared.getSessionId()

            #expect(newSessionId == rnSessionId)

            mockAppLifecycle.simulateAppDidEnterBackground()
            mockNow.date.addTimeInterval(60 * 30) // +30 minutes (session should not rotate)
            newSessionId = PostHogSessionManager.shared.getSessionId()

            #expect(newSessionId == rnSessionId)

            mockNow.date.addTimeInterval(60 * 1) // past 30 minutes (session should clear)
            newSessionId = PostHogSessionManager.shared.getSessionId()

            #expect(newSessionId == rnSessionId)
        }

        @Test("Session id is NOT rotated after 30 min of inactivity")
        func testSessionNotRotatedWhenInactive() throws {
            let mockNow = MockDate()
            now = { mockNow.date }

            // RN sets custom session id
            let rnSessionId = UUID().uuidString
            PostHogSessionManager.shared.setSessionId(rnSessionId)

            // app foregrounded
            mockAppLifecycle.simulateAppDidBecomeActive()

            // activity
            PostHogSessionManager.shared.touchSession()
            var newSessionId: String?

            // inactivity
            mockNow.date.addTimeInterval(60 * 30) // 30 minutes inactivity (session should not rotate)
            newSessionId = PostHogSessionManager.shared.getSessionId()

            #expect(newSessionId == rnSessionId)

            mockNow.date.addTimeInterval(20) // past 30 minutes of inactivity (session should rotate)
            newSessionId = PostHogSessionManager.shared.getSessionId()

            #expect(newSessionId == rnSessionId)
        }

        @Test("Session id is NOT rotated after max session length is reached")
        func testSessionNotRotatedWhenPastMaxSessionLength() throws {
            let mockNow = MockDate()
            now = { mockNow.date }

            // RN sets custom session id
            let rnSessionId = UUID().uuidString
            PostHogSessionManager.shared.setSessionId(rnSessionId)

            // app foregrounded
            mockAppLifecycle.simulateAppDidBecomeActive()

            var newSessionId: String?

            for _ in 0 ..< 49 {
                // activity
                mockNow.date.addTimeInterval(60 * 29) // +23 hours, 40 minutes (session should not rotate)
                PostHogSessionManager.shared.touchSession()
            }

            newSessionId = PostHogSessionManager.shared.getSessionId()

            #expect(newSessionId == rnSessionId)

            mockNow.date.addTimeInterval(60 * 10) // +10 minutes (session should not rotate)
            newSessionId = PostHogSessionManager.shared.getSessionId()

            #expect(newSessionId == rnSessionId)

            mockNow.date.addTimeInterval(60 * 10) // +10 minutes (session should rotate)
            newSessionId = PostHogSessionManager.shared.getSessionId()

            #expect(newSessionId == rnSessionId)
        }

        @Test("Session id is NOT cleared when startSession() is called")
        func testSessionNotRotatedWhenStartSessionCalled() throws {
            let mockNow = MockDate()
            now = { mockNow.date }

            // RN sets custom session id
            let rnSessionId = UUID().uuidString
            PostHogSessionManager.shared.setSessionId(rnSessionId)

            var newSessionId = PostHogSessionManager.shared.getSessionId()

            #expect(newSessionId == rnSessionId)

            PostHogSessionManager.shared.startSession()

            newSessionId = PostHogSessionManager.shared.getSessionId()

            #expect(newSessionId == rnSessionId)
        }

        @Test("Session id is NOT cleared when endSession() is called")
        func testSessionNotRotatedWhenEndSessionCalled() throws {
            let mockNow = MockDate()
            now = { mockNow.date }

            // RN sets custom session id
            let rnSessionId = UUID().uuidString
            PostHogSessionManager.shared.setSessionId(rnSessionId)

            var newSessionId = PostHogSessionManager.shared.getSessionId()

            #expect(newSessionId == rnSessionId)

            PostHogSessionManager.shared.endSession()

            newSessionId = PostHogSessionManager.shared.getSessionId()

            #expect(newSessionId == rnSessionId)
        }

        @Test("Session id is NOT rotated when resetSession() is called")
        func testSessionNotRotatedWhenResetSessionCalled() throws {
            let mockNow = MockDate()
            now = { mockNow.date }

            // RN sets custom session id
            let rnSessionId = UUID().uuidString
            PostHogSessionManager.shared.setSessionId(rnSessionId)

            var newSessionId = PostHogSessionManager.shared.getSessionId()

            #expect(newSessionId == rnSessionId)

            PostHogSessionManager.shared.resetSession()

            newSessionId = PostHogSessionManager.shared.getSessionId()

            #expect(newSessionId == rnSessionId)
        }
    }
}
