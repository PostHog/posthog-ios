#if os(iOS)
    import Foundation
    @testable import PostHog
    import Testing

    @Suite("Session Replay tests", .serialized)
    class PostHogSessionReplayTests {
        let server: MockPostHogServer

        init() {
            server = MockPostHogServer()
            server.start()
        }

        deinit {
            server.stop()
        }

        private func getSut() -> PostHogSDK {
            let config = PostHogConfig(projectToken: UUID().uuidString, host: "http://localhost:9001")
            config.sessionReplay = false
            config.disableReachabilityForTesting = true
            config.disableQueueTimerForTesting = true
            config.disableFlushOnBackgroundForTesting = true
            config.disableRemoteConfigForTesting = true
            config.preloadFeatureFlags = false
            PostHogStorage(config).setDictionary(forKey: .remoteConfig, contents: ["sessionRecording": ["endpoint": "/s/"]])
            return PostHogSDK.with(config)
        }

        @Test("Session replay can be manually started when disabled in config")
        func manualSessionReplayStart() async throws {
            let sut = getSut()
            defer {
                sut.close()
                deleteSafely(applicationSupportDirectoryURL().appendingPathComponent(sut.config.projectToken))
            }
            #expect(sut.getReplayIntegration() == nil)
            #expect(!sut.isSessionReplayActive())

            sut.startSessionRecording()

            #expect(sut.getReplayIntegration() != nil)
            #expect(sut.isSessionReplayActive())
        }

        @Test("Session replay can be toggled multiple times")
        func sessionReplayToggle() async throws {
            let sut = getSut()
            defer {
                sut.close()
                deleteSafely(applicationSupportDirectoryURL().appendingPathComponent(sut.config.projectToken))
            }
            #expect(sut.getReplayIntegration() == nil)

            sut.startSessionRecording()
            #expect(sut.isSessionReplayActive())
            sut.stopSessionRecording()
            #expect(!sut.isSessionReplayActive())
            #expect(sut.getReplayIntegration() != nil)
            sut.startSessionRecording()
            #expect(sut.isSessionReplayActive())

            sut.optOut()
            #expect(sut.getReplayIntegration() == nil)
            #expect(!sut.isSessionReplayActive())
            sut.optIn()
            sut.startSessionRecording()
            #expect(sut.isSessionReplayActive())
        }
    }
#endif
