#if os(iOS)
    @testable import PostHog
    import Testing
    import Foundation

    @Suite("Session Replay Event Triggers", .serialized)
    class PostHogSessionReplayEventTriggersTests {
        let testAPIKey = "test_api_key"
        let server: MockPostHogServer

        init() {
            server = MockPostHogServer()
            server.start()
        }

        deinit {
            server.stop()
        }

        private func getSut(
            eventTriggers: [String]? = nil
        ) -> PostHogSDK {
            let config = PostHogConfig(apiKey: testAPIKey, host: "http://localhost:9001")
            config.sessionReplay = true
            config.disableReachabilityForTesting = true
            config.disableQueueTimerForTesting = true
            config.preloadFeatureFlags = false
            
            // Configure mock server for remote config
            server.returnReplay = true
            server.sessionRecordingEventTriggers = eventTriggers
            
            return PostHogSDK.with(config)
        }
        
        private func waitForRemoteConfig(_ sut: PostHogSDK) async {
            guard let remoteConfig = sut.remoteConfig else {
                return
            }
            
            var remoteConfigLoaded = false
            let token = remoteConfig.onRemoteConfigLoaded.subscribe { _ in
                remoteConfigLoaded = true
            }
            
            await withCheckedContinuation { continuation in
                let timeout = Date().addingTimeInterval(2)
                while !remoteConfigLoaded, Date() < timeout {}
                continuation.resume()
            }
            
            _ = token
        }

        // MARK: - isActive() Tests

        @Test("isActive returns true when no event triggers configured")
        func isActiveWithoutTriggers() async throws {
            let sut = getSut(eventTriggers: nil)
            await waitForRemoteConfig(sut)

            let integration = sut.getReplayIntegration()
            #expect(integration != nil)
            #expect(integration?.isActive() == true)

            sut.close()
        }

        @Test("isActive returns false when waiting for event trigger")
        func isActiveWhileWaitingForTrigger() async throws {
            let sut = getSut(eventTriggers: ["purchase_completed"])
            await waitForRemoteConfig(sut)

            let integration = sut.getReplayIntegration()
            #expect(integration != nil)
            #expect(integration?.isActive() == false)

            sut.close()
        }

        @Test("isActive returns true after trigger event is captured")
        func isActiveAfterTriggerFired() async throws {
            let sut = getSut(eventTriggers: ["purchase_completed"])
            await waitForRemoteConfig(sut)

            let integration = sut.getReplayIntegration()
            #expect(integration != nil)
            #expect(integration?.isActive() == false)

            sut.capture("purchase_completed")

            #expect(integration?.isActive() == true)

            sut.close()
        }

        // MARK: - Trigger Matching Tests

        @Test("Non-matching event does not activate replay")
        func nonMatchingEventDoesNotActivate() async throws {
            let sut = getSut(eventTriggers: ["purchase_completed"])
            await waitForRemoteConfig(sut)

            let integration = sut.getReplayIntegration()
            #expect(integration?.isActive() == false)

            sut.capture("page_view")
            sut.capture("button_clicked")

            #expect(integration?.isActive() == false)

            sut.close()
        }

        @Test("Any matching trigger activates replay")
        func anyMatchingTriggerActivates() async throws {
            let sut = getSut(eventTriggers: ["purchase_completed", "signup_finished", "checkout_started"])
            await waitForRemoteConfig(sut)

            let integration = sut.getReplayIntegration()
            #expect(integration?.isActive() == false)

            sut.capture("signup_finished")

            #expect(integration?.isActive() == true)

            sut.close()
        }

        // MARK: - Session Rotation Tests

        @Test("New session requires new trigger activation")
        func newSessionRequiresNewTrigger() async throws {
            let sut = getSut(eventTriggers: ["purchase_completed"])
            await waitForRemoteConfig(sut)

            let integration = sut.getReplayIntegration()
            #expect(integration?.isActive() == false)

            sut.capture("purchase_completed")
            #expect(integration?.isActive() == true)

            sut.sessionManager.setSessionId(UUID().uuidString)

            #expect(integration?.isActive() == false)

            sut.close()
        }

        @Test("Trigger activation persists within same session")
        func triggerPersistsInSameSession() async throws {
            let sut = getSut(eventTriggers: ["purchase_completed"])
            await waitForRemoteConfig(sut)

            let integration = sut.getReplayIntegration()

            sut.capture("purchase_completed")
            #expect(integration?.isActive() == true)

            sut.capture("other_event")
            sut.capture("another_event")

            #expect(integration?.isActive() == true)

            sut.close()
        }

        // MARK: - Manual Start Tests

        @Test("Manual start bypasses event triggers")
        func manualStartBypassesTriggers() async throws {
            let sut = getSut(eventTriggers: ["purchase_completed"])
            await waitForRemoteConfig(sut)

            let integration = sut.getReplayIntegration()
            #expect(integration != nil)
            #expect(integration?.isActive() == false)

            integration?.startInternal(forceStart: true)

            #expect(integration?.isActive() == true)

            sut.close()
        }

        // MARK: - Stop/Start Tests

        @Test("Trigger event starts replay when stopped")
        func triggerStartsReplayWhenStopped() async throws {
            let sut = getSut(eventTriggers: ["purchase_completed"])
            await waitForRemoteConfig(sut)

            let integration = sut.getReplayIntegration()
            #expect(integration != nil)

            integration?.stop()

            sut.capture("purchase_completed")

            #expect(integration?.isActive() == true)

            sut.close()
        }

        // MARK: - Empty Triggers Tests

        @Test("Empty triggers array means no waiting")
        func emptyTriggersNoWaiting() async throws {
            let sut = getSut(eventTriggers: nil)
            await waitForRemoteConfig(sut)

            let integration = sut.getReplayIntegration()
            #expect(integration != nil)
            #expect(integration?.isActive() == true)

            sut.close()
        }

    }
#endif
