#if os(iOS) && (!SWIFT_PACKAGE || SessionReplay)
    import Foundation
    @_spi(PostHogInternal) @testable import PostHog
    import Testing

    @Suite("Session Replay Remote Masking", .serialized)
    class PostHogSessionReplayRemoteMaskingTests {
        let server: MockPostHogServer

        init() {
            server = MockPostHogServer()
            server.start()
        }

        deinit {
            server.stop()
        }

        private func makeSut(
            liveConfig: Bool,
            localMaskText: Bool = false,
            localMaskImages: Bool = false,
            minimumDurationMilliseconds: Int? = nil,
            cachedMasking: [String: Any]? = nil
        ) throws -> (sut: PostHogSDK, integration: PostHogReplayIntegration, replayQueue: PostHogReplayQueue) {
            let config = PostHogConfig(projectToken: UUID().uuidString, host: "http://localhost:9001")
            config.sessionReplay = true
            config.sessionReplayConfig.maskAllTextInputs = localMaskText
            config.sessionReplayConfig.maskAllImages = localMaskImages
            config.disableReachabilityForTesting = true
            config.disableQueueTimerForTesting = true
            config.preloadFeatureFlags = false
            config.flushAt = 1000
            config.disableRemoteConfigForTesting = !liveConfig

            var sessionRecording: [String: Any] = ["endpoint": "/s/"]
            if let minimumDurationMilliseconds {
                sessionRecording["minimumDurationMilliseconds"] = minimumDurationMilliseconds
            }
            if let cachedMasking {
                sessionRecording["masking"] = cachedMasking
            }
            PostHogStorage(config).setDictionary(forKey: .remoteConfig, contents: ["sessionRecording": sessionRecording])

            PostHogReplayIntegration.clearInstalls()

            let sut = PostHogSDK.with(config)
            return (sut, try #require(sut.getReplayIntegration()), try #require(sut.replayQueue))
        }

        private func snapshotEvent(_ name: String) -> PostHogEvent {
            PostHogEvent(event: "$snapshot", distinctId: "test-user", properties: ["name": name])
        }

        private func remoteConfig(masking: [String: Any]?) -> [String: Any] {
            var sessionRecording: [String: Any] = ["endpoint": "/s/"]
            if let masking {
                sessionRecording["masking"] = masking
            }
            return ["sessionRecording": sessionRecording]
        }

        @Test("a server mask turned on by the live config drops the buffer and resolves true")
        func serverMaskDropsBuffer() async throws {
            server.returnReplay = true
            server.sessionRecordingMasking = ["mobile": ["maskAllText": true]]
            server.configResponseDelay = 0.5
            let (sut, integration, replayQueue) = try makeSut(liveConfig: true)
            defer { sut.close() }

            #expect(integration.resolvedMasking().maskAllTextInputs == false)

            replayQueue.add(snapshotEvent("1"))
            replayQueue.add(snapshotEvent("2"))
            #expect(replayQueue.bufferDepth == 2)

            await waitUntil(timeout: 10) { integration.resolvedMasking().maskAllTextInputs }
            await waitUntil { replayQueue.bufferDepth == 0 && integration.isBuffering == false }

            #expect(integration.resolvedMasking().maskAllTextInputs == true)
            #expect(integration.resolvedMasking().maskAllImages == false)
            #expect(sut.sessionReplayResolvedMasking()["maskAllTextInputs"] == true)
            #expect(sut.sessionReplayResolvedMasking()["maskAllImages"] == false)
            #expect(replayQueue.bufferDepth == 0)
            #expect(replayQueue.depth == 0)
        }

        @Test("no server mask leaves the buffer to migrate")
        func noServerMaskMigratesBuffer() async throws {
            server.returnReplay = true
            server.sessionRecordingMasking = nil
            server.configResponseDelay = 0.5
            let (sut, integration, replayQueue) = try makeSut(liveConfig: true)
            defer { sut.close() }

            replayQueue.add(snapshotEvent("1"))
            replayQueue.add(snapshotEvent("2"))
            #expect(replayQueue.bufferDepth == 2)

            await waitUntil(timeout: 10) { replayQueue.bufferDepth == 0 && replayQueue.depth == 2 }

            #expect(replayQueue.depth == 2)
            #expect(integration.resolvedMasking().maskAllTextInputs == false)
            #expect(integration.resolvedMasking().maskAllImages == false)
        }

        @Test("without a resolved value the local flags are returned")
        func localFlagsWithoutRemoteMasking() throws {
            let (sut, integration, _) = try makeSut(liveConfig: false, localMaskText: true, localMaskImages: false)
            defer { sut.close() }

            #expect(integration.resolvedMasking().maskAllTextInputs == true)
            #expect(integration.resolvedMasking().maskAllImages == false)
            #expect(sut.sessionReplayResolvedMasking() == ["maskAllTextInputs": true, "maskAllImages": false])
        }

        @Test("a later config that turns a flag on drops frames held for the minimum duration")
        func laterConfigTurningFlagOnDropsBuffer() async throws {
            let (sut, integration, replayQueue) = try makeSut(liveConfig: false, minimumDurationMilliseconds: 600_000)
            defer { sut.close() }

            replayQueue.add(snapshotEvent("1"))
            integration.applyRemoteConfig(remoteConfig: remoteConfig(masking: nil))
            replayQueue.add(snapshotEvent("2"))
            #expect(replayQueue.bufferDepth == 2)
            #expect(replayQueue.depth == 0)

            integration.applyRemoteConfig(remoteConfig: remoteConfig(masking: ["mobile": ["maskAllImages": true]]))
            await waitUntil { replayQueue.bufferDepth == 0 }

            #expect(replayQueue.bufferDepth == 0)
            #expect(replayQueue.depth == 0)
            #expect(integration.resolvedMasking().maskAllImages == true)
            #expect(integration.resolvedMasking().maskAllTextInputs == false)
        }

        @Test("a config that repeats an already-on flag does not drop the buffer")
        func repeatedFlagDoesNotDropBuffer() async throws {
            let (sut, integration, replayQueue) = try makeSut(liveConfig: false, minimumDurationMilliseconds: 600_000)
            defer { sut.close() }

            let masking: [String: Any] = ["mobile": ["maskAllText": true]]
            integration.applyRemoteConfig(remoteConfig: remoteConfig(masking: masking))
            replayQueue.add(snapshotEvent("1"))
            replayQueue.add(snapshotEvent("2"))
            #expect(replayQueue.bufferDepth == 2)

            integration.applyRemoteConfig(remoteConfig: remoteConfig(masking: masking))
            try await Task.sleep(nanoseconds: 200_000_000)

            #expect(replayQueue.bufferDepth == 2)
            #expect(integration.resolvedMasking().maskAllTextInputs == true)
        }

        @Test("a cached server mask applies from install and does not drop later frames")
        func cachedMaskAppliesAtInstall() async throws {
            let (sut, integration, replayQueue) = try makeSut(
                liveConfig: false,
                minimumDurationMilliseconds: 600_000,
                cachedMasking: ["mobile": ["maskAllText": true]]
            )
            defer { sut.close() }

            #expect(integration.resolvedMasking().maskAllTextInputs == true)

            replayQueue.add(snapshotEvent("1"))
            integration.applyRemoteConfig(remoteConfig: remoteConfig(masking: ["mobile": ["maskAllText": true]]))
            try await Task.sleep(nanoseconds: 200_000_000)

            #expect(replayQueue.bufferDepth == 1)
        }
    }
#endif
