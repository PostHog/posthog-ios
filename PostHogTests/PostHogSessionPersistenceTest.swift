//
//  PostHogSessionPersistenceTest.swift
//  PostHog
//
//  Created by PostHog on 11/09/2026.
//

import Foundation
@testable import PostHog
import Testing

@Suite(.serialized, .resetsGlobalState)
struct PostHogSessionPersistenceTest {
    let mockAppLifecycle: MockApplicationLifecyclePublisher

    init() {
        mockAppLifecycle = MockApplicationLifecyclePublisher()
        mockAppLifecycle.isInBackground = false
        DI.main.appLifecyclePublisher = mockAppLifecycle

        // important!
        deleteSafely(applicationSupportDirectoryURL())
    }

    private func getConfig() -> PostHogConfig {
        PostHogConfig(projectToken: "test_session_persistence_\(UUID().uuidString)")
    }

    /// A new manager on its own storage instance stands in for the next process launch.
    private func launch(_ config: PostHogConfig) -> PostHogSessionManager {
        let manager = PostHogSessionManager()
        manager.setup(config: config, storage: PostHogStorage(config))
        return manager
    }

    @Test("Session id is restored on relaunch when the app was away for less than 30 minutes")
    func restoresSessionAfterShortRelaunch() async throws {
        try await withMockedClock { clock in
            let config = getConfig()

            let first = launch(config)
            first.startSession()
            let sessionId = try #require(first.getSessionId(readOnly: true))

            clock.date.addTimeInterval(20) // user comes back 20 seconds later

            let second = launch(config)
            second.startSession()

            #expect(second.getSessionId(readOnly: true) == sessionId)
        }
    }

    @Test("Session id is not restored on relaunch after 30 minutes of inactivity")
    func doesNotRestoreSessionPastIdleWindow() async throws {
        try await withMockedClock { clock in
            let config = getConfig()

            let first = launch(config)
            first.startSession()
            let sessionId = try #require(first.getSessionId(readOnly: true))

            clock.date.addTimeInterval(60 * 31)

            let second = launch(config)
            second.startSession()

            let newSessionId = try #require(second.getSessionId(readOnly: true))
            #expect(newSessionId != sessionId)
        }
    }

    @Test("Session id is not restored on relaunch past the maximum session length")
    func doesNotRestoreSessionPastMaximumLength() async throws {
        try await withMockedClock { clock in
            let config = getConfig()

            let first = launch(config)
            first.startSession()
            let sessionId = try #require(first.getSessionId(readOnly: true))

            // Keep the session alive for more than 24 hours, marking activity often enough
            // that the idle window never expires.
            for _ in 0 ..< 58 {
                clock.date.addTimeInterval(60 * 25)
                first.touchSession()
            }

            let second = launch(config)
            second.startSession()

            let newSessionId = try #require(second.getSessionId(readOnly: true))
            #expect(newSessionId != sessionId)
        }
    }

    @Test("startSession() keeps a live session instead of rotating it")
    func startSessionKeepsLiveSession() throws {
        let manager = launch(getConfig())
        manager.startSession()
        let sessionId = try #require(manager.getSessionId(readOnly: true))

        manager.startSession()

        #expect(manager.getSessionId(readOnly: true) == sessionId)
    }

    @Test("startSession() replaces a session that is past the idle window")
    func startSessionReplacesIdleSession() async throws {
        try await withMockedClock { clock in
            let manager = launch(getConfig())
            manager.startSession()
            let sessionId = try #require(manager.getSessionId(readOnly: true))

            clock.date.addTimeInterval(60 * 31) // no activity for 31 minutes

            manager.startSession()

            #expect(manager.getSessionId(readOnly: true) != sessionId)
        }
    }

    @Test("startSession() replaces a session that is past the maximum length")
    func startSessionReplacesSessionPastMaximumLength() async throws {
        try await withMockedClock { clock in
            let manager = launch(getConfig())
            manager.startSession()
            let sessionId = try #require(manager.getSessionId(readOnly: true))

            // stay active, so only the 24 hour maximum can expire this session
            for _ in 0 ..< 50 {
                clock.date.addTimeInterval(60 * 29)
                manager.touchSession()
            }

            manager.startSession()

            #expect(manager.getSessionId(readOnly: true) != sessionId)
        }
    }

    @Test("endSession() drops the persisted session so the next launch starts fresh")
    func endSessionDropsPersistedSession() throws {
        let config = getConfig()

        let first = launch(config)
        first.startSession()
        try #require(first.getSessionId(readOnly: true) != nil)
        first.endSession()

        #expect(launch(config).getSessionId(readOnly: true) == nil)
    }

    @Test("A second SDK setup on the same token keeps the current session id")
    func secondSetupKeepsSessionId() async throws {
        try await withMockedClock { clock in
            let token = "test_session_persistence_\(UUID().uuidString)"
            func getSdkConfig() -> PostHogConfig {
                let config = PostHogConfig(projectToken: token)
                config.preloadFeatureFlags = false
                config.sendFeatureFlagEvent = false
                config.captureApplicationLifecycleEvents = false
                config.disableReachabilityForTesting = true
                config.disableQueueTimerForTesting = true
                return config
            }

            let first = PostHogSDK.with(getSdkConfig())
            let sessionId = try #require(first.getSessionId())

            clock.date.addTimeInterval(20)

            let second = PostHogSDK.with(getSdkConfig())
            #expect(second.getSessionId() == sessionId)

            first.close()
            second.close()
        }
    }
}
