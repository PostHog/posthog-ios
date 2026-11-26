#if os(iOS) && (!SWIFT_PACKAGE || SessionReplay)
    import Foundation
    @_spi(PostHogInternal) @testable import PostHog
    import Testing
    import UIKit

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
            cachedMasking: [String: Any]? = nil,
            beforeSend: ((PostHogEvent) -> PostHogEvent?)? = nil
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
            if let beforeSend {
                config.setBeforeSend(beforeSend)
            }

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

        @Test("without a server mask the local flags are returned")
        func localFlagsWithoutRemoteMasking() throws {
            let (sut, integration, _) = try makeSut(liveConfig: false, localMaskText: true, localMaskImages: false)
            defer { sut.close() }

            #expect(integration.resolvedMasking().maskAllTextInputs == true)
            #expect(integration.resolvedMasking().maskAllImages == false)
            #expect(sut.sessionReplayResolvedMasking() == ["maskAllTextInputs": true, "maskAllImages": false])
        }

        @Test("a local flag changed after install still applies, and cannot turn a server mask off")
        func localFlagChangesAfterInstallApply() throws {
            let (sut, integration, _) = try makeSut(liveConfig: false, cachedMasking: ["mobile": ["maskAllText": true]])
            defer { sut.close() }

            #expect(integration.resolvedMasking().maskAllImages == false)
            sut.config.sessionReplayConfig.maskAllImages = true
            #expect(integration.resolvedMasking().maskAllImages == true)
            sut.config.sessionReplayConfig.maskAllImages = false
            #expect(integration.resolvedMasking().maskAllImages == false)

            sut.config.sessionReplayConfig.maskAllTextInputs = true
            sut.config.sessionReplayConfig.maskAllTextInputs = false
            #expect(integration.resolvedMasking().maskAllTextInputs == true)
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

        @Test("the first frame after a mask turns on is sent again with its meta event")
        @MainActor
        func frameAfterDropCarriesMetaEvent() throws {
            let lock = NSLock()
            var sentTypes: [[Int]] = []
            let (sut, integration, _) = try makeSut(liveConfig: false, beforeSend: { event in
                if event.event == "$snapshot", let data = event.properties["$snapshot_data"] as? [[String: Any]] {
                    lock.withLock { sentTypes.append(data.compactMap { $0["type"] as? Int }) }
                }
                return nil
            })
            defer { sut.close() }
            let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 640))

            func sendFrame() {
                let wireframe = RRScreenshotFrame()
                wireframe.type = "screenshot"
                wireframe.base64 = "Screen"
                wireframe.maskingGeneration = integration.currentMaskingGeneration
                integration.captureSnapshot(
                    wireframe,
                    window: window,
                    windowSize: window.bounds.size,
                    screenName: nil,
                    postHog: sut,
                    timestampDate: Date()
                )
                PostHogReplayIntegration.dispatchQueue.sync {}
            }

            sendFrame()
            sendFrame()
            #expect(lock.withLock { sentTypes } == [[4, 2]])

            integration.applyRemoteConfig(remoteConfig: remoteConfig(masking: ["mobile": ["maskAllText": true]]))
            sendFrame()
            #expect(lock.withLock { sentTypes } == [[4, 2], [4, 2]])
        }

        @Test("a frame collected before a mask turns on is dropped instead of queued")
        @MainActor
        func frameCollectedBeforeMaskTurnsOnIsDropped() throws {
            let lock = NSLock()
            var sent: [String] = []
            let (sut, integration, _) = try makeSut(liveConfig: false, beforeSend: { event in
                if event.event == "$snapshot", let data = event.properties["$snapshot_data"] as? [[String: Any]] {
                    let frames = data.compactMap { (($0["data"] as? [String: Any])?["wireframes"] as? [[String: Any]])?.first?["base64"] as? String }
                    lock.withLock { sent.append(contentsOf: frames) }
                }
                return nil
            })
            defer { sut.close() }
            let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 640))

            func collectFrame(_ name: String) -> RRScreenshotFrame {
                let wireframe = RRScreenshotFrame()
                wireframe.type = "screenshot"
                wireframe.base64 = name
                wireframe.maskingGeneration = integration.currentMaskingGeneration
                return wireframe
            }
            func enqueue(_ wireframe: RRScreenshotFrame) {
                integration.captureSnapshot(
                    wireframe,
                    window: window,
                    windowSize: window.bounds.size,
                    screenName: nil,
                    postHog: sut,
                    timestampDate: Date()
                )
                PostHogReplayIntegration.dispatchQueue.sync {}
            }

            let collectedBefore = collectFrame("before")
            integration.applyRemoteConfig(remoteConfig: remoteConfig(masking: ["mobile": ["maskAllText": true]]))
            enqueue(collectedBefore)
            #expect(lock.withLock { sent }.isEmpty)

            // A config that repeats the flag is not a new turn-on, so a frame collected before it goes through.
            let collectedAfter = collectFrame("after")
            integration.applyRemoteConfig(remoteConfig: remoteConfig(masking: ["mobile": ["maskAllText": true]]))
            enqueue(collectedAfter)
            #expect(lock.withLock { sent } == ["after"])
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

        @Test("a server mask over a local false is logged once per flag, and not when the local flag is on")
        func serverMaskIsLoggedOncePerFlag() throws {
            let masking: [String: Any] = ["mobile": ["maskAllText": true]]

            let (sut, integration, _) = try makeSut(liveConfig: false)
            defer { sut.close() }
            #expect(integration.loggedMaskFlagsForTesting.isEmpty)
            integration.applyRemoteConfig(remoteConfig: remoteConfig(masking: masking))
            integration.applyRemoteConfig(remoteConfig: remoteConfig(masking: masking))
            #expect(integration.loggedMaskFlagsForTesting == ["maskAllTextInputs"])
            integration.applyRemoteConfig(remoteConfig: remoteConfig(masking: ["mobile": ["maskAllText": true, "maskAllImages": true]]))
            #expect(integration.loggedMaskFlagsForTesting == ["maskAllTextInputs", "maskAllImages"])

            let (localSut, localIntegration, _) = try makeSut(liveConfig: false, localMaskText: true)
            defer { localSut.close() }
            localIntegration.applyRemoteConfig(remoteConfig: remoteConfig(masking: masking))
            localIntegration.applyRemoteConfig(remoteConfig: remoteConfig(masking: masking))
            #expect(localIntegration.loggedMaskFlagsForTesting.isEmpty)
        }

        @Test("a later config with session recording off resets the stored server mask")
        func sessionRecordingOffResetsServerMask() throws {
            let (sut, integration, _) = try makeSut(liveConfig: false, localMaskImages: true)
            defer { sut.close() }

            integration.applyRemoteConfig(remoteConfig: remoteConfig(masking: ["mobile": ["maskAllText": true]]))
            #expect(integration.resolvedMasking().maskAllTextInputs == true)

            integration.applyRemoteConfig(remoteConfig: ["sessionRecording": false])
            #expect(integration.resolvedMasking().maskAllTextInputs == false)
            #expect(integration.resolvedMasking().maskAllImages == true)
        }

        @Test("the stored server mask survives a reset")
        func serverMaskSurvivesReset() throws {
            let (sut, integration, _) = try makeSut(liveConfig: false, cachedMasking: ["mobile": ["maskAllText": true]])
            defer { sut.close() }

            #expect(integration.resolvedMasking().maskAllTextInputs == true)
            sut.reset()
            #expect(integration.resolvedMasking().maskAllTextInputs == true)
        }

        @Test("a failed first config keeps the cached server mask")
        func failedFirstConfigKeepsCachedMask() async throws {
            server.return500 = true
            let (sut, integration, _) = try makeSut(liveConfig: true, cachedMasking: ["mobile": ["maskAllText": true]])
            defer { sut.close() }

            #expect(integration.resolvedMasking().maskAllTextInputs == true)
            let deadline = Date().addingTimeInterval(5)
            while sut.remoteConfig?.hasFetchedRemoteConfig != true, Date() < deadline {
                try await Task.sleep(nanoseconds: 20_000_000)
            }
            #expect(sut.remoteConfig?.hasFetchedRemoteConfig == true)
            // Any listener notification is posted to main; let it run.
            await MainActor.run {}
            #expect(integration.resolvedMasking().maskAllTextInputs == true)
            #expect(integration.currentMaskingGeneration == 0)
        }

        @Test("a buffered frame stamped before a mask turned on is dropped, a current one is buffered")
        func staleFrameIsNotBuffered() throws {
            let (sut, integration, replayQueue) = try makeSut(liveConfig: false, minimumDurationMilliseconds: 600_000)
            defer { sut.close() }
            #expect(integration.isBuffering == true)

            integration.bumpMaskingGenerationForTesting()
            let current = integration.currentMaskingGeneration

            PostHogReplayIntegration.withCaptureMaskingGeneration(current - 1) {
                replayQueue.add(snapshotEvent("stale"))
            }
            #expect(replayQueue.bufferDepth == 0)
            #expect(replayQueue.depth == 0)

            PostHogReplayIntegration.withCaptureMaskingGeneration(current) {
                replayQueue.add(snapshotEvent("current"))
            }
            #expect(replayQueue.bufferDepth == 1)
            #expect(replayQueue.depth == 0)
        }

        @Test("a stale frame is not added to the replay queue when not buffering")
        func staleFrameIsNotQueuedDirectly() throws {
            let (sut, integration, replayQueue) = try makeSut(liveConfig: false)
            defer { sut.close() }
            integration.applyRemoteConfig(remoteConfig: remoteConfig(masking: nil))
            #expect(integration.isBuffering == false)

            integration.bumpMaskingGenerationForTesting()
            let current = integration.currentMaskingGeneration

            PostHogReplayIntegration.withCaptureMaskingGeneration(current - 1) {
                replayQueue.add(snapshotEvent("stale"))
            }
            #expect(replayQueue.depth == 0)

            PostHogReplayIntegration.withCaptureMaskingGeneration(current) {
                replayQueue.add(snapshotEvent("current"))
            }
            #expect(replayQueue.depth == 1)
        }

        @Test("the buffer is not migrated between a mask turning on and the clear")
        func bufferIsNotMigratedAfterGenerationBump() async throws {
            let (sut, integration, replayQueue) = try makeSut(liveConfig: false, minimumDurationMilliseconds: 600_000)
            defer { sut.close() }

            replayQueue.add(snapshotEvent("1"))
            replayQueue.add(snapshotEvent("2"))
            #expect(replayQueue.bufferDepth == 2)

            integration.bumpMaskingGenerationForTesting()
            PostHogReplayIntegration.withCaptureMaskingGeneration(integration.currentMaskingGeneration) {
                replayQueue.add(snapshotEvent("3"))
            }
            replayQueue.migrateBufferToQueue()
            try await Task.sleep(nanoseconds: 200_000_000)

            #expect(replayQueue.depth == 0)
            #expect(replayQueue.bufferDepth == 3)
        }

        @Test("a cached server mask at install is not a turn-on")
        func cachedMaskAtInstallIsNotATransition() throws {
            let (sut, integration, _) = try makeSut(liveConfig: false, cachedMasking: ["mobile": ["maskAllText": true]])
            defer { sut.close() }

            #expect(integration.resolvedMasking().maskAllTextInputs == true)
            #expect(integration.currentMaskingGeneration == 0)
            #expect(integration.loggedMaskFlagsForTesting == ["maskAllTextInputs"])
        }

        @Test("flags notification queued before /config notification must not migrate unmasked opening buffer")
        @MainActor
        func bootstrapFlagsDoesNotMigrateUnmaskedBuffer() async throws {
            server.returnReplay = true
            server.sessionRecordingMasking = ["mobile": ["maskAllText": true]]
            server.configResponseDelay = 0.05

            let config = PostHogConfig(projectToken: UUID().uuidString, host: "http://localhost:9001")
            config.sessionReplay = true
            config.sessionReplayConfig.maskAllTextInputs = false
            config.sessionReplayConfig.maskAllImages = false
            config.bootstrap = PostHogBootstrapConfig(featureFlags: ["beta-ui": true], featureFlagPayloads: nil)
            config.disableReachabilityForTesting = true
            config.disableQueueTimerForTesting = true
            config.preloadFeatureFlags = false
            config.flushAt = 1000
            config.disableRemoteConfigForTesting = false

            PostHogStorage(config).setDictionary(forKey: .remoteConfig, contents: ["sessionRecording": ["endpoint": "/s/"]])
            PostHogReplayIntegration.clearInstalls()

            let sut = PostHogSDK.with(config)
            defer { sut.close() }
            let integration = try #require(sut.getReplayIntegration())
            let replayQueue = try #require(sut.replayQueue)

            replayQueue.add(snapshotEvent("unmasked-opening"))
            #expect(replayQueue.bufferDepth == 1)
            #expect(replayQueue.depth == 0)

            let deadline = Date().addingTimeInterval(5)
            while sut.remoteConfig?.hasFetchedRemoteConfig != true, Date() < deadline {
                usleep(1_000)
            }
            #expect(sut.remoteConfig?.hasFetchedRemoteConfig == true)

            let observed = NotificationCenter.default.addObserver(
                forName: PostHogSDK.didStartNotification,
                object: nil,
                queue: nil
            ) { _ in
                usleep(20_000)
            }
            defer { NotificationCenter.default.removeObserver(observed) }

            await waitUntil(timeout: 5) { integration.resolvedMasking().maskAllTextInputs }
            await waitUntil(timeout: 5) { replayQueue.bufferDepth == 0 }

            #expect(replayQueue.depth == 0)
        }

        @Test("dropping an opening buffer for stricter masking on main does not bypass minimumDurationMilliseconds")
        @MainActor
        func stricterMaskOnFirstConfigKeepsMinimumDurationBuffering() async throws {
            let (sut, integration, replayQueue) = try makeSut(
                liveConfig: false,
                localMaskText: false,
                minimumDurationMilliseconds: 100
            )
            defer { sut.close() }

            replayQueue.add(snapshotEvent("1"))
            try await Task.sleep(nanoseconds: 150_000_000)
            replayQueue.add(snapshotEvent("2"))
            #expect(replayQueue.bufferDepth == 2)

            integration.applyRemoteConfig(remoteConfig: [
                "sessionRecording": [
                    "endpoint": "/s/",
                    "minimumDurationMilliseconds": 100,
                    "masking": ["mobile": ["maskAllText": true]],
                ],
            ])
            await waitUntil { replayQueue.bufferDepth == 0 }

            #expect(replayQueue.depth == 0)
            #expect(integration.isBuffering == true)

            PostHogReplayIntegration.withCaptureMaskingGeneration(integration.currentMaskingGeneration) {
                replayQueue.add(snapshotEvent("3"))
            }
            #expect(replayQueue.bufferDepth == 1)
            #expect(replayQueue.depth == 0)
        }

        @Test("a buffer about to be dropped for a mask turn-on does not pass the minimum duration")
        func staleBufferDoesNotPassMinimumDuration() async throws {
            let (sut, integration, replayQueue) = try makeSut(liveConfig: false, minimumDurationMilliseconds: 100)
            defer { sut.close() }
            integration.applyRemoteConfig(remoteConfig: remoteConfig(masking: nil))
            #expect(integration.isBuffering == true)

            replayQueue.add(snapshotEvent("1"))
            try await Task.sleep(nanoseconds: 150_000_000)
            // The window between the generation bump and the buffer clear.
            integration.bumpMaskingGenerationForTesting()
            PostHogReplayIntegration.withCaptureMaskingGeneration(integration.currentMaskingGeneration) {
                replayQueue.add(snapshotEvent("2"))
            }

            #expect(replayQueue.depth == 0)
            #expect(integration.isBuffering == true)
        }

        @Test("gen-1 opening frame added immediately after main-thread masking turn-on survives prior clear")
        @MainActor
        func postDropOpeningFrameSurvivesMainThreadClear() async throws {
            let (sut, integration, replayQueue) = try makeSut(
                liveConfig: false,
                localMaskText: false,
                minimumDurationMilliseconds: 600_000
            )
            defer { sut.close() }

            var lostCount = 0
            for i in 0 ..< 10 {
                let isText = (i % 2 == 0)
                integration.applyRemoteConfig(remoteConfig: remoteConfig(masking: nil))
                replayQueue.add(snapshotEvent("gen0_\(i)"))
                #expect(replayQueue.bufferDepth >= 1)

                let flag = isText ? "maskAllText" : "maskAllImages"
                integration.applyRemoteConfig(remoteConfig: remoteConfig(masking: ["mobile": [flag: true]]))
                PostHogReplayIntegration.withCaptureMaskingGeneration(integration.currentMaskingGeneration) {
                    replayQueue.add(snapshotEvent("gen1_opening_\(i)"))
                }

                try await Task.sleep(nanoseconds: 100_000_000)
                if replayQueue.bufferDepth == 0 {
                    lostCount += 1
                }
                replayQueue.clear()
            }
            #expect(lostCount == 0)
        }

        @Test("off-main setup: /config landing between cache read and subscribe must still apply the mask")
        func configLostDuringOffMainInstall() async throws {
            server.returnReplay = true
            server.sessionRecordingMasking = ["mobile": ["maskAllText": true]]
            server.configResponseDelay = 0.05
            PostHogReplayIntegration.beforeRemoteConfigSubscribeForTesting = { Thread.sleep(forTimeInterval: 0.4) }
            defer { PostHogReplayIntegration.beforeRemoteConfigSubscribeForTesting = nil }

            let config = PostHogConfig(projectToken: UUID().uuidString, host: "http://localhost:9001")
            config.sessionReplay = true
            config.sessionReplayConfig.maskAllTextInputs = false
            config.sessionReplayConfig.maskAllImages = false
            config.disableReachabilityForTesting = true
            config.disableQueueTimerForTesting = true
            config.preloadFeatureFlags = false
            config.flushAt = 1000
            config.disableRemoteConfigForTesting = false
            PostHogStorage(config).setDictionary(forKey: .remoteConfig, contents: ["sessionRecording": ["endpoint": "/s/"]])
            PostHogReplayIntegration.clearInstalls()

            let sut: PostHogSDK = await withCheckedContinuation { cont in
                DispatchQueue.global().async { cont.resume(returning: PostHogSDK.with(config)) }
            }
            defer { sut.close() }
            let integration = try #require(sut.getReplayIntegration())

            await waitUntil(timeout: 3) { sut.remoteConfig?.hasFetchedRemoteConfig == true }
            await MainActor.run {}
            #expect(integration.resolvedMasking().maskAllTextInputs == true)
        }

        @Test("a server mask masks real labels and images, and ph-no-mask still wins")
        @MainActor
        func serverMaskAppliesToViewHierarchy() throws {
            let (sut, integration, _) = try makeSut(liveConfig: false)
            defer { sut.close() }

            let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 640))
            let label = UILabel(frame: CGRect(x: 10, y: 10, width: 200, height: 30))
            label.text = "secret"
            let imageView = UIImageView(frame: CGRect(x: 10, y: 60, width: 100, height: 100))
            imageView.image = UIGraphicsImageRenderer(size: CGSize(width: 10, height: 10)).image { context in
                UIColor.red.setFill()
                context.fill(CGRect(x: 0, y: 0, width: 10, height: 10))
            }
            let unmaskedLabel = UILabel(frame: CGRect(x: 10, y: 200, width: 200, height: 30))
            unmaskedLabel.text = "public"
            unmaskedLabel.accessibilityIdentifier = "ph-no-mask"
            for view in [label, imageView, unmaskedLabel] {
                window.addSubview(view)
            }
            window.isHidden = false
            defer { window.isHidden = true }

            func isMasked(_ view: UIView) -> Bool {
                (integration.collectMaskableRects(in: window) ?? []).contains { $0.intersects(view.frame) }
            }

            #expect(!isMasked(label))
            #expect(!isMasked(imageView))

            integration.applyRemoteConfig(remoteConfig: remoteConfig(masking: ["mobile": ["maskAllText": true]]))
            #expect(isMasked(label))
            #expect(!isMasked(imageView))
            #expect(!isMasked(unmaskedLabel))

            integration.applyRemoteConfig(remoteConfig: remoteConfig(masking: ["mobile": ["maskAllText": true, "maskAllImages": true]]))
            #expect(isMasked(label))
            #expect(isMasked(imageView))
            #expect(!isMasked(unmaskedLabel))
        }

        @Test("a server mask turned off mid-session reverts to the local flags and keeps the buffer")
        func serverMaskTurnedOffKeepsBuffer() async throws {
            let (sut, integration, replayQueue) = try makeSut(
                liveConfig: false,
                localMaskImages: true,
                minimumDurationMilliseconds: 600_000
            )
            defer { sut.close() }

            integration.applyRemoteConfig(remoteConfig: remoteConfig(masking: ["mobile": ["maskAllText": true]]))
            #expect(integration.resolvedMasking().maskAllTextInputs == true)
            let generation = integration.currentMaskingGeneration
            PostHogReplayIntegration.withCaptureMaskingGeneration(generation) {
                replayQueue.add(snapshotEvent("1"))
                replayQueue.add(snapshotEvent("2"))
            }
            #expect(replayQueue.bufferDepth == 2)

            integration.applyRemoteConfig(remoteConfig: remoteConfig(masking: ["mobile": ["maskAllText": false]]))
            try await Task.sleep(nanoseconds: 200_000_000)

            #expect(integration.resolvedMasking().maskAllTextInputs == false)
            #expect(integration.resolvedMasking().maskAllImages == true)
            #expect(integration.currentMaskingGeneration == generation)
            #expect(replayQueue.bufferDepth == 2)
            #expect(integration.isBuffering == true)
        }

        @Test("without an installed replay integration the resolved masking falls back to the local config")
        func resolvedMaskingFallsBackWithoutReplay() throws {
            let config = PostHogConfig(projectToken: UUID().uuidString, host: "http://localhost:9001")
            config.sessionReplay = false
            config.sessionReplayConfig.maskAllTextInputs = true
            config.sessionReplayConfig.maskAllImages = false
            config.disableReachabilityForTesting = true
            config.disableQueueTimerForTesting = true
            config.preloadFeatureFlags = false
            config.disableRemoteConfigForTesting = true
            PostHogReplayIntegration.clearInstalls()

            let sut = PostHogSDK.with(config)
            defer { sut.close() }

            #expect(sut.getReplayIntegration() == nil)
            #expect(sut.sessionReplayResolvedMasking() == ["maskAllTextInputs": true, "maskAllImages": false])

            sut.config.sessionReplayConfig.maskAllImages = true
            #expect(sut.sessionReplayResolvedMasking() == ["maskAllTextInputs": true, "maskAllImages": true])
        }

        @Test("mask turn-on wakes capture backoff")
        @MainActor
        func maskTurnOnWakesBackoff() async throws {
            let (sut, integration, _) = try makeSut(liveConfig: false)
            defer { sut.close() }
            let backoff = integration.captureBackoffForTesting
            for _ in 0 ..< 12 {
                backoff.noteFrame(unchanged: true)
            }
            #expect(backoff.isInBackoffForTesting == true)

            integration.applyRemoteConfig(remoteConfig: remoteConfig(masking: ["mobile": ["maskAllText": true]]))
            #expect(backoff.isInBackoffForTesting == false)
        }
    }
#endif
