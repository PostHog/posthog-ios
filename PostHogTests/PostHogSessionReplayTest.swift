#if os(iOS)
    @testable import PostHog
    import Testing

    @Suite("Session Replay tests", .serialized)
    class PostHogSessionReplayTests: PostHogSDKBaseTest {
        private func getSut(
            sessionReplay: Bool
        ) -> PostHogSDK {
            let config = makeConfig()
            config.sessionReplay = sessionReplay
            return makeSDK(config: config)
        }

        @Test("Session replay can be manually started when disabled in config")
        func manualSessionReplayStart() async throws {
            // Setup SDK with session replay disabled
            let sut = getSut(sessionReplay: false)

            // Initially session replay should be inactive
            #expect(sut.getReplayIntegration() == nil)

            // Manually start session replay
            sut.startSessionRecording()

            // Session replay should now be active
            #expect(sut.getReplayIntegration() != nil)

            sut.reset()
        }

        @Test("Session replay can be toggled multiple times")
        func sessionReplayToggle() async throws {
            // Setup SDK with session replay disabled
            let sut = getSut(sessionReplay: false)

            // Initially session replay should be inactive
            #expect(sut.getReplayIntegration() == nil)

            // Start session replay
            sut.startSessionRecording()
            #expect(sut.getReplayIntegration() != nil)

            // Stop session replay
            sut.stopSessionRecording()
            sut.optOut()

            #expect(sut.getReplayIntegration() == nil)

            // Start again
            sut.optIn()
            sut.startSessionRecording()
            #expect(sut.getReplayIntegration() != nil)

            sut.reset()
        }
    }
#endif
