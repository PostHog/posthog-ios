#if os(iOS) && (!SWIFT_PACKAGE || SessionReplay)
    import Foundation
    @_spi(PostHogInternal) @testable import PostHog
    import Testing

    @Suite("Session Replay Event Triggers", .serialized)
    class PostHogSessionReplayEventTriggersTests {
        let server: MockPostHogServer

        init() {
            server = MockPostHogServer()
            server.start()
        }

        deinit {
            server.stop()
        }

        private func getSut(
            eventTriggers: [String]? = nil,
            linkedFlagNotMatched: Bool = false,
            triggerGroups: [[String: Any]]? = nil,
            localSampleRate: NSNumber? = nil
        ) -> PostHogSDK {
            // A token per test keeps the seeded recording config apart from other suites' SDK instances
            let config = PostHogConfig(projectToken: "replay_triggers_\(UUID().uuidString)", host: "http://localhost:9001")
            config.sessionReplay = true
            config.sessionReplayConfig.sampleRate = localSampleRate
            config.disableReachabilityForTesting = true
            config.disableQueueTimerForTesting = true
            config.preloadFeatureFlags = false
            // Drive recording config from the seeded .remoteConfig below, not the async /config fetch,
            // so the tests stay deterministic and independent of global stub state from other suites.
            config.disableRemoteConfigForTesting = true

            // Configure mock server for remote config
            server.returnReplay = true
            server.sessionRecordingEventTriggers = eventTriggers

            // Seed the recording config so install() reads the event triggers up front (.remoteConfig
            // survives reset(), so clear any value leaked from a previous serialized test first).
            let storage = PostHogStorage(config)
            storage.remove(key: .remoteConfig)
            var sessionRecording: [String: Any] = ["endpoint": "/s/"]
            if let eventTriggers {
                sessionRecording["eventTriggers"] = eventTriggers
            }
            if linkedFlagNotMatched {
                // No cached value seeded for this flag, so it evaluates as not matched.
                sessionRecording["linkedFlag"] = "unmatched_replay_flag"
            }
            if let triggerGroups {
                sessionRecording["version"] = 2
                sessionRecording["triggerGroups"] = triggerGroups
            }
            storage.setDictionary(forKey: .remoteConfig, contents: ["sessionRecording": sessionRecording])

            // Reset the static install flag a prior replay suite may have left set, so this SUT installs
            // a fresh integration rather than no-opping onto a stale one.
            PostHogReplayIntegration.clearInstalls()

            return PostHogSDK.with(config)
        }

        // MARK: - isActive() Tests

        @Test("isActive returns true when no event triggers configured")
        func isActiveWithoutTriggers() async throws {
            let sut = getSut(eventTriggers: nil)
            let integration = sut.getReplayIntegration()
            #expect(integration != nil)
            #expect(integration?.isActive() == true)

            sut.close()
        }

        @Test("isActive returns false when waiting for event trigger")
        func isActiveWhileWaitingForTrigger() async throws {
            let sut = getSut(eventTriggers: ["purchase_completed"])
            let integration = sut.getReplayIntegration()
            #expect(integration != nil)
            #expect(integration?.isActive() == false)

            sut.close()
        }

        @Test("isActive returns true after trigger event is captured")
        func isActiveAfterTriggerFired() async throws {
            let sut = getSut(eventTriggers: ["purchase_completed"])
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
            let integration = sut.getReplayIntegration()

            sut.capture("purchase_completed")
            #expect(integration?.isActive() == true)

            sut.capture("other_event")
            sut.capture("another_event")

            #expect(integration?.isActive() == true)

            sut.close()
        }

        // MARK: - Manual Start Tests

        @Test("Manual start respects event triggers")
        func manualStartRespectsTriggers() async throws {
            let sut = getSut(eventTriggers: ["purchase_completed"])
            let integration = sut.getReplayIntegration()
            #expect(integration != nil)
            #expect(integration?.isActive() == false)

            // Manual start should still wait for trigger
            sut.startSessionRecording()

            #expect(integration?.isActive() == false)

            // Trigger event activates replay
            sut.capture("purchase_completed")
            #expect(integration?.isActive() == true)

            sut.close()
        }

        // MARK: - Stop/Start Tests

        @Test("Trigger event does not restart replay when manually stopped")
        func triggerDoesNotRestartWhenManuallyStopped() async throws {
            let sut = getSut(eventTriggers: ["purchase_completed"])
            let integration = sut.getReplayIntegration()
            #expect(integration != nil)
            #expect(integration?.isActive() == false)

            // Activate with trigger
            sut.capture("purchase_completed")
            #expect(integration?.isActive() == true)

            // Manually stop
            sut.stopSessionRecording()
            #expect(integration?.isActive() == false)

            // Trigger event should NOT restart (event listener is removed on stop)
            sut.capture("purchase_completed")
            #expect(integration?.isActive() == false)

            sut.close()
        }

        // MARK: - Remote Config Reload Tests

        @Test("Reloading an unchanged trigger list keeps the trigger-activated session recording")
        func unchangedTriggersReloadKeepsActivation() async throws {
            let sut = getSut(eventTriggers: ["purchase_completed"])
            let integration = try #require(sut.getReplayIntegration())
            defer { sut.close() }

            sut.capture("purchase_completed")
            #expect(integration.isActive() == true)
            let sessionId = try #require(sut.getSessionId())

            sut.remoteConfig?.onRemoteConfigLoaded.invoke(sut.remoteConfig?.getRemoteConfig())

            #expect(integration.isActive() == true)
            #expect(sut.getSessionId() == sessionId)
        }

        @Test("Reloading the same triggers in a different order keeps the trigger-activated session recording")
        func reorderedTriggersReloadKeepsActivation() async throws {
            let sut = getSut(eventTriggers: ["purchase_completed", "signup_finished"])
            let integration = try #require(sut.getReplayIntegration())
            defer { sut.close() }

            sut.capture("purchase_completed")
            #expect(integration.isActive() == true)

            sut.remoteConfig?.onRemoteConfigLoaded.invoke(remoteConfig(eventTriggers: ["signup_finished", "purchase_completed"]))

            #expect(integration.isActive() == true)
        }

        @Test("Reloading a changed trigger list keeps the trigger-activated session recording")
        func changedTriggersReloadKeepsActivation() async throws {
            let sut = getSut(eventTriggers: ["purchase_completed"])
            let integration = try #require(sut.getReplayIntegration())
            defer { sut.close() }

            sut.capture("purchase_completed")
            #expect(integration.isActive() == true)

            sut.remoteConfig?.onRemoteConfigLoaded.invoke(remoteConfig(eventTriggers: ["checkout_started"]))

            #expect(integration.isActive() == true)
        }

        @Test("Activation kept across a reload does not carry over to a new session")
        func reloadKeptActivationDoesNotCarryToNewSession() async throws {
            let sut = getSut(eventTriggers: ["purchase_completed"])
            let integration = try #require(sut.getReplayIntegration())
            defer { sut.close() }

            sut.capture("purchase_completed")
            sut.remoteConfig?.onRemoteConfigLoaded.invoke(remoteConfig(eventTriggers: ["checkout_started"]))
            #expect(integration.isActive() == true)

            sut.sessionManager.setSessionId(UUID().uuidString)

            #expect(integration.isActive() == false)
        }

        @Test("Reloading with triggers added stops a recording the session never activated")
        func addedTriggersReloadStopsUnactivatedRecording() async throws {
            let sut = getSut(eventTriggers: nil)
            let integration = try #require(sut.getReplayIntegration())
            defer { sut.close() }
            #expect(integration.isActive() == true)

            sut.remoteConfig?.onRemoteConfigLoaded.invoke(remoteConfig(eventTriggers: ["purchase_completed"]))

            #expect(integration.isActive() == false)
        }

        @Test("Reloading with the triggers removed starts recording")
        func removedTriggersReloadStartsRecording() async throws {
            let sut = getSut(eventTriggers: ["purchase_completed"])
            let integration = try #require(sut.getReplayIntegration())
            defer { sut.close() }
            #expect(integration.isActive() == false)

            sut.remoteConfig?.onRemoteConfigLoaded.invoke(remoteConfig(eventTriggers: []))

            #expect(integration.isActive() == true)
        }

        private func remoteConfig(eventTriggers: [String]) -> [String: Any] {
            ["sessionRecording": ["endpoint": "/s/", "eventTriggers": eventTriggers]]
        }

        // MARK: - Empty Triggers Tests

        @Test("Empty triggers array means no waiting")
        func emptyTriggersNoWaiting() async throws {
            let sut = getSut(eventTriggers: [])
            let integration = sut.getReplayIntegration()
            #expect(integration != nil)
            #expect(integration?.isActive() == true)

            sut.close()
        }

        // MARK: - React Native Opt-Out Tests

        @Test("React Native opts out of native event-trigger gating")
        func reactNativeOptsOutOfTriggerGating() async throws {
            let original = postHogSdkName
            postHogSdkName = "posthog-react-native"
            defer { postHogSdkName = original }

            // Triggers are configured, but React Native evaluates them in its JS layer, so the native
            // integration must not gate — recording is active immediately without a trigger firing.
            // (The non-RN path that waits for a trigger is covered by isActiveWhileWaitingForTrigger.)
            let sut = getSut(eventTriggers: ["purchase_completed"])
            let integration = sut.getReplayIntegration()
            #expect(integration != nil)
            #expect(integration?.isActive() == true)

            sut.close()
        }

        // MARK: - v2 Trigger Groups

        @Test("an event-only trigger group waits for its event")
        func eventOnlyTriggerGroupWaits() async throws {
            let sut = getSut(triggerGroups: [eventOnlyTriggerGroup])
            defer { sut.close() }

            #expect(sut.getReplayIntegration()?.isActive() == false)
        }

        private var checkoutUrlTriggerGroup: [String: Any] {
            ["id": "checkout", "sampleRate": 1, "conditions": ["matchType": "any", "urls": [["url": "Checkout", "matching": "regex"]]]]
        }

        @Test("a session rotation on a matching screen keeps the URL trigger group active")
        func sessionRotationOnMatchingScreenStaysActive() async throws {
            let sut = getSut(triggerGroups: [checkoutUrlTriggerGroup])
            defer { sut.close() }
            let integration = try #require(sut.getReplayIntegration())

            sut.screen("Checkout")
            #expect(integration.isActive() == true)

            sut.sessionManager.setSessionId(UUID().uuidString)

            #expect(integration.isActive() == true)
        }

        @Test("a session rotation on a non-matching screen keeps the URL trigger group pending")
        func sessionRotationOnOtherScreenStaysPending() async throws {
            let sut = getSut(triggerGroups: [checkoutUrlTriggerGroup])
            defer { sut.close() }
            let integration = try #require(sut.getReplayIntegration())

            sut.screen("Home")
            #expect(integration.isActive() == false)

            let newSessionId = UUID().uuidString
            sut.sessionManager.setSessionId(newSessionId)

            #expect(integration.isActive() == false)
            #expect(sut.remoteConfig?.hasPendingSessionRecordingTriggerGroups(sessionId: newSessionId) == true)
        }

        @Test("a snapshot event does not activate a trigger group")
        func snapshotEventDoesNotActivateTriggerGroup() async throws {
            let sut = getSut(triggerGroups: [[
                "id": "snapshot", "sampleRate": 1,
                "conditions": ["matchType": "any", "events": [["name": "$snapshot"]]],
            ]])
            defer { sut.close() }
            let integration = try #require(sut.getReplayIntegration())

            sut.capture("$snapshot", properties: ["$snapshot_data": []])

            #expect(integration.isActive() == false)
        }

        @Test("a v2 config whose every group is rejected stays in v2 and records nothing")
        func v2WithOnlyRejectedGroupsRecordsNothing() async throws {
            let sut = getSut(triggerGroups: [["id": "", "sampleRate": 0, "conditions": [:]]])
            defer { sut.close() }
            let integration = try #require(sut.getReplayIntegration())
            let remoteConfig = try #require(sut.remoteConfig)

            sut.screen("Checkout")
            sut.capture("purchase_completed")

            #expect(remoteConfig.hasSessionRecordingTriggerGroups() == true)
            #expect(integration.isActive() == false)
            let properties = integration.debugProperties()
            #expect(properties["$sdk_debug_replay_remote_trigger_matching_config"] as? String == "v2_trigger_groups")
            #expect(properties["$sdk_debug_replay_trigger_groups_count"] as? Int == 0)
        }

        @Test("a v2 config with an empty trigger group list keeps the v1 gates")
        func v2WithEmptyTriggerGroupsKeepsV1() async throws {
            let sut = getSut(eventTriggers: ["purchase_completed"], triggerGroups: [])
            defer { sut.close() }
            let integration = try #require(sut.getReplayIntegration())

            #expect(sut.remoteConfig?.hasSessionRecordingTriggerGroups() == false)
            #expect(integration.isActive() == false)

            sut.capture("purchase_completed")

            #expect(integration.isActive() == true)
        }

        @Test("React Native leaves trigger groups to the JS layer")
        func reactNativeLeavesTriggerGroupsToJS() async throws {
            let original = postHogSdkName
            postHogSdkName = "posthog-react-native"
            defer { postHogSdkName = original }

            // The same event-only group: JS decides when to start, so native must not refuse it.
            let sut = getSut(triggerGroups: [eventOnlyTriggerGroup])
            defer { sut.close() }

            #expect(sut.getReplayIntegration()?.isActive() == true)
        }

        @Test("under React Native a native config callback does not restart a recorder JS stopped")
        func reactNativeStopSurvivesConfigCallback() async throws {
            let original = postHogSdkName
            postHogSdkName = "posthog-react-native"
            defer { postHogSdkName = original }

            let sut = getSut(triggerGroups: [eventOnlyTriggerGroup])
            defer { sut.close() }
            // Under React Native the JS layer hands native its session id.
            sut.sessionManager.setSessionId(UUID().uuidString)
            let integration = try #require(sut.getReplayIntegration())
            #expect(integration.isActive() == true)

            // JS found the session no longer eligible and stopped the recorder.
            sut.stopSessionRecording()
            #expect(integration.isActive() == false)

            integration.applyRemoteConfig(remoteConfig: sut.remoteConfig?.getRemoteConfig())
            #expect(integration.isActive() == false)

            // Only the JS layer's next start resumes it.
            sut.startSessionRecording(resumeCurrent: true)
            #expect(integration.isActive() == true)
        }

        @Test("under React Native a refused start request still unblocks automatic starts")
        func reactNativeRefusedStartStillClearsStopLatch() async throws {
            let original = postHogSdkName
            postHogSdkName = "posthog-react-native"
            defer { postHogSdkName = original }

            let sut = getSut(triggerGroups: [eventOnlyTriggerGroup])
            defer { sut.close() }
            // Under React Native the JS layer hands native its session id.
            sut.sessionManager.setSessionId(UUID().uuidString)
            let integration = try #require(sut.getReplayIntegration())
            #expect(integration.isActive() == true)

            // JS found the session no longer eligible and stopped the recorder.
            sut.stopSessionRecording()
            #expect(integration.isActive() == false)

            // JS asks to start again, but native refuses this call: the replay flag is not active.
            sut.remoteConfig?.setSessionReplayFlagActiveForTesting(false)
            sut.startSessionRecording(resumeCurrent: true)
            #expect(integration.isActive() == false)

            // The request still meant "JS wants recording": a later automatic start (config
            // callback) must not stay blocked by the latch.
            sut.remoteConfig?.setSessionReplayFlagActiveForTesting(true)
            integration.applyRemoteConfig(remoteConfig: sut.remoteConfig?.getRemoteConfig())
            #expect(integration.isActive() == true)
        }

        @Test("outside React Native a config callback does not resume after a stop")
        func nativeStopHoldsAcrossConfigCallback() async throws {
            let sut = getSut(triggerGroups: [["id": "unconditional", "sampleRate": 1, "conditions": ["matchType": "any"]]])
            defer { sut.close() }
            let integration = try #require(sut.getReplayIntegration())

            sut.stopSessionRecording()
            #expect(integration.isActive() == false)

            integration.applyRemoteConfig(remoteConfig: sut.remoteConfig?.getRemoteConfig())
            #expect(integration.isActive() == false)

            sut.startSessionRecording(resumeCurrent: true)
            #expect(integration.isActive() == true)
        }

        @Test("the v1 linked flag does not gate recording under trigger groups")
        func linkedFlagIgnoredUnderTriggerGroups() async throws {
            let sut = getSut(
                linkedFlagNotMatched: true,
                triggerGroups: [["id": "unconditional", "sampleRate": 1, "conditions": ["matchType": "any"]]]
            )
            defer { sut.close() }

            #expect(sut.getReplayIntegration()?.isActive() == true)
            #expect(sut.remoteConfig?.sessionReplayLinkedFlagSnapshot().configured == false)
        }

        @Test("v1 event triggers do not gate recording under trigger groups")
        func eventTriggersIgnoredUnderTriggerGroups() async throws {
            let sut = getSut(
                eventTriggers: ["purchase_completed"],
                triggerGroups: [["id": "unconditional", "sampleRate": 1, "conditions": ["matchType": "any"]]]
            )
            defer { sut.close() }

            #expect(sut.getReplayIntegration()?.isActive() == true)
        }

        @Test("the local sample rate still caps recording under trigger groups")
        func localSampleRateCapsTriggerGroups() async throws {
            let sut = getSut(
                triggerGroups: [["id": "unconditional", "sampleRate": 1, "conditions": ["matchType": "any"]]],
                localSampleRate: 0
            )
            defer { sut.close() }

            #expect(sut.getReplayIntegration()?.isActive() == false)
        }

        private var fractionalUnconditionalGroup: [[String: Any]] {
            [["id": "g-empty", "sampleRate": 0.2, "conditions": ["matchType": "all"]]]
        }

        /// A fresh session id the trigger groups sample in (or out), picked through the SDK's own evaluator.
        private func sessionId(sampledIn: Bool, by sut: PostHogSDK) throws -> String {
            let remoteConfig = try #require(sut.remoteConfig)
            for _ in 0 ..< 1000 {
                let id = UUID().uuidString
                if remoteConfig.isSessionRecordingPermittedByTriggerGroups(sessionId: id) == sampledIn {
                    return id
                }
            }
            Issue.record("no session id sampled \(sampledIn ? "in" : "out")")
            return UUID().uuidString
        }

        @Test("unconditional groups resume after a sampled-out session")
        func unconditionalGroupsResumeAfterSampledOutSession() throws {
            let sut = getSut(triggerGroups: fractionalUnconditionalGroup)
            defer { sut.close() }
            let first = try sessionId(sampledIn: true, by: sut)
            let sampledOut = try sessionId(sampledIn: false, by: sut)
            let third = try sessionId(sampledIn: true, by: sut)

            sut.sessionManager.setSessionId(first)
            sut.startSessionRecording(resumeCurrent: true)
            #expect(sut.isSessionReplayActive())

            sut.sessionManager.setSessionId(sampledOut)
            #expect(!sut.isSessionReplayActive())

            sut.sessionManager.setSessionId(third)
            #expect(sut.isSessionReplayActive())

            sut.capture("ordinary")
            #expect(sut.isSessionReplayActive())
        }

        @Test("a session sampled out from the start does not block the next one")
        func initiallySampledOutSessionDoesNotBlockNext() throws {
            let sut = getSut(triggerGroups: fractionalUnconditionalGroup)
            defer { sut.close() }
            let out = try sessionId(sampledIn: false, by: sut)
            let inId = try sessionId(sampledIn: true, by: sut)

            sut.stopSessionRecording()
            sut.sessionManager.setSessionId(out)
            sut.startSessionRecording(resumeCurrent: true)
            #expect(!sut.isSessionReplayActive())

            sut.sessionManager.setSessionId(inId)
            #expect(sut.isSessionReplayActive())
        }

        @Test("an explicit stop still holds across a session change")
        func explicitStopHoldsAcrossSessionChange() throws {
            let sut = getSut(triggerGroups: fractionalUnconditionalGroup)
            defer { sut.close() }
            let first = try sessionId(sampledIn: true, by: sut)
            let second = try sessionId(sampledIn: true, by: sut)

            sut.sessionManager.setSessionId(first)
            sut.startSessionRecording(resumeCurrent: true)
            #expect(sut.isSessionReplayActive())

            sut.stopSessionRecording()
            sut.sessionManager.setSessionId(second)
            #expect(!sut.isSessionReplayActive())

            sut.startSessionRecording(resumeCurrent: true)
            #expect(sut.isSessionReplayActive())
        }

        @Test("a flags reload does not restart a recorder the app stopped")
        func flagsReloadDoesNotUndoExplicitStop() throws {
            let sut = getSut(triggerGroups: [["id": "unconditional", "sampleRate": 1, "conditions": ["matchType": "any"]]])
            defer { sut.close() }
            sut.startSessionRecording(resumeCurrent: true)
            #expect(sut.isSessionReplayActive())

            sut.stopSessionRecording()
            sut.remoteConfig?.onFeatureFlagsLoaded.invoke([:])
            #expect(!sut.isSessionReplayActive())

            sut.startSessionRecording(resumeCurrent: true)
            #expect(sut.isSessionReplayActive())
        }

        @Test("a matching trigger group event does not restart a recorder the app stopped")
        func triggerGroupEventDoesNotUndoExplicitStop() throws {
            let sut = getSut(triggerGroups: [eventOnlyTriggerGroup])
            defer { sut.close() }

            sut.capture("purchase_completed")
            #expect(sut.isSessionReplayActive())

            sut.stopSessionRecording()
            sut.sessionManager.setSessionId(UUID().uuidString)
            sut.capture("purchase_completed")
            #expect(!sut.isSessionReplayActive())

            // The event captured while stopped did not activate the group for this session.
            sut.startSessionRecording(resumeCurrent: true)
            #expect(!sut.isSessionReplayActive())
            sut.capture("purchase_completed")
            #expect(sut.isSessionReplayActive())
        }

        @Test("a resumed recording survives a sampled-out session")
        func resumedReplaySurvivesSampledOutSession() throws {
            let sut = getSut(triggerGroups: fractionalUnconditionalGroup)
            defer { sut.close() }
            let first = try sessionId(sampledIn: true, by: sut)
            let sampledOut = try sessionId(sampledIn: false, by: sut)
            let third = try sessionId(sampledIn: true, by: sut)

            sut.sessionManager.setSessionId(first)
            sut.startSessionRecording(resumeCurrent: true)
            #expect(sut.isSessionReplayActive())

            sut.stopSessionRecording()
            #expect(!sut.isSessionReplayActive())

            sut.startSessionRecording(resumeCurrent: true)
            #expect(sut.isSessionReplayActive())

            sut.sessionManager.setSessionId(sampledOut)
            #expect(!sut.isSessionReplayActive())

            sut.sessionManager.setSessionId(third)
            #expect(sut.isSessionReplayActive())
        }

        @Test("a stop after a resume holds across a session change again")
        func stopAfterResumeHoldsAcrossSessionChange() throws {
            let sut = getSut(triggerGroups: fractionalUnconditionalGroup)
            defer { sut.close() }
            let first = try sessionId(sampledIn: true, by: sut)
            let second = try sessionId(sampledIn: true, by: sut)

            sut.sessionManager.setSessionId(first)
            sut.startSessionRecording(resumeCurrent: true)
            sut.stopSessionRecording()
            sut.startSessionRecording(resumeCurrent: true)
            #expect(sut.isSessionReplayActive())

            sut.stopSessionRecording()
            sut.sessionManager.setSessionId(second)
            #expect(!sut.isSessionReplayActive())
        }

        @Test("a refused start request after a stop still lets the next session record")
        func refusedStartAfterStopLetsNextSessionRecord() throws {
            let sut = getSut(triggerGroups: fractionalUnconditionalGroup)
            defer { sut.close() }
            let first = try sessionId(sampledIn: true, by: sut)
            let second = try sessionId(sampledIn: true, by: sut)

            sut.sessionManager.setSessionId(first)
            sut.startSessionRecording(resumeCurrent: true)
            sut.stopSessionRecording()
            #expect(!sut.isSessionReplayActive())

            // The app asks to start again, but this call is refused: the replay flag is not active.
            sut.remoteConfig?.setSessionReplayFlagActiveForTesting(false)
            sut.startSessionRecording(resumeCurrent: true)
            #expect(!sut.isSessionReplayActive())

            sut.remoteConfig?.setSessionReplayFlagActiveForTesting(true)
            sut.sessionManager.setSessionId(second)
            #expect(sut.isSessionReplayActive())
        }

        private var eventOnlyTriggerGroup: [String: Any] {
            ["id": "purchase", "name": "Purchase", "sampleRate": 1, "conditions": ["matchType": "any", "events": [["name": "purchase_completed"]]]]
        }

        // MARK: - debugProperties() Trigger Status

        @Test("trigger status reflects pending state before either trigger resolves, then activation as each fires")
        func triggerStatusReflectsCurrentState() async throws {
            let sut = getSut(eventTriggers: ["purchase_completed"], linkedFlagNotMatched: true)
            let integration = try #require(sut.getReplayIntegration())
            defer { sut.close() }

            // Neither trigger has resolved yet — the integration hasn't even started (event-trigger
            // gated), but trigger status is computed fresh regardless of active state.
            var props = integration.debugProperties()
            #expect(props["$sdk_debug_replay_linked_flag_trigger_status"] as? String == "trigger_pending")
            #expect(props["$sdk_debug_replay_event_trigger_status"] as? String == "trigger_pending")
            let pending = props["$sdk_debug_replay_pending_trigger_conditions"] as? [String] ?? []
            #expect(Set(pending) == Set(["linked_flag", "event_trigger"]))

            sut.capture("purchase_completed")

            props = integration.debugProperties()
            #expect(props["$sdk_debug_replay_event_trigger_status"] as? String == "trigger_activated")
            let pendingAfter = props["$sdk_debug_replay_pending_trigger_conditions"] as? [String] ?? []
            #expect(!pendingAfter.contains("event_trigger"))
        }

        @Test("pending trigger groups name each pending condition until one records")
        func pendingTriggerGroupsAreAPendingCondition() async throws {
            let sut = getSut(triggerGroups: [eventOnlyTriggerGroup])
            let integration = try #require(sut.getReplayIntegration())
            defer { sut.close() }

            var props = integration.debugProperties()
            #expect(props["$sdk_debug_replay_event_trigger_status"] as? String == "trigger_disabled")
            #expect(props["$sdk_debug_replay_linked_flag_trigger_status"] as? String == "trigger_disabled")
            #expect(props["$sdk_debug_replay_pending_trigger_conditions"] as? [String] == ["trigger group \"Purchase\": event condition not matched"])

            sut.capture("purchase_completed")

            props = integration.debugProperties()
            #expect(props["$sdk_debug_replay_pending_trigger_conditions"] == nil)
        }

        @Test("a screen seen while replay is stopped activates the group for the session the next start opens")
        func screenSeenWhileStoppedCountsForTheNextSession() async throws {
            let sut = getSut(triggerGroups: [checkoutUrlTriggerGroup])
            defer { sut.close() }
            let integration = try #require(sut.getReplayIntegration())

            sut.stopSessionRecording()
            sut.screen("Checkout")
            #expect(integration.isActive() == false)

            sut.startSessionRecording(resumeCurrent: false)

            #expect(integration.isActive() == true)
        }

        @Test("a screen event that rotates the session checks its own screen, not the one it left")
        func rotatingScreenEventChecksItsOwnScreen() async throws {
            // An inactivity timeout rotates the session only in the foreground; in the background it clears it.
            DI.main.appLifecyclePublisher = MockApplicationLifecyclePublisher()
            defer { DI.main.appLifecyclePublisher = ApplicationLifecyclePublisher.shared }
            let sut = getSut(triggerGroups: [checkoutUrlTriggerGroup])
            defer { sut.close() }
            let integration = try #require(sut.getReplayIntegration())

            sut.screen("Checkout")
            #expect(integration.isActive() == true)
            let oldSessionId = try #require(sut.sessionManager.getSessionId(readOnly: true))

            let pastInactivityTimeout = Date().addingTimeInterval(60 * 60)
            sut.capture("$screen", properties: ["$screen_name": "Home"], timestamp: pastInactivityTimeout)

            let newSessionId = try #require(sut.sessionManager.getSessionId(readOnly: true))
            #expect(newSessionId != oldSessionId)
            #expect(sut.remoteConfig?.hasPendingSessionRecordingTriggerGroups(sessionId: newSessionId) == true)
            #expect(integration.isActive() == false)
        }

        @Test("a session started while replay is stopped is checked against the screen at the next start")
        func stoppedSessionIsCheckedOnNextStart() async throws {
            let sut = getSut(triggerGroups: [checkoutUrlTriggerGroup])
            defer { sut.close() }
            let integration = try #require(sut.getReplayIntegration())

            sut.stopSessionRecording()
            sut.screen("Checkout")

            let newSessionId = UUID().uuidString
            sut.sessionManager.setSessionId(newSessionId)
            #expect(sut.remoteConfig?.hasPendingSessionRecordingTriggerGroups(sessionId: newSessionId) == true)

            sut.startSessionRecording(resumeCurrent: true)

            #expect(integration.isActive() == true)
        }

        @Test("a matching screen seen while stopped activates the group at the next start in a session that evaluated events")
        func screenSeenWhileStoppedCountsInEvaluatedSession() async throws {
            let sut = getSut(triggerGroups: [checkoutUrlTriggerGroup])
            defer { sut.close() }
            let integration = try #require(sut.getReplayIntegration())

            sut.capture("app_opened")
            let sessionId = try #require(sut.sessionManager.getSessionId(readOnly: true))
            sut.stopSessionRecording()
            sut.screen("Checkout")

            sut.startSessionRecording(resumeCurrent: true)

            #expect(sut.sessionManager.getSessionId(readOnly: true) == sessionId)
            #expect(integration.isActive() == true)
        }

        @Test("a non-matching screen seen while stopped keeps the group pending at the next start")
        func nonMatchingScreenSeenWhileStoppedStaysPending() async throws {
            let sut = getSut(triggerGroups: [checkoutUrlTriggerGroup])
            defer { sut.close() }
            let integration = try #require(sut.getReplayIntegration())

            sut.capture("app_opened")
            let sessionId = try #require(sut.sessionManager.getSessionId(readOnly: true))
            sut.stopSessionRecording()
            sut.screen("Home")

            sut.startSessionRecording(resumeCurrent: true)

            #expect(sut.remoteConfig?.hasPendingSessionRecordingTriggerGroups(sessionId: sessionId) == true)
            #expect(integration.isActive() == false)
        }

        @Test("a screen evaluated live without a match is not activated by a stop and a start")
        func liveScreenWithoutMatchIsNotRecheckedOnStart() async throws {
            var group = checkoutUrlTriggerGroup
            group["conditions"] = [
                "matchType": "any",
                "urls": [["url": "Checkout", "matching": "regex"]],
                "properties": [["type": "person", "key": "plan", "value": "pro"]],
            ]
            let sut = getSut(triggerGroups: [group])
            defer { sut.close() }
            let integration = try #require(sut.getReplayIntegration())

            sut.screen("Checkout")
            #expect(integration.isActive() == false)

            sut.setPersonPropertiesForFlags(["plan": "pro"], reloadFeatureFlags: false)
            sut.stopSessionRecording()
            sut.startSessionRecording(resumeCurrent: true)

            #expect(integration.isActive() == false)
        }

        // MARK: - Trigger groups loaded by a config

        /// `applyRemoteConfig` runs on the main queue after the reload callback.
        private func loadConfig(_ sut: PostHogSDK, triggerGroups: [[String: Any]]) async throws {
            server.sessionRecordingTriggerGroups = triggerGroups
            let remoteConfig = try #require(sut.remoteConfig)
            await withCheckedContinuation { continuation in
                remoteConfig.reloadRemoteConfig { _ in continuation.resume() }
            }
            await MainActor.run {}
        }

        @Test("a matching screen seen before the first v2 config records once the config loads")
        func screenBeforeFirstGroupsLoadRecords() async throws {
            let sut = getSut()
            defer { sut.close() }
            let integration = try #require(sut.getReplayIntegration())

            sut.screen("Checkout")
            try await loadConfig(sut, triggerGroups: [checkoutUrlTriggerGroup])

            #expect(sut.remoteConfig?.hasSessionRecordingTriggerGroups() == true)
            #expect(integration.isActive() == true)
        }

        @Test("a config reload that adds a group matching the current screen activates it")
        func reloadAddingMatchingGroupActivates() async throws {
            let sut = getSut(triggerGroups: [eventOnlyTriggerGroup])
            defer { sut.close() }
            let integration = try #require(sut.getReplayIntegration())

            sut.screen("Checkout")
            #expect(integration.isActive() == false)

            try await loadConfig(sut, triggerGroups: [eventOnlyTriggerGroup, checkoutUrlTriggerGroup])

            #expect(integration.isActive() == true)
        }

        @Test("a config reload on a non-matching screen keeps the new group pending")
        func reloadOnNonMatchingScreenStaysPending() async throws {
            let sut = getSut(triggerGroups: [eventOnlyTriggerGroup])
            defer { sut.close() }
            let integration = try #require(sut.getReplayIntegration())

            sut.screen("Home")
            try await loadConfig(sut, triggerGroups: [eventOnlyTriggerGroup, checkoutUrlTriggerGroup])

            let sessionId = try #require(sut.sessionManager.getSessionId(readOnly: true))
            #expect(sut.remoteConfig?.hasPendingSessionRecordingTriggerGroups(sessionId: sessionId) == true)
            #expect(integration.isActive() == false)
        }

        @Test("a config loaded while replay is stopped activates nothing until the next start")
        func reloadWhileStoppedWaitsForStart() async throws {
            let sut = getSut(triggerGroups: [eventOnlyTriggerGroup])
            defer { sut.close() }
            let integration = try #require(sut.getReplayIntegration())

            sut.screen("Checkout")
            sut.stopSessionRecording()
            try await loadConfig(sut, triggerGroups: [eventOnlyTriggerGroup, checkoutUrlTriggerGroup])

            let sessionId = try #require(sut.sessionManager.getSessionId(readOnly: true))
            #expect(sut.remoteConfig?.hasPendingSessionRecordingTriggerGroups(sessionId: sessionId) == true)
            #expect(integration.isActive() == false)

            sut.startSessionRecording(resumeCurrent: true)

            #expect(integration.isActive() == true)
        }

        @Test("reset on a matching screen keeps the URL trigger group active for the session it starts")
        func resetOnMatchingScreenStaysActive() async throws {
            let sut = getSut(triggerGroups: [checkoutUrlTriggerGroup])
            defer { sut.close() }
            let integration = try #require(sut.getReplayIntegration())

            sut.screen("Checkout")
            #expect(integration.isActive() == true)
            let oldSessionId = try #require(sut.sessionManager.getSessionId(readOnly: true))

            sut.reset()
            sut.remoteConfig?.onFeatureFlagsLoaded.invoke([:])

            let newSessionId = try #require(sut.sessionManager.getSessionId(readOnly: true))
            #expect(newSessionId != oldSessionId)
            #expect(sut.remoteConfig?.hasPendingSessionRecordingTriggerGroups(sessionId: newSessionId) == false)
            #expect(integration.isActive() == true)
        }
    }
#endif
