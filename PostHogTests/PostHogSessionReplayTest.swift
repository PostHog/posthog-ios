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

        private func getSut(
            sessionReplay: Bool = false,
            optOut: Bool = false,
            config: PostHogConfig = PostHogConfig(projectToken: UUID().uuidString, host: "http://localhost:9001")
        ) -> PostHogSDK {
            config.sessionReplay = sessionReplay
            config.optOut = optOut
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

        @Test("Opt-in ignores a stop made while opted out")
        func optInIgnoresStopWhileOptedOut() async throws {
            let sut = getSut(sessionReplay: true)
            let storageURL = applicationSupportDirectoryURL().appendingPathComponent(sut.config.projectToken)
            defer {
                sut.close()
                deleteSafely(storageURL)
            }

            sut.optOut()
            sut.stopSessionRecording()
            sut.optIn()

            #expect(sut.isSessionReplayActive())
        }

        @Test("Opt-in restarts a recording the app started itself in a new session")
        func optInRestartsManuallyStartedReplayInNewSession() async throws {
            let sut = getSut()
            let storageURL = applicationSupportDirectoryURL().appendingPathComponent(sut.config.projectToken)
            defer {
                sut.close()
                deleteSafely(storageURL)
            }
            sut.startSessionRecording()
            #expect(sut.isSessionReplayActive())
            let sessionId = sut.getSessionId()

            sut.optOut()
            sut.optIn()

            #expect(sut.isSessionReplayActive())
            #expect(sut.getSessionId() != sessionId)
        }

        @Test("Opt-in does not start replay the app never started when disabled in config")
        func optInDoesNotStartReplayNeverStarted() async throws {
            let sut = getSut()
            let storageURL = applicationSupportDirectoryURL().appendingPathComponent(sut.config.projectToken)
            defer {
                sut.close()
                deleteSafely(storageURL)
            }

            sut.optOut()
            sut.optIn()

            #expect(sut.getReplayIntegration() == nil)
            #expect(!sut.isSessionReplayActive())
        }

        @Test("Opt-in after launching opted out does not start replay disabled in config")
        func optInAfterLaunchingOptedOutDoesNotStartReplay() async throws {
            let sut = getSut(optOut: true)
            let storageURL = applicationSupportDirectoryURL().appendingPathComponent(sut.config.projectToken)
            defer {
                sut.close()
                deleteSafely(storageURL)
            }

            sut.optIn()

            #expect(sut.getReplayIntegration() == nil)
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

        @Test("A stop racing a start leaves replay intent matching the recording")
        func stopRacingStartKeepsIntentInStep() async throws {
            let config = SessionReplayObservingConfig(projectToken: UUID().uuidString, host: "http://localhost:9001")
            let sut = getSut(config: config)
            let storageURL = applicationSupportDirectoryURL().appendingPathComponent(sut.config.projectToken)
            defer {
                sut.close()
                deleteSafely(storageURL)
            }
            sut.startSessionRecording()
            sut.stopSessionRecording()

            // The replay integration reads `sessionReplay` as it starts; stop from another thread right then
            let stopDone = DispatchSemaphore(value: 0)
            config.onSessionReplayRead = {
                config.onSessionReplayRead = nil
                DispatchQueue.global().async {
                    sut.stopSessionRecording()
                    stopDone.signal()
                }
                if stopDone.wait(timeout: .now() + 0.5) == .success {
                    stopDone.signal()
                }
            }
            sut.startSessionRecording()
            #expect(stopDone.wait(timeout: .now() + 5) == .success)

            #expect(!sut.isSessionReplayActive())
            sut.optOut()
            sut.optIn()
            #expect(!sut.isSessionReplayActive())
        }
    }

    /// Runs `onSessionReplayRead` on the thread that reads `sessionReplay`, so a test can act mid-start.
    private final class SessionReplayObservingConfig: PostHogConfig {
        var onSessionReplayRead: (() -> Void)?

        override var sessionReplay: Bool {
            get {
                onSessionReplayRead?()
                return super.sessionReplay
            }
            set { super.sessionReplay = newValue }
        }
    }
#endif
