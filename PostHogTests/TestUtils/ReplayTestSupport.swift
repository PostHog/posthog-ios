#if os(iOS)
    import Foundation
    @testable import PostHog
    import Testing

    /// Records the `$snapshot` data a replay SUT sends, instead of uploading it.
    final class ReplaySnapshots {
        private let lock = NSLock()
        private var values: [[String: Any]] = []

        func record(_ event: PostHogEvent) {
            guard event.event == "$snapshot",
                  let data = event.properties["$snapshot_data"] as? [[String: Any]]
            else { return }
            lock.withLock { values.append(contentsOf: data) }
        }

        var touches: [[String: Any]] {
            lock.withLock {
                values.filter { $0["type"] as? Int == 3 }
                    .compactMap { $0["data"] as? [String: Any] }
                    .filter { $0["source"] as? Int == 2 }
            }
        }

        var screenshots: [[String: Any]] {
            lock.withLock {
                values.filter { $0["type"] as? Int == 2 }
                    .compactMap { $0["data"] as? [String: Any] }
                    .flatMap { $0["wireframes"] as? [[String: Any]] ?? [] }
                    .filter { $0["type"] as? String == "screenshot" }
            }
        }
    }

    /// An SDK recording screenshot-mode replay, its replay integration, and what it sends.
    /// `configure` adjusts the replay config before setup.
    func makeScreenshotReplaySut(
        configure: (PostHogSessionReplayConfig) -> Void = { _ in }
    ) throws -> (PostHogSDK, PostHogReplayIntegration, ReplaySnapshots) {
        let config = PostHogConfig(projectToken: UUID().uuidString)
        config.sessionReplay = true
        config.sessionReplayConfig.screenshotMode = true
        config.sessionReplayConfig.captureNetworkTelemetry = false
        configure(config.sessionReplayConfig)
        config.disableReachabilityForTesting = true
        config.disableQueueTimerForTesting = true
        config.disableFlushOnBackgroundForTesting = true
        config.disableRemoteConfigForTesting = true
        config.preloadFeatureFlags = false
        config.captureApplicationLifecycleEvents = false
        config.captureScreenViews = false
        let snapshots = ReplaySnapshots()
        config.setBeforeSend { event in
            snapshots.record(event)
            return nil
        }
        PostHogStorage(config).setDictionary(forKey: .remoteConfig, contents: ["sessionRecording": ["endpoint": "/s/"]])
        PostHogReplayIntegration.clearInstalls()
        let sut = PostHogSDK.with(config)
        let integration = try #require(sut.getReplayIntegration())
        #expect(sut.isSessionReplayActive())
        return (sut, integration, snapshots)
    }

    /// Waits for work already queued on the replay queue, such as snapshot serialization.
    func drainReplayQueue() async {
        await withCheckedContinuation { continuation in
            PostHogReplayIntegration.dispatchQueue.async { continuation.resume() }
        }
    }
#endif
