//
//  PostHogSessionManagerTest.swift
//  PostHog
//
//  Created by Yiannis Josephides on 16/12/2024.
//

import Foundation
@testable import PostHog
import Testing

@Suite(.serialized)
enum PostHogSessionManagerTest {
    @Suite("Test session id rotation logic")
    struct SessionRotation {
        let mockAppLifecycle: MockApplicationLifecyclePublisher

        init() {
            mockAppLifecycle = MockApplicationLifecyclePublisher()
            DI.main.appLifecyclePublisher = mockAppLifecycle
        }

        func getSut() -> PostHogSDK {
            let config = PostHogConfig(apiKey: "test-key")
            return PostHogSDK.with(config)
        }

        @Test("Session id is cleared after 30 min of background time")
        func sessionClearedBackgrounded() throws {
            let mockNow = MockDate()
            now = { mockNow.date }
            let posthog = getSut()

            let originalSessionId = posthog.getSessionManager()?.getNextSessionId()

            try #require(originalSessionId != nil)

            posthog.getSessionManager()?.touchSession()
            var newSessionId: String?

            newSessionId = posthog.getSessionManager()?.getSessionId()

            #expect(newSessionId == originalSessionId)

            mockAppLifecycle.simulateAppDidEnterBackground() // user backgrounds app

            mockNow.date.addTimeInterval(60 * 30) // +30 minutes (session should not rotate)
            newSessionId = posthog.getSessionManager()?.getSessionId() // background activity

            #expect(newSessionId == originalSessionId)

            mockNow.date.addTimeInterval(60 * 1) // past 30 minutes (session should clear)
            newSessionId = posthog.getSessionManager()?.getSessionId() // background activity, session should be cleared

            #expect(newSessionId == nil)
        }

        @Test("Session id is cleared after 30 min when moving from background to foreground")
        func sessionClearedWhenMovingBetweenBackgroundAndForeground() throws {
            let mockNow = MockDate()
            now = { mockNow.date }
            let posthog = getSut()

            let originalSessionId = posthog.getSessionManager()?.getNextSessionId()

            try #require(originalSessionId != nil)

            posthog.getSessionManager()?.touchSession()
            var newSessionId: String?

            newSessionId = posthog.getSessionManager()?.getSessionId()

            #expect(newSessionId == originalSessionId)

            mockAppLifecycle.simulateAppDidEnterBackground() // user backgrounds app
            mockNow.date.addTimeInterval(60 * 29) // waits 29 mins
            mockAppLifecycle.simulateAppDidBecomeActive() // user foregrounds app
            newSessionId = posthog.getSessionManager()?.getSessionId() // should not rotate

            #expect(newSessionId == originalSessionId)

            mockAppLifecycle.simulateAppDidEnterBackground() // user backgrounds app
            mockNow.date.addTimeInterval(60 * 31) // waits 30+ mins
            mockAppLifecycle.simulateAppDidBecomeActive() // user foregrounds app
            newSessionId = posthog.getSessionManager()?.getSessionId() // *should* rotate

            #expect(newSessionId != originalSessionId)
        }

        @Test("Session id is rotated after 30 min of inactivity when app is foregrounded")
        func sessionRotatedWhenInactive() throws {
            let mockNow = MockDate()
            now = { mockNow.date }
            let posthog = getSut()

            // session start
            let originalSessionId = posthog.getSessionManager()?.getNextSessionId()
            // app foregrounded
            mockAppLifecycle.simulateAppDidBecomeActive()

            try #require(originalSessionId != nil)

            // activity
            posthog.getSessionManager()?.touchSession()
            var newSessionId: String?

            // inactivity
            mockNow.date.addTimeInterval(60 * 30) // 30 minutes inactivity (session should not rotate)
            newSessionId = posthog.getSessionManager()?.getSessionId()

            #expect(newSessionId == originalSessionId)

            mockNow.date.addTimeInterval(20) // past 30 minutes of inactivity (session should rotate)
            newSessionId = posthog.getSessionManager()?.getSessionId()

            #expect(newSessionId != nil)
            #expect(newSessionId != originalSessionId)
        }

        @Test("Session id is rotated after max session length is reached")
        func sessionRotatedWhenPastMaxSessionLength() throws {
            let mockNow = MockDate()
            now = { mockNow.date }
            let posthog = getSut()

            // session start
            let originalSessionId = posthog.getSessionManager()?.getNextSessionId()
            // app foregrounded
            mockAppLifecycle.simulateAppDidBecomeActive()

            try #require(originalSessionId != nil)

            var newSessionId: String?

            for _ in 0 ..< 49 {
                // activity
                mockNow.date.addTimeInterval(60 * 29) // +23 hours, 40 minutes (session should not rotate)
                posthog.getSessionManager()?.touchSession()
            }

            newSessionId = posthog.getSessionManager()?.getSessionId()

            #expect(newSessionId == originalSessionId)

            mockNow.date.addTimeInterval(60 * 10) // +10 minutes (session should not rotate)
            newSessionId = posthog.getSessionManager()?.getSessionId()

            #expect(newSessionId == originalSessionId)

            mockNow.date.addTimeInterval(60 * 10) // +10 minutes (session should rotate)
            newSessionId = posthog.getSessionManager()?.getSessionId()

            #expect(newSessionId != originalSessionId)
        }
    }

    @Suite("Test $session_id property in events")
    class PostHogSDKEvents: PostHogSDKBaseTest {
        let mockAppLifecycle: MockApplicationLifecyclePublisher

        init() {
            mockAppLifecycle = MockApplicationLifecyclePublisher()
            super.init()
            DI.main.appLifecyclePublisher = mockAppLifecycle
        }

        deinit {
            now = { Date() }
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
            server.reset()
            let config = makeConfig()
            config.flushAt = flushAt
            config.preloadFeatureFlags = preloadFeatureFlags
            config.sendFeatureFlagEvent = sendFeatureFlagEvent
            config.captureApplicationLifecycleEvents = captureApplicationLifecycleEvents
            config.optOut = optOut
            config.propertiesSanitizer = propertiesSanitizer
            config.personProfiles = personProfiles
            config.maxBatchSize = max(flushAt, config.maxBatchSize)
            return makeSDK(config: config)
        }

        @Test("Clears $session_id after 30 mins of background inactivity")
        func sessionClearedAfterBackgroundInactivity() async throws {
            let sut = getSut(flushAt: 2)
            let mockNow = MockDate()
            now = { mockNow.date }

            defer {
                sut.close()
            }

            // open app
            mockAppLifecycle.simulateAppDidBecomeActive()

            // some activity
            sut.getSessionManager()?.touchSession()
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
        func sessionRotatedAfterInactivity() async throws {
            let sut = getSut(flushAt: 2)
            let mockNow = MockDate()
            now = { mockNow.date }

            defer {
                sut.close()
            }

            // open app
            mockAppLifecycle.simulateAppDidFinishLaunching()
            mockAppLifecycle.simulateAppDidBecomeActive()

            // some activity
            sut.getSessionManager()?.touchSession()
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

            sut.close()
        }

        @Test("Rotates $session_id after max session length of 24 hours")
        func sessionRotatedAfterMaxSessionLength() async throws {
            let sut = getSut(flushAt: 52)
            let mockNow = MockDate()
            var compoundedTime: TimeInterval = 0
            now = { mockNow.date }

            defer {
                sut.close()
            }

            // open app
            mockAppLifecycle.simulateAppDidFinishLaunching()
            mockAppLifecycle.simulateAppDidBecomeActive()

            // activity
            sut.getSessionManager()?.touchSession()
            sut.capture("event 0 captured", timestamp: mockNow.date)

            let originalSessionId = sut.getSessionManager()?.getSessionId(readOnly: true)

            // 23 hours, 41 minutes worth of activity
            for i in 0 ..< 49 {
                // activity
                compoundedTime += 60 * 29
                mockNow.date.addTimeInterval(60 * 29)
                sut.getSessionManager()?.touchSession()
                sut.capture("event \(i) captured", timestamp: mockNow.date)
            }

            compoundedTime += 60 * 10
            mockNow.date.addTimeInterval(60 * 10)
            sut.getSessionManager()?.touchSession()
            sut.capture("event 51 captured", timestamp: mockNow.date)

            compoundedTime += 60 * 10
            mockNow.date.addTimeInterval(60 * 10)
            sut.getSessionManager()?.touchSession()
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
        func applicationLifecyclePublisherHandlesTokenDeallocationCorrectly() {
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
        let posthog: PostHogSDK

        init() {
            postHogSdkName = "posthog-react-native"
            mockAppLifecycle = MockApplicationLifecyclePublisher()
            DI.main.appLifecyclePublisher = mockAppLifecycle
            let config = PostHogConfig(apiKey: "test-key")
            posthog = PostHogSDK.with(config)
        }

        @Test("Session id is NOT cleared after 30 min of background time")
        func sessionNotClearedBackgrounded() throws {
            let mockNow = MockDate()
            now = { mockNow.date }

            // RN sets custom session id
            let rnSessionId = UUID().uuidString
            posthog.getSessionManager()?.setSessionId(rnSessionId)

            posthog.getSessionManager()?.touchSession()
            var newSessionId: String?

            newSessionId = posthog.getSessionManager()?.getSessionId()

            #expect(newSessionId == rnSessionId)

            mockAppLifecycle.simulateAppDidEnterBackground()
            mockNow.date.addTimeInterval(60 * 30) // +30 minutes (session should not rotate)
            newSessionId = posthog.getSessionManager()?.getSessionId()

            #expect(newSessionId == rnSessionId)

            mockNow.date.addTimeInterval(60 * 1) // past 30 minutes (session should clear)
            newSessionId = posthog.getSessionManager()?.getSessionId()

            #expect(newSessionId == rnSessionId)
        }

        @Test("Session id is NOT rotated after 30 min of inactivity")
        func sessionNotRotatedWhenInactive() throws {
            let mockNow = MockDate()
            now = { mockNow.date }

            // RN sets custom session id
            let rnSessionId = UUID().uuidString
            posthog.getSessionManager()?.setSessionId(rnSessionId)

            // app foregrounded
            mockAppLifecycle.simulateAppDidBecomeActive()

            // activity
            posthog.getSessionManager()?.touchSession()
            var newSessionId: String?

            // inactivity
            mockNow.date.addTimeInterval(60 * 30) // 30 minutes inactivity (session should not rotate)
            newSessionId = posthog.getSessionManager()?.getSessionId()

            #expect(newSessionId == rnSessionId)

            mockNow.date.addTimeInterval(20) // past 30 minutes of inactivity (session should rotate)
            newSessionId = posthog.getSessionManager()?.getSessionId()

            #expect(newSessionId == rnSessionId)
        }

        @Test("Session id is NOT rotated after max session length is reached")
        func sessionNotRotatedWhenPastMaxSessionLength() throws {
            let mockNow = MockDate()
            now = { mockNow.date }

            // RN sets custom session id
            let rnSessionId = UUID().uuidString
            posthog.getSessionManager()?.setSessionId(rnSessionId)

            // app foregrounded
            mockAppLifecycle.simulateAppDidBecomeActive()

            var newSessionId: String?

            for _ in 0 ..< 49 {
                // activity
                mockNow.date.addTimeInterval(60 * 29) // +23 hours, 40 minutes (session should not rotate)
                posthog.getSessionManager()?.touchSession()
            }

            newSessionId = posthog.getSessionManager()?.getSessionId()

            #expect(newSessionId == rnSessionId)

            mockNow.date.addTimeInterval(60 * 10) // +10 minutes (session should not rotate)
            newSessionId = posthog.getSessionManager()?.getSessionId()

            #expect(newSessionId == rnSessionId)

            mockNow.date.addTimeInterval(60 * 10) // +10 minutes (session should rotate)
            newSessionId = posthog.getSessionManager()?.getSessionId()

            #expect(newSessionId == rnSessionId)
        }

        @Test("Session id is NOT cleared when startSession() is called")
        func sessionNotRotatedWhenStartSessionCalled() throws {
            let mockNow = MockDate()
            now = { mockNow.date }

            // RN sets custom session id
            let rnSessionId = UUID().uuidString
            posthog.getSessionManager()?.setSessionId(rnSessionId)

            var newSessionId = posthog.getSessionManager()?.getSessionId()

            #expect(newSessionId == rnSessionId)

            posthog.getSessionManager()?.startSession()

            newSessionId = posthog.getSessionManager()?.getSessionId()

            #expect(newSessionId == rnSessionId)
        }

        @Test("Session id is NOT cleared when endSession() is called")
        func sessionNotRotatedWhenEndSessionCalled() throws {
            let mockNow = MockDate()
            now = { mockNow.date }

            // RN sets custom session id
            let rnSessionId = UUID().uuidString
            posthog.getSessionManager()?.setSessionId(rnSessionId)

            var newSessionId = posthog.getSessionManager()?.getSessionId()

            #expect(newSessionId == rnSessionId)

            posthog.getSessionManager()?.endSession()

            newSessionId = posthog.getSessionManager()?.getSessionId()

            #expect(newSessionId == rnSessionId)
        }

        @Test("Session id is NOT rotated when resetSession() is called")
        func sessionNotRotatedWhenResetSessionCalled() throws {
            let mockNow = MockDate()
            now = { mockNow.date }

            // RN sets custom session id
            let rnSessionId = UUID().uuidString
            posthog.getSessionManager()?.setSessionId(rnSessionId)

            var newSessionId = posthog.getSessionManager()?.getSessionId()

            #expect(newSessionId == rnSessionId)

            posthog.getSessionManager()?.resetSession()

            newSessionId = posthog.getSessionManager()?.getSessionId()

            #expect(newSessionId == rnSessionId)
        }
    }
}
