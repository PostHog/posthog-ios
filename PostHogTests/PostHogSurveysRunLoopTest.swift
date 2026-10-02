#if os(iOS)
    import Foundation
    @testable import PostHog
    import Testing
    import UIKit

    /// Comparing the live `UIView.layoutSublayers(of:)` IMP before and after setup proves nothing the
    /// SDK starts joins that call chain, regardless of what another suite may have left swizzled.
    /// Nothing in the SDK swizzles that method any more, so this now guards against one being reintroduced.
    @Suite("Surveys Run Loop Opportunities", .serialized)
    final class PostHogSurveysRunLoopTest {
        let server: MockPostHogServer

        init() {
            server = MockPostHogServer()
            server.start()
        }

        deinit {
            server.stop()
        }

        private var layoutImplementation: IMP? {
            class_getMethodImplementation(UIView.self, #selector(UIView.layoutSublayers(of:)))
        }

        private func getSut(sessionReplay: Bool) -> PostHogSDK {
            let config = PostHogConfig(projectToken: UUID().uuidString, host: "http://localhost:9090")
            config._surveys = true
            config.sessionReplay = sessionReplay
            config.disableReachabilityForTesting = true
            config.disableQueueTimerForTesting = true
            config.preloadFeatureFlags = false
            config.disableRemoteConfigForTesting = true
            config.captureApplicationLifecycleEvents = false

            let storage = PostHogStorage(config)
            storage.reset()
            if sessionReplay {
                storage.setDictionary(forKey: .remoteConfig, contents: ["sessionRecording": ["endpoint": "/s/"]])
            }

            PostHogSurveyIntegration.clearInstalls()
            PostHogReplayIntegration.clearInstalls()
            return PostHogSDK.with(config)
        }

        @MainActor
        @Test("surveys take their opportunities from the run loop, not from a layout swizzle")
        func surveysDoNotSwizzleLayout() async throws {
            let before = try #require(layoutImplementation)

            let sut = getSut(sessionReplay: false)
            defer { sut.close() }
            await drainMain()

            #expect(layoutImplementation == before)
            #expect(DI.main.runLoopPublisher.isObserving)
        }

        @MainActor
        @Test("replay and surveys together still leave the layout implementation alone")
        func replayAndSurveysDoNotSwizzleLayout() async throws {
            let before = try #require(layoutImplementation)

            let sut = getSut(sessionReplay: true)
            defer { sut.close() }
            let replay = try #require(sut.getReplayIntegration())
            try #require(replay.isActive())
            await drainMain()

            #expect(layoutImplementation == before)
            #expect(DI.main.runLoopPublisher.isObserving)
        }
    }
#endif
