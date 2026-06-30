#if os(iOS)
    import Foundation
    @testable import PostHog
    import Testing

    @Suite("Session Replay Remote Config Buffering", .serialized)
    class PostHogSessionReplayRemoteConfigBufferTests {
        let server: MockPostHogServer

        init() {
            server = MockPostHogServer()
            server.start()
        }

        deinit {
            server.stop()
        }

        /// - Parameters:
        ///   - flagActive: whether the seeded cached recording config evaluates the replay flag as
        ///     active (no linkedFlag) or inactive (an unmatched linkedFlag).
        ///   - minimumDurationMilliseconds: optional minimum-duration buffering threshold to seed.
        ///   - sampleRate: optional remote sample rate to seed (0 samples every session out).
        ///   - linkedFlag: if set, gate recording on this feature flag (instead of `flagActive`) and seed
        ///     its cached value to `cachedLinkedFlagValue`.
        ///   - cachedLinkedFlagValue: the cached value seeded for `linkedFlag` (drives the cold-start flag).
        ///   - preloadFeatureFlags: the `config.preloadFeatureFlags` value (gates the linkedFlag deferral).
        private func getSut(
            flagActive: Bool,
            minimumDurationMilliseconds: Int? = nil,
            sampleRate: Double? = nil,
            linkedFlag: String? = nil,
            cachedLinkedFlagValue: Bool = true,
            preloadFeatureFlags: Bool = false
        ) -> PostHogSDK {
            // Unique token per SUT so the disk-backed replay queue is isolated and this suite never
            // pollutes (or inherits) snapshots from the shared "test_project_token" used elsewhere.
            let config = PostHogConfig(projectToken: UUID().uuidString, host: "http://localhost:9001")
            config.sessionReplay = true
            config.disableReachabilityForTesting = true
            config.disableQueueTimerForTesting = true
            config.preloadFeatureFlags = preloadFeatureFlags
            // Keep the threshold above the handful of events migrated below so the migrate step doesn't
            // auto-flush them out of the persisted queue before the assertion reads its depth.
            config.flushAt = 1000
            // Drive the flag from the seeded cache, not the async /config. remoteConfigDidFetch stays
            // false, so the integration arms awaitingFirstRemoteConfig at install.
            config.disableRemoteConfigForTesting = true

            // Seed the recording config so preload reads the flag/minimum-duration up front.
            let storage = PostHogStorage(config)
            var sessionRecording: [String: Any] = ["endpoint": "/s/"]
            if let linkedFlag {
                sessionRecording["linkedFlag"] = linkedFlag
                storage.setDictionary(forKey: .enabledFeatureFlags, contents: [linkedFlag: cachedLinkedFlagValue])
            } else if !flagActive {
                sessionRecording["linkedFlag"] = "unmatched_replay_flag"
            }
            if let minimumDurationMilliseconds {
                sessionRecording["minimumDurationMilliseconds"] = minimumDurationMilliseconds
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

        private func makeSut(
            flagActive: Bool,
            minimumDurationMilliseconds: Int? = nil,
            sampleRate: Double? = nil,
            linkedFlag: String? = nil,
            cachedLinkedFlagValue: Bool = true,
            preloadFeatureFlags: Bool = false
        ) throws -> (sut: PostHogSDK, integration: PostHogReplayIntegration, replayQueue: PostHogReplayQueue) {
            let sut = getSut(
                flagActive: flagActive,
                minimumDurationMilliseconds: minimumDurationMilliseconds,
                sampleRate: sampleRate,
                linkedFlag: linkedFlag,
                cachedLinkedFlagValue: cachedLinkedFlagValue,
                preloadFeatureFlags: preloadFeatureFlags
            )
            return (sut, try #require(sut.getReplayIntegration()), try #require(sut.replayQueue))
        }

        private func snapshotEvent(_ name: String = "snapshot") -> PostHogEvent {
            PostHogEvent(event: "$snapshot", distinctId: "test-user", properties: ["name": name])
        }

        @Test("snapshots route to the buffer while awaiting the first remote config")
        func snapshotsBufferWhileAwaiting() throws {
            let (sut, integration, replayQueue) = try makeSut(flagActive: true)
            defer { sut.close() }

            #expect(integration.isBuffering == true)

            replayQueue.add(snapshotEvent("1"))
            replayQueue.add(snapshotEvent("2"))

            #expect(replayQueue.bufferDepth == 2)
            #expect(replayQueue.depth == 0)
        }

        @Test("first remote config with flag on migrates the buffer to the persisted queue")
        func firstConfigFlagOnMigrates() async throws {
            let (sut, integration, replayQueue) = try makeSut(flagActive: true)
            defer { sut.close() }

            replayQueue.add(snapshotEvent("1"))
            replayQueue.add(snapshotEvent("2"))
            #expect(replayQueue.bufferDepth == 2)
            #expect(replayQueue.depth == 0)

            integration.applyRemoteConfig(remoteConfig: nil)
            await waitUntil { replayQueue.bufferDepth == 0 && replayQueue.depth == 2 }

            #expect(replayQueue.bufferDepth == 0)
            #expect(replayQueue.depth == 2)
            #expect(integration.isBuffering == false)
            #expect(integration.isActive() == true)
        }

        @Test("first remote config with flag off drops the buffer and nothing is persisted")
        func firstConfigFlagOffDropsBuffer() async throws {
            let (sut, integration, replayQueue) = try makeSut(flagActive: false)
            defer { sut.close() }

            replayQueue.add(snapshotEvent("1"))
            replayQueue.add(snapshotEvent("2"))
            #expect(replayQueue.bufferDepth == 2)

            integration.applyRemoteConfig(remoteConfig: nil)
            await waitUntil { replayQueue.bufferDepth == 0 }

            // Buffer dropped, nothing migrated to the persisted queue, and the fresh flag is off so the
            // capturer self-gates (recording doesn't resume on its own).
            #expect(replayQueue.bufferDepth == 0)
            #expect(replayQueue.depth == 0)
            #expect(integration.isBuffering == false)
            #expect(sut.remoteConfig?.isSessionReplayFlagActive() == false)
        }

        @Test("first remote config with flag on but session sampled out drops the buffer")
        func firstConfigFlagOnSampledOutDropsBuffer() async throws {
            // Flag stays on, but the fresh sample rate now excludes every session. The buffered opening
            // window recorded under the stale cache must be discarded, not migrated against the policy.
            let (sut, integration, replayQueue) = try makeSut(flagActive: true, sampleRate: 0)
            defer { sut.close() }

            replayQueue.add(snapshotEvent("1"))
            replayQueue.add(snapshotEvent("2"))
            #expect(replayQueue.bufferDepth == 2)

            integration.applyRemoteConfig(remoteConfig: nil)
            await waitUntil { replayQueue.bufferDepth == 0 }

            #expect(replayQueue.bufferDepth == 0)
            #expect(replayQueue.depth == 0)
            #expect(integration.isBuffering == false)
            #expect(sut.remoteConfig?.isSessionReplayFlagActive() == true)
            #expect(integration.isActive() == false)
        }

        @Test("first remote config that introduces an event trigger drops the buffer")
        func firstConfigIntroducingEventTriggerDropsBuffer() async throws {
            // Cached config had no triggers, so the opening window was recorded and buffered. The fresh
            // config now gates recording behind an unfired event trigger, so the pre-trigger window must
            // be discarded — mirroring how `start()` won't record until the trigger fires.
            let (sut, integration, replayQueue) = try makeSut(flagActive: true)
            defer { sut.close() }

            replayQueue.add(snapshotEvent("1"))
            replayQueue.add(snapshotEvent("2"))
            #expect(replayQueue.bufferDepth == 2)

            integration.applyRemoteConfig(remoteConfig: ["sessionRecording": ["eventTriggers": ["purchase_completed"]]])
            await waitUntil { replayQueue.bufferDepth == 0 }

            #expect(replayQueue.bufferDepth == 0)
            #expect(replayQueue.depth == 0)
            #expect(integration.isBuffering == false)
            // Flag is still on — this is a trigger-gated drop, not a flag-off drop.
            #expect(sut.remoteConfig?.isSessionReplayFlagActive() == true)
        }

        @Test("minimum-duration elapsed does not migrate while awaiting the first remote config")
        func minimumDurationDoesNotMigrateWhileAwaiting() async throws {
            let (sut, integration, replayQueue) = try makeSut(flagActive: true, minimumDurationMilliseconds: 1)
            defer { sut.close() }

            replayQueue.add(snapshotEvent("1"))
            try await Task.sleep(nanoseconds: 20_000_000) // 20ms, well past the 1ms minimum duration
            replayQueue.add(snapshotEvent("2"))

            // The minimum duration has elapsed, but the awaiting gate must keep the buffer in place.
            #expect((replayQueue.bufferDuration ?? 0) > 0.001)
            #expect(replayQueue.bufferDepth == 2)
            #expect(replayQueue.depth == 0)

            // Once the first remote config resolves (flag on) and the minimum duration is met, the
            // held buffer migrates.
            integration.applyRemoteConfig(remoteConfig: nil)
            await waitUntil { replayQueue.bufferDepth == 0 && replayQueue.depth == 2 }
            #expect(replayQueue.depth == 2)
        }

        @Test("first remote config flag on with an unmet minimum duration keeps buffering")
        func firstConfigFlagOnUnderMinimumDurationKeepsBuffer() async throws {
            // A large minimum duration the freshly-buffered window cannot have spanned yet.
            let (sut, integration, replayQueue) = try makeSut(flagActive: true, minimumDurationMilliseconds: 600_000)
            defer { sut.close() }

            replayQueue.add(snapshotEvent("1"))
            replayQueue.add(snapshotEvent("2"))
            #expect(replayQueue.bufferDepth == 2)

            integration.applyRemoteConfig(remoteConfig: nil)

            // Flag is on but the minimum duration isn't met, so the opening window stays buffered (not
            // force-flushed to the persisted queue) and the min-duration gate takes over.
            #expect(replayQueue.depth == 0)
            #expect(replayQueue.bufferDepth == 2)
            #expect(integration.isBuffering == true)
        }

        // MARK: - resolveBufferFromFeatureFlags (post-reset and offline paths)

        @Test("a feature-flags reload before the first remote config does not resolve the buffer")
        func featureFlagsBeforeFirstConfigDoNotResolve() throws {
            let (sut, integration, replayQueue) = try makeSut(flagActive: true)
            defer { sut.close() }

            #expect(integration.isBuffering == true)
            replayQueue.add(snapshotEvent("1"))
            replayQueue.add(snapshotEvent("2"))
            #expect(replayQueue.bufferDepth == 2)

            // No `/config` attempt has completed yet, so a flags reload must not resolve from the
            // pre-`/config` cache — the buffered window stays put.
            sut.remoteConfig?.onFeatureFlagsLoaded.invoke(nil)

            #expect(replayQueue.bufferDepth == 2)
            #expect(replayQueue.depth == 0)
            #expect(integration.isBuffering == true)
        }

        @Test("a session rotation while the first remote config is still pending re-arms, then flags resolve")
        func rotationWhileAwaitingRearmsAndFlagsResolve() async throws {
            let (sut, integration, replayQueue) = try makeSut(flagActive: true)
            defer { sut.close() }

            // Resolve the initial buffer.
            integration.applyRemoteConfig(remoteConfig: nil)
            #expect(integration.isBuffering == false)

            // No `/config` has been fetched yet (disableRemoteConfigForTesting), so a session rotation
            // re-arms the buffer — modelling a rotation during the pre-first-config window. After a
            // `/config` has been fetched this would NOT re-arm (it survives reset, so the gate stays off).
            sut.sessionManager.setSessionId(UUID().uuidString)
            #expect(integration.isBuffering == true)

            replayQueue.add(snapshotEvent("1"))
            replayQueue.add(snapshotEvent("2"))
            #expect(replayQueue.bufferDepth == 2)
            #expect(replayQueue.depth == 0)

            // A feature-flags reload then resolves the re-armed buffer.
            sut.remoteConfig?.onFeatureFlagsLoaded.invoke(nil)
            await waitUntil { replayQueue.bufferDepth == 0 && replayQueue.depth == 2 }
            #expect(replayQueue.depth == 2)
        }

        @Test("a failed first remote config still resolves the buffer via the next feature-flags reload")
        func offlineConfigFailureResolvesViaFeatureFlags() async throws {
            let (sut, integration, replayQueue) = try makeSut(flagActive: true)
            defer { sut.close() }

            replayQueue.add(snapshotEvent("1"))
            replayQueue.add(snapshotEvent("2"))
            #expect(replayQueue.bufferDepth == 2)

            // Offline launch: the first `/config` attempt fails, so `onRemoteConfigLoaded` never fires
            // (applyRemoteConfig is skipped) but the attempt is recorded as completed.
            server.return500 = true
            sut.remoteConfig?.reloadRemoteConfig()
            await waitUntil { sut.remoteConfig?.hasFetchedRemoteConfig == true }
            #expect(integration.isBuffering == true) // still awaiting — applyRemoteConfig didn't run

            // The next flags reload now resolves the buffer from the cached flag (on → migrate).
            sut.remoteConfig?.onFeatureFlagsLoaded.invoke(nil)
            await waitUntil { replayQueue.bufferDepth == 0 && replayQueue.depth == 2 }
            #expect(replayQueue.depth == 2)
        }

        @Test("a feature-flags reload drops the buffer when the cached flag is on but sampled out")
        func featureFlagsResolveDropsWhenSampledOut() async throws {
            // The offline/feature-flags resolve path delegates to the same recordability gate, so a
            // cached flag-on session that the sample rate now excludes must drop, not migrate.
            let (sut, integration, replayQueue) = try makeSut(flagActive: true, sampleRate: 0)
            defer { sut.close() }

            replayQueue.add(snapshotEvent("1"))
            replayQueue.add(snapshotEvent("2"))
            #expect(replayQueue.bufferDepth == 2)

            server.return500 = true
            sut.remoteConfig?.reloadRemoteConfig()
            await waitUntil { sut.remoteConfig?.hasFetchedRemoteConfig == true }

            sut.remoteConfig?.onFeatureFlagsLoaded.invoke(nil)
            await waitUntil { replayQueue.bufferDepth == 0 }
            #expect(replayQueue.bufferDepth == 0)
            #expect(replayQueue.depth == 0)
            #expect(integration.isBuffering == false)
            // The flag is still on, so this is a sampling drop, not a flag-off drop.
            #expect(sut.remoteConfig?.isSessionReplayFlagActive() == true)
            #expect(integration.isActive() == false)
        }

        // MARK: - linkedFlag deferral (the flag value is only fresh after /flags, which follows /config)

        @Test("linkedFlag config defers the first-config resolve to /flags and drops when the flag is now off")
        func linkedFlagDefersToFlagsAndDropsWhenOff() async throws {
            // Returning user with a cached-on linked flag records and buffers the opening window. The
            // fresh config is linkedFlag-gated, so the buffer must NOT resolve on the stale cached flag
            // at /config — it waits for /flags, which reports the flag now off (the mock omits it) → drop.
            let (sut, integration, replayQueue) = try makeSut(
                flagActive: true, linkedFlag: "replay_linked_flag", cachedLinkedFlagValue: true, preloadFeatureFlags: true
            )
            defer { sut.close() }

            replayQueue.add(snapshotEvent("1"))
            replayQueue.add(snapshotEvent("2"))
            #expect(replayQueue.bufferDepth == 2)

            // First /config: linkedFlag-gated + preloadFeatureFlags → deferred, buffer stays armed.
            integration.applyRemoteConfig(remoteConfig: nil)
            #expect(integration.isBuffering == true)
            #expect(replayQueue.bufferDepth == 2)

            // /flags lands without the linked flag → fresh flag off → buffer dropped, nothing sent.
            sut.reloadFeatureFlags()
            await waitUntil { replayQueue.bufferDepth == 0 }
            #expect(replayQueue.bufferDepth == 0)
            #expect(replayQueue.depth == 0)
            #expect(integration.isBuffering == false)
            #expect(sut.remoteConfig?.isSessionReplayFlagActive() == false)
        }

        @Test("linkedFlag config resolves at first /config when preloadFeatureFlags is off")
        func linkedFlagResolvesAtConfigWhenPreloadDisabled() async throws {
            // No /flags reload will follow (preloadFeatureFlags off), so the buffer must resolve at
            // /config against the cached flag rather than wait forever (which would buffer then drop the
            // session — the same data-loss class as the post-reset bug).
            let (sut, integration, replayQueue) = try makeSut(
                flagActive: true, linkedFlag: "replay_linked_flag", cachedLinkedFlagValue: true, preloadFeatureFlags: false
            )
            defer { sut.close() }

            replayQueue.add(snapshotEvent("1"))
            replayQueue.add(snapshotEvent("2"))
            #expect(replayQueue.bufferDepth == 2)

            integration.applyRemoteConfig(remoteConfig: nil)
            await waitUntil { replayQueue.bufferDepth == 0 }
            #expect(integration.isBuffering == false)
            #expect(replayQueue.depth == 2)
        }

        @Test("boolean recording config resolves at first /config even with preloadFeatureFlags on")
        func booleanConfigDoesNotDeferWithPreload() async throws {
            // No linkedFlag → the recording flag is authoritative at /config, so there is nothing to
            // wait for; only linkedFlag-gated configs defer.
            let (sut, integration, replayQueue) = try makeSut(flagActive: true, preloadFeatureFlags: true)
            defer { sut.close() }

            replayQueue.add(snapshotEvent("1"))
            replayQueue.add(snapshotEvent("2"))
            #expect(replayQueue.bufferDepth == 2)

            integration.applyRemoteConfig(remoteConfig: nil)
            await waitUntil { replayQueue.bufferDepth == 0 }
            #expect(integration.isBuffering == false)
            #expect(replayQueue.depth == 2)
        }
    }
#endif
