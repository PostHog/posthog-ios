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

        private func getSut(sessionReplay: Bool = false) -> PostHogSDK {
            let config = PostHogConfig(projectToken: UUID().uuidString, host: "http://localhost:9001")
            config.sessionReplay = sessionReplay
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
            let storageURL = applicationSupportDirectoryURL().appendingPathComponent(sut.config.projectToken)
            defer {
                sut.close()
                deleteSafely(storageURL)
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
            let storageURL = applicationSupportDirectoryURL().appendingPathComponent(sut.config.projectToken)
            defer {
                sut.close()
                deleteSafely(storageURL)
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

        @Test("Opt-in restarts session replay in a new session")
        func optInRestartsReplayInNewSession() async throws {
            let sut = getSut(sessionReplay: true)
            let storageURL = applicationSupportDirectoryURL().appendingPathComponent(sut.config.projectToken)
            defer {
                sut.close()
                deleteSafely(storageURL)
            }
            #expect(sut.isSessionReplayActive())
            let sessionId = sut.getSessionId()

            sut.optOut()
            sut.optIn()

            #expect(sut.isSessionReplayActive())
            #expect(sut.getSessionId() != sessionId)
        }

        @Test("Opt-in does not restart session replay the app stopped")
        func optInKeepsStoppedReplayStopped() async throws {
            let sut = getSut(sessionReplay: true)
            let storageURL = applicationSupportDirectoryURL().appendingPathComponent(sut.config.projectToken)
            defer {
                sut.close()
                deleteSafely(storageURL)
            }
            sut.stopSessionRecording()

            sut.optOut()
            sut.optIn()

            #expect(!sut.isSessionReplayActive())
        }

        @Test("Opt-in after close() and setup() ignores a stop from the earlier run")
        func optInAfterReuseStartsReplay() async throws {
            let sut = getSut(sessionReplay: true)
            let storageURL = applicationSupportDirectoryURL().appendingPathComponent(sut.config.projectToken)
            defer {
                sut.close()
                deleteSafely(storageURL)
            }
            let config = sut.config
            sut.stopSessionRecording()
            sut.optOut()
            sut.close()

            sut.setup(config)
            sut.optIn()

            #expect(sut.isSessionReplayActive())
        }
    }
#endif
