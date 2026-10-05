//
//  PostHogSessionManagerTest.swift
//  PostHog
//
//  Created by Yiannis Josephides on 16/12/2024.
//

import Foundation
@testable import PostHog
import Testing

@Suite(.serialized, .resetsGlobalState)
enum PostHogSessionManagerTest {
    @Suite("Test session id rotation logic")
    final class SessionRotation {
        let mockAppLifecycle: MockApplicationLifecyclePublisher
        private var sdks: [PostHogSDK] = []

        init() {
            mockAppLifecycle = MockApplicationLifecyclePublisher()
            DI.main.appLifecyclePublisher = mockAppLifecycle
        }

        deinit {
            for sdk in sdks {
                let storage = PostHogStorage(sdk.config)
                sdk.close()
                deleteSafely(storage.appFolderUrl)
            }
        }

        func getSut() -> PostHogSDK {
            let config = PostHogConfig(projectToken: UUID().uuidString)
            config.captureApplicationLifecycleEvents = false
            config.disableRemoteConfigForTesting = true
            config.preloadFeatureFlags = false
            config.disableQueueTimerForTesting = true
            let sdk = PostHogSDK.with(config)
            sdks.append(sdk)
            return sdk
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
    class PostHogSDKEvents {
        let mockAppLifecycle: MockApplicationLifecyclePublisher
        var server: MockPostHogServer!
        private var cleanupJobs = [() -> Void]()

        init() {
            PostHogAppLifeCycleIntegration.clearInstalls()

            mockAppLifecycle = MockApplicationLifecyclePublisher()
            DI.main.appLifecyclePublisher = mockAppLifecycle

            server = MockPostHogServer()
            server.start()
        }

        deinit {
            cleanupJobs.forEach { $0() }
            now = { Date() }
            server.stop()
            server = nil
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
            let config = PostHogConfig(projectToken: UUID().uuidString, host: "http://localhost:9001")
            config.flushAt = flushAt
            config.preloadFeatureFlags = preloadFeatureFlags
            config.sendFeatureFlagEvent = sendFeatureFlagEvent
            config.disableReachabilityForTesting = true
            config.disableQueueTimerForTesting = true
            config.disableFlushOnBackgroundForTesting = true
            config.captureApplicationLifecycleEvents = captureApplicationLifecycleEvents
            config.captureScreenViews = false
            config.optOut = optOut
            config.propertiesSanitizer = propertiesSanitizer
            config.personProfiles = personProfiles
            config.maxBatchSize = max(flushAt, config.maxBatchSize)
            server.batchProjectToken = config.projectToken
            let sdk = PostHogSDK.with(config)
            let storage = PostHogStorage(config)
            cleanupJobs.append {
                sdk.close()
                deleteSafely(storage.appFolderUrl)
            }
            return sdk
        }

        @Test("Clears $session_id after 30 mins of background inactivity")
        func sessionClearedAfterBackgroundInactivity() async throws {
            let sut = getSut(flushAt: 2)
            let mockNow = MockDate()
            now = { mockNow.date }

            // Clear any stale batch requests from previous tests' PostHogSDK instances
            server.reset(batchCount: 1)

            defer {
                sut.reset()
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

            // Clear any stale batch requests from previous tests' PostHogSDK instances
            server.reset(batchCount: 1)

            defer {
                sut.reset()
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

            sut.reset()
            sut.close()
        }

        @Test("$sdk_debug_session_start describes the rotated session on the event that rotates it")
        func debugSessionKeysDescribeRotatedSession() async throws {
            let sut = getSut(flushAt: 2)
            let mockNow = MockDate()
            now = { mockNow.date }

            server.reset(batchCount: 1)

            defer {
                sut.reset()
                sut.close()
            }

            mockAppLifecycle.simulateAppDidFinishLaunching()
            mockAppLifecycle.simulateAppDidBecomeActive()

            sut.getSessionManager()?.touchSession()
            sut.screen("first")

            mockNow.date.addTimeInterval(60 * 31) // +31 mins: this capture rotates the session
            sut.screen("after 31 mins")

            let events = try await getServerEvents(server)
            try #require(events.count == 2)

            let start1 = try #require(events[0].properties["$sdk_debug_session_start"] as? Int64)
            let start2 = try #require(events[1].properties["$sdk_debug_session_start"] as? Int64)

            // Regression: the debug snapshot used to run before getSessionId(at:) rotated, so the
            // rotating event carried the new $session_id with the previous session's start.
            #expect(start2 != start1)
            #expect(start2 == Int64(mockNow.date.timeIntervalSince1970 * 1000))
        }

        @Test("a custom event carries the required keys but none of the optional replay debug bundle")
        func customEventCarriesNoReplayDebugBundle() async throws {
            let sut = getSut()

            server.reset(batchCount: 1)

            defer {
                sut.reset()
                sut.close()
            }

            sut.getSessionManager()?.touchSession()
            sut.capture("custom event")

            let events = try await getServerEvents(server)
            try #require(events.count == 1)

            let properties = events[0].properties
            #expect(properties["$recording_status"] != nil)
            #expect(properties["$sdk_debug_pending_queue_size"] != nil)
            #expect(properties["$sdk_debug_session_start"] == nil)
            #expect(properties["$sdk_debug_replay_capture_mode"] == nil)
            #expect(properties["$sdk_debug_replay_flush_hold_reason"] == nil)
            #expect(properties["$sdk_debug_replay_pending_trigger_conditions"] == nil)
        }

        @Test("the optional replay debug bundle is attached at most once every 30 seconds; required keys stay on every event")
        func replayDebugBundleIsThrottled() async throws {
            let sut = getSut(flushAt: 3)
            let mockNow = MockDate()
            now = { mockNow.date }

            server.reset(batchCount: 1)

            defer {
                sut.reset()
                sut.close()
            }

            sut.getSessionManager()?.touchSession()
            sut.screen("first")

            mockNow.date.addTimeInterval(29)
            sut.screen("inside the window")

            mockNow.date.addTimeInterval(1) // 30s after the first, so the window has elapsed
            sut.screen("at the window edge")

            let events = try await getServerEvents(server)
            try #require(events.count == 3)

            for event in events {
                #expect(event.properties["$recording_status"] != nil)
            }
            #expect(events[0].properties["$sdk_debug_session_start"] != nil)
            #expect(events[1].properties["$sdk_debug_session_start"] == nil)
            #expect(events[2].properties["$sdk_debug_session_start"] != nil)
        }

        @Test("a far-future eligible capture doesn't suppress the optional bundle once wall clock catches up")
        func replayDebugBundleFollowsWallClockNotEventTimestamp() async throws {
            let sut = getSut(flushAt: 2)
            let mockNow = MockDate()
            now = { mockNow.date }

            server.reset(batchCount: 1)

            defer {
                sut.reset()
                sut.close()
            }

            sut.getSessionManager()?.touchSession()
            sut.capture("$future", timestamp: mockNow.date.addingTimeInterval(60 * 60))

            mockNow.date.addTimeInterval(30)
            sut.capture("$after", timestamp: mockNow.date)

            let events = try await getServerEvents(server)
            try #require(events.count == 2)

            #expect(events[0].properties["$sdk_debug_session_start"] != nil)
            #expect(events[1].properties["$sdk_debug_session_start"] != nil)
        }

        @Test("the crash-context snapshot always carries the bundle and never arms the window")
        func readOnlyContextSnapshotBypassesGateAndThrottle() async throws {
            let sut = getSut()

            server.reset(batchCount: 1)

            defer {
                sut.reset()
                sut.close()
            }

            sut.getSessionManager()?.touchSession()

            let lock = NSLock()
            var snapshots: [[String: Any]] = []
            let token = sut.onEventContextChanged.subscribe { context in
                lock.withLock { snapshots.append(context["event_properties"] as? [String: Any] ?? [:]) }
            }

            sut.register(["first": 1])
            sut.register(["second": 2])

            let captured = lock.withLock { snapshots }
            try #require(captured.count >= 2)
            for snapshot in captured {
                #expect(snapshot["$recording_status"] != nil)
                #expect(snapshot["$sdk_debug_session_start"] != nil)
                #expect(snapshot["$sdk_debug_pending_queue_size"] == nil)
            }

            // The read-only builds never armed the window, so the first captured event still attaches.
            sut.screen("first")

            let events = try await getServerEvents(server)
            try #require(events.count == 1)
            #expect(events[0].properties["$recording_status"] != nil)

            withExtendedLifetime(token) {}
        }

        @Test("an event dropped by beforeSend does not consume the throttle window")
        func beforeSendDroppedEventDoesNotArmWindow() async throws {
            let sut = getSut()
            let mockNow = MockDate()
            now = { mockNow.date }

            server.reset(batchCount: 1)

            defer {
                sut.reset()
                sut.close()
            }

            sut.getSessionManager()?.touchSession()
            sut.config.setBeforeSend { $0.event == "$dropped" ? nil : $0 }
            // Dropped while the window is open, which is when it could have armed it.
            sut.capture("$dropped")

            mockNow.date.addTimeInterval(1)
            sut.capture("$after")

            let events = try await getServerEvents(server)
            try #require(events.count == 1)

            #expect(events[0].event == "$after")
            #expect(events[0].properties["$sdk_debug_session_start"] != nil)
        }

        @Test("an event that carried no bundle does not consume the window when the interval elapses mid-capture")
        func eventWithoutBundleDoesNotConsumeWindow() async throws {
            let sut = getSut(flushAt: 3)
            let mockNow = MockDate()
            now = { mockNow.date }

            server.reset(batchCount: 1)

            defer {
                sut.reset()
                sut.close()
            }

            sut.getSessionManager()?.touchSession()
            sut.capture("$first")

            mockNow.date.addTimeInterval(29)
            // beforeSend runs after the properties are built, so this crosses the interval boundary
            // between the claim and the commit.
            sut.config.setBeforeSend { event in
                if event.event == "$inside" { mockNow.date.addTimeInterval(6) }
                return event
            }
            sut.capture("$inside")

            sut.config.setBeforeSend { $0 }
            mockNow.date.addTimeInterval(1)
            sut.capture("$after")

            let events = try await getServerEvents(server)
            try #require(events.count == 3)

            #expect(events[0].properties["$sdk_debug_session_start"] != nil)
            #expect(events[1].properties["$sdk_debug_session_start"] == nil)
            #expect(events[2].properties["$sdk_debug_session_start"] != nil)
        }

        @Test("a deduplicated identify() $set does not arm the throttle window")
        func deduplicatedSetDoesNotArmWindow() async throws {
            let sut = getSut(flushAt: 3)
            let mockNow = MockDate()
            now = { mockNow.date }

            server.reset(batchCount: 1)

            defer {
                sut.reset()
                sut.close()
            }

            sut.getSessionManager()?.touchSession()

            sut.identify("user_dedup")

            mockNow.date.addTimeInterval(31)
            sut.identify("user_dedup", userProperties: ["name": "John"])

            mockNow.date.addTimeInterval(31)
            // Same properties again: deduplicated, never queued.
            sut.identify("user_dedup", userProperties: ["name": "John"])

            sut.capture("$after")

            let events = try await getServerEvents(server)
            try #require(events.count == 3)

            #expect(events[0].event == "$identify")
            #expect(events[1].event == "$set")
            #expect(events[2].event == "$after")
            #expect(events[2].properties["$sdk_debug_session_start"] != nil)
        }

        @Test("a custom event captured while the window is open does not arm it")
        func customEventDoesNotArmWindow() async throws {
            let sut = getSut(flushAt: 2)
            let mockNow = MockDate()
            now = { mockNow.date }

            server.reset(batchCount: 1)

            defer {
                sut.reset()
                sut.close()
            }

            sut.getSessionManager()?.touchSession()
            sut.capture("custom event")

            mockNow.date.addTimeInterval(1)
            sut.capture("$eligible")

            let events = try await getServerEvents(server)
            try #require(events.count == 2)

            #expect(events[1].properties["$sdk_debug_session_start"] != nil)
        }

        @Test("an eligible event captured from inside beforeSend does not also carry the optional bundle")
        func captureInsideBeforeSendDoesNotDoubleClaim() async throws {
            let sut = getSut(flushAt: 2)
            let mockNow = MockDate()
            now = { mockNow.date }

            server.reset(batchCount: 1)

            defer {
                sut.reset()
                sut.close()
            }

            sut.getSessionManager()?.touchSession()
            sut.config.setBeforeSend { event in
                if event.event == "$outer" { sut.capture("$inner") }
                return event
            }
            sut.capture("$outer")

            let events = try await getServerEvents(server)
            try #require(events.count == 2)

            let carriers = events.filter { $0.properties["$sdk_debug_session_start"] != nil }
            #expect(carriers.count == 1)
            #expect(carriers.first?.event == "$outer")
        }

        @Test("an eligible event renamed by beforeSend still carries the bundle and consumes the window")
        func renamedEligibleEventConsumesWindow() async throws {
            let sut = getSut(flushAt: 2)
            let mockNow = MockDate()
            now = { mockNow.date }

            server.reset(batchCount: 1)

            defer {
                sut.reset()
                sut.close()
            }

            sut.getSessionManager()?.touchSession()
            sut.config.setBeforeSend { event in
                if event.event == "$renamed" { event.event = "custom name" }
                return event
            }
            sut.capture("$renamed")

            mockNow.date.addTimeInterval(1)
            sut.capture("$after")

            let events = try await getServerEvents(server)
            try #require(events.count == 2)

            #expect(events[0].event == "custom name")
            #expect(events[0].properties["$sdk_debug_session_start"] != nil)
            #expect(events[1].properties["$sdk_debug_session_start"] == nil)
        }

        @Test("a custom event renamed to an eligible name by beforeSend carries no bundle and does not consume the window")
        func customEventRenamedToEligibleDoesNotConsumeWindow() async throws {
            let sut = getSut(flushAt: 2)
            let mockNow = MockDate()
            now = { mockNow.date }

            server.reset(batchCount: 1)

            defer {
                sut.reset()
                sut.close()
            }

            sut.getSessionManager()?.touchSession()
            sut.config.setBeforeSend { event in
                if event.event == "custom name" { event.event = "$renamed" }
                return event
            }
            sut.capture("custom name")

            mockNow.date.addTimeInterval(1)
            sut.capture("$after")

            let events = try await getServerEvents(server)
            try #require(events.count == 2)

            #expect(events[0].event == "$renamed")
            #expect(events[0].properties["$sdk_debug_session_start"] == nil)
            #expect(events[1].properties["$sdk_debug_session_start"] != nil)
        }

        @Test("the window starts when the event is accepted, not while beforeSend is running")
        func windowStartsAtAcceptance() async throws {
            let sut = getSut(flushAt: 2)
            let mockNow = MockDate()
            now = { mockNow.date }

            server.reset(batchCount: 1)

            defer {
                sut.reset()
                sut.close()
            }

            sut.getSessionManager()?.touchSession()
            sut.config.setBeforeSend { event in
                if event.event == "$slow" { mockNow.date.addTimeInterval(31) }
                return event
            }
            sut.capture("$slow")
            sut.capture("$next")

            let events = try await getServerEvents(server)
            try #require(events.count == 2)

            #expect(events[0].properties["$sdk_debug_session_start"] != nil)
            #expect(events[1].properties["$sdk_debug_session_start"] == nil)
        }

        @Test("a claim stays reserved while its capture is still inside beforeSend, however long that takes")
        func outstandingClaimDoesNotExpire() async throws {
            let sut = getSut(flushAt: 2)
            let mockNow = MockDate()
            now = { mockNow.date }

            server.reset(batchCount: 1)

            defer {
                sut.reset()
                sut.close()
            }

            sut.getSessionManager()?.touchSession()
            sut.config.setBeforeSend { event in
                if event.event == "$slow" {
                    mockNow.date.addTimeInterval(31)
                    sut.capture("$inner")
                }
                return event
            }
            sut.capture("$slow")

            let events = try await getServerEvents(server)
            try #require(events.count == 2)

            let carriers = events.filter { $0.properties["$sdk_debug_session_start"] != nil }
            #expect(carriers.count == 1)
            #expect(carriers.first?.event == "$slow")
        }

        @Test("a claimer dropped by beforeSend releases the claim so the next eligible event gets the bundle immediately")
        func droppedClaimerReleasesClaim() async throws {
            let sut = getSut()
            let mockNow = MockDate()
            now = { mockNow.date }

            server.reset(batchCount: 1)

            defer {
                sut.reset()
                sut.close()
            }

            sut.getSessionManager()?.touchSession()
            sut.config.setBeforeSend { $0.event == "$dropped" ? nil : $0 }
            sut.capture("$dropped")
            sut.capture("$after")

            let events = try await getServerEvents(server)
            try #require(events.count == 1)

            #expect(events[0].event == "$after")
            #expect(events[0].properties["$sdk_debug_session_start"] != nil)
        }

        @Test("the internal claim marker never reaches a queued event")
        func claimMarkerNeverReachesQueuedEvent() async throws {
            let sut = getSut()

            server.reset(batchCount: 1)

            defer {
                sut.reset()
                sut.close()
            }

            sut.getSessionManager()?.touchSession()
            sut.capture("$eligible")

            let events = try await getServerEvents(server)
            try #require(events.count == 1)

            #expect(events[0].properties["$__replay_debug_claim"] == nil)
        }

        @Test("Rotates $session_id after max session length of 24 hours")
        func sessionRotatedAfterMaxSessionLength() async throws {
            let sut = getSut(flushAt: 52)
            let mockNow = MockDate()
            var compoundedTime: TimeInterval = 0
            now = { mockNow.date }

            // Clear any stale batch requests from previous tests' PostHogSDK instances
            server.reset(batchCount: 1)

            defer {
                sut.reset()
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
                token = publisher.onDidBecomeActive.subscribe {
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

            #expect(sut.onDidBecomeActive.subscriberCount == 5)
            registrations.removeFirst(2)
            #expect(sut.onDidBecomeActive.subscriberCount == 3)
            registrations.removeAll()
            #expect(sut.onDidBecomeActive.subscriberCount == 0)
        }
    }

    @Suite("Test React Native session management")
    final class ReactNativeTests {
        let mockAppLifecycle: MockApplicationLifecyclePublisher
        let posthog: PostHogSDK

        init() {
            postHogSdkName = "posthog-react-native"
            mockAppLifecycle = MockApplicationLifecyclePublisher()
            DI.main.appLifecyclePublisher = mockAppLifecycle
            let config = PostHogConfig(projectToken: "test_project_token")
            posthog = PostHogSDK.with(config)
        }

        deinit {
            // Close the suite-held SDK so its integrations/queues don't linger into other suites.
            posthog.close()
            // Restore globals this suite mutates so it doesn't leak RN mode / a mocked clock into the
            // other serialized suites (a struct can't deinit, hence the class).
            postHogSdkName = postHogiOSSdkName
            now = { Date() }
            DI.main.appLifecyclePublisher = ApplicationLifecyclePublisher.shared
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

    @Suite("setup() seeds isAppInBackground from current application state")
    struct AppStateSeeding {
        let mockAppLifecycle: MockApplicationLifecyclePublisher

        init() {
            mockAppLifecycle = MockApplicationLifecyclePublisher()
            DI.main.appLifecyclePublisher = mockAppLifecycle
        }

        @Test("late setup() with foreground app: snapshot reads false, not the initial true")
        func seedsForegroundOnLateSetup() throws {
            // Regression: without the seed, a late setup() would stay at
            // the defensive default (`true`) until the next state change.
            mockAppLifecycle.isInBackground = false

            let config = PostHogConfig(projectToken: "test_seed_fg_\(UUID().uuidString)")
            let sdk = PostHogSDK.with(config)
            defer { sdk.close() }

            #expect(sdk.getSessionManager()?.isAppInBackgroundSnapshot == false)
        }

        @Test("setup() with backgrounded app: snapshot reads true")
        func seedsBackgroundOnSetup() throws {
            mockAppLifecycle.isInBackground = true

            let config = PostHogConfig(projectToken: "test_seed_bg_\(UUID().uuidString)")
            let sdk = PostHogSDK.with(config)
            defer { sdk.close() }

            #expect(sdk.getSessionManager()?.isAppInBackgroundSnapshot == true)
        }
    }
}
