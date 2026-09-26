#if os(iOS)
    import Foundation
    @testable import PostHog
    import Testing

    @Suite("Session Replay Manual Mode", .serialized)
    class PostHogSessionReplayManualModeTests {
        let server: MockPostHogServer

        init() {
            server = MockPostHogServer()
            server.start()
        }

        deinit {
            server.stop()
        }

        private func getSut(
            sessionReplay: Bool,
            eventTriggers: [String]? = nil,
            sampleRate: Double? = nil
        ) -> PostHogSDK {
            // Unique token per SUT so the disk-backed replay queue is isolated across tests in this suite.
            let config = PostHogConfig(projectToken: UUID().uuidString, host: "http://localhost:9001")
            config.sessionReplay = sessionReplay
            config.disableReachabilityForTesting = true
            config.disableQueueTimerForTesting = true
            config.preloadFeatureFlags = false
            // Drive recording config from the seeded .remoteConfig below, not the async /config fetch,
            // so the tests stay deterministic and independent of global stub state from other suites.
            config.disableRemoteConfigForTesting = true

            let storage = PostHogStorage(config)
            var sessionRecording: [String: Any] = ["endpoint": "/s/"]
            if let eventTriggers {
                sessionRecording["eventTriggers"] = eventTriggers
            }
            if let sampleRate {
                sessionRecording["sampleRate"] = sampleRate
            }
            storage.setDictionary(forKey: .remoteConfig, contents: ["sessionRecording": sessionRecording])

            // Reset the static install flag a prior replay suite may have left set, so this SUT installs
            // a fresh integration rather than no-opping onto a stale one.
            PostHogReplayIntegration.clearInstalls()

            return PostHogSDK.with(config)
        }

        // MARK: - Manual mode gate

        @Test("Manual mode with no explicit start never installs or records")
        func manualModeWithoutExplicitStartStaysInactive() async throws {
            let sut = getSut(sessionReplay: false)
            defer { sut.close() }

            #expect(sut.getReplayIntegration() == nil)
            #expect(sut.isSessionReplayActive() == false)
        }

        @Test("Explicit start records in manual mode")
        func explicitStartRecordsInManualMode() async throws {
            let sut = getSut(sessionReplay: false)
            defer { sut.close() }

            sut.startSessionRecording()

            let integration = sut.getReplayIntegration()
            #expect(integration != nil)
            #expect(integration?.isActive() == true)
        }

        @Test("Remote config load after explicit stop does not restart manual recording")
        func remoteConfigLoadAfterExplicitStopDoesNotRestart() async throws {
            let sut = getSut(sessionReplay: false)
            defer { sut.close() }

            sut.startSessionRecording()
            let integration = try #require(sut.getReplayIntegration())
            #expect(integration.isActive() == true)

            sut.stopSessionRecording()
            #expect(integration.isActive() == false)

            integration.applyRemoteConfig(remoteConfig: ["sessionRecording": ["endpoint": "/s/"]])
            #expect(integration.isActive() == false)
        }

        @Test("Matched trigger after explicit stop does not restart manual recording")
        func matchedTriggerAfterExplicitStopDoesNotRestart() async throws {
            let sut = getSut(sessionReplay: false, eventTriggers: ["purchase_completed"])
            defer { sut.close() }

            sut.startSessionRecording()
            let integration = try #require(sut.getReplayIntegration())
            #expect(integration.isActive() == false)

            sut.capture("purchase_completed")
            #expect(integration.isActive() == true)

            sut.stopSessionRecording()
            #expect(integration.isActive() == false)

            sut.sessionManager.setSessionId(UUID().uuidString)
            sut.capture("purchase_completed")
            #expect(integration.isActive() == false)
        }

        @Test("Explicit stop while manual start is still deferred by a trigger clears the intent")
        func explicitStopWhileDeferredByTriggerClearsIntent() async throws {
            let sut = getSut(sessionReplay: false, eventTriggers: ["purchase_completed"])
            defer { sut.close() }

            sut.startSessionRecording()
            let integration = try #require(sut.getReplayIntegration())
            #expect(integration.isActive() == false)

            sut.stopSessionRecording()

            sut.capture("purchase_completed")
            #expect(integration.isActive() == false)
        }

        @Test("Session change after explicit stop does not restart manual recording")
        func sessionChangeAfterExplicitStopDoesNotRestart() async throws {
            let sut = getSut(sessionReplay: false)
            defer { sut.close() }

            sut.startSessionRecording()
            let integration = try #require(sut.getReplayIntegration())
            #expect(integration.isActive() == true)

            sut.stopSessionRecording()
            #expect(integration.isActive() == false)

            sut.sessionManager.setSessionId(UUID().uuidString)
            #expect(integration.isActive() == false)
        }

        @Test("Explicit start then session change keeps recording")
        func explicitStartThenSessionChangeKeepsRecording() async throws {
            let sut = getSut(sessionReplay: false)
            defer { sut.close() }

            sut.startSessionRecording()
            let integration = try #require(sut.getReplayIntegration())
            #expect(integration.isActive() == true)

            sut.sessionManager.setSessionId(UUID().uuidString)
            #expect(integration.isActive() == true)
        }

        @Test("Internal stop from sampling resumes once the condition clears, when the manual marker is set")
        func internalStopFromSamplingResumesWhenMarkerSet() async throws {
            let sut = getSut(sessionReplay: false)
            defer { sut.close() }

            sut.startSessionRecording()
            let integration = try #require(sut.getReplayIntegration())
            #expect(integration.isActive() == true)

            let remoteConfig = try #require(sut.remoteConfig)
            remoteConfig.setRecordingSampleRateForTesting(0.0)
            integration.applyRemoteConfig(remoteConfig: nil)
            #expect(integration.isActive() == false)

            remoteConfig.setRecordingSampleRateForTesting(1.0)
            integration.applyRemoteConfig(remoteConfig: nil)
            #expect(integration.isActive() == true)
        }

        @Test("Internal stop from added triggers resumes once triggers are removed, when the manual marker is set")
        func internalStopFromTriggersResumesWhenMarkerSet() async throws {
            let sut = getSut(sessionReplay: false)
            defer { sut.close() }

            sut.startSessionRecording()
            let integration = try #require(sut.getReplayIntegration())
            #expect(integration.isActive() == true)

            integration.applyRemoteConfig(remoteConfig: ["sessionRecording": ["endpoint": "/s/", "eventTriggers": ["purchase_completed"]]])
            #expect(integration.isActive() == false)

            integration.applyRemoteConfig(remoteConfig: ["sessionRecording": ["endpoint": "/s/"]])
            #expect(integration.isActive() == true)
        }

        @Test("After an explicit stop, a sampled-out then sampled-in sequence does not resume recording")
        func sampledOutThenInAfterExplicitStopDoesNotResume() async throws {
            let sut = getSut(sessionReplay: false)
            defer { sut.close() }

            sut.startSessionRecording()
            let integration = try #require(sut.getReplayIntegration())
            #expect(integration.isActive() == true)

            sut.stopSessionRecording()
            #expect(integration.isActive() == false)

            let remoteConfig = try #require(sut.remoteConfig)
            remoteConfig.setRecordingSampleRateForTesting(0.0)
            integration.applyRemoteConfig(remoteConfig: nil)
            #expect(integration.isActive() == false)

            remoteConfig.setRecordingSampleRateForTesting(1.0)
            integration.applyRemoteConfig(remoteConfig: nil)
            #expect(integration.isActive() == false)
        }

        // MARK: - Automatic mode control

        @Test("Automatic mode restarts on the next remote config load after a stop")
        func automaticModeRestartsOnNextRemoteConfigLoad() async throws {
            let sut = getSut(sessionReplay: true)
            defer { sut.close() }

            let integration = try #require(sut.getReplayIntegration())
            #expect(integration.isActive() == true)

            sut.stopSessionRecording()
            #expect(integration.isActive() == false)

            integration.applyRemoteConfig(remoteConfig: ["sessionRecording": ["endpoint": "/s/"]])
            #expect(integration.isActive() == true)
        }

        @Test("Automatic mode with triggers restarts on a matched trigger in a new session after a stop")
        func automaticModeWithTriggersRestartsOnNewSessionTrigger() async throws {
            let sut = getSut(sessionReplay: true, eventTriggers: ["purchase_completed"])
            defer { sut.close() }

            let integration = try #require(sut.getReplayIntegration())
            #expect(integration.isActive() == false)

            sut.capture("purchase_completed")
            #expect(integration.isActive() == true)

            sut.stopSessionRecording()
            #expect(integration.isActive() == false)

            sut.sessionManager.setSessionId(UUID().uuidString)
            sut.capture("purchase_completed")
            #expect(integration.isActive() == true)
        }
    }
#endif
