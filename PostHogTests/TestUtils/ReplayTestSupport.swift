#if os(iOS) && (!SWIFT_PACKAGE || SessionReplay)
    import Foundation
    @testable import PostHog
    import Testing
    import UIKit

    /// Records the `$snapshot` data a replay SUT sends, instead of uploading it.
    final class ReplaySnapshots {
        private let lock = NSLock()
        private var values: [[String: Any]] = []
        private var recordedPosts: [(sessionId: String?, data: [[String: Any]])] = []

        func record(_ event: PostHogEvent) {
            guard event.event == "$snapshot",
                  let data = event.properties["$snapshot_data"] as? [[String: Any]]
            else { return }
            lock.withLock {
                values.append(contentsOf: data)
                recordedPosts.append((event.properties["$session_id"] as? String, data))
            }
        }

        /// Each `$snapshot` event with the session it was sent under, in the order they were sent.
        var posts: [(sessionId: String?, data: [[String: Any]])] {
            lock.withLock { recordedPosts }
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

        /// The `href` of each meta event, in the order they were sent.
        var metaHrefs: [String?] {
            lock.withLock {
                values.filter { $0["type"] as? Int == 4 }
                    .map { ($0["data"] as? [String: Any])?["href"] as? String }
            }
        }

        /// The first uploaded screenshot, decoded.
        func firstScreenshotImage() throws -> CGImage {
            let screenshot = try #require(screenshots.first)
            let base64 = try #require((screenshot["base64"] as? String)?.components(separatedBy: ",").last)
            let data = try #require(Data(base64Encoded: base64))
            return try #require(UIImage(data: data)?.cgImage)
        }
    }

    /// An SDK recording screenshot-mode replay, its replay integration, and what it sends.
    /// `configure` adjusts the replay config before setup.
    func makeScreenshotReplaySut(
        configure: (PostHogSessionReplayConfig) -> Void = { _ in }
    ) throws -> (PostHogSDK, PostHogReplayIntegration, ReplaySnapshots) {
        let config = PostHogConfig(projectToken: UUID().uuidString)
        config.sessionReplay = true
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

    /// Waits for a capture to give the render slot back, then for the snapshot it queued.
    @MainActor
    func waitForCaptureToFinish(_ integration: PostHogReplayIntegration) async {
        await waitUntil(timeout: 5) { !integration.isScreenshotRenderInFlightForTesting }
        #expect(!integration.isScreenshotRenderInFlightForTesting)
        await drainReplayQueue()
    }

    /// Runs `body` while the replay queue is held, then waits for the work it queued.
    @MainActor
    func withReplayQueueHeld(_ body: () -> Void) {
        let queue = PostHogReplayIntegration.dispatchQueue
        queue.suspend()
        body()
        queue.resume()
        queue.sync {}
    }

    /// Waits for work already queued on the replay queue, such as snapshot serialization.
    func drainReplayQueue() async {
        await withCheckedContinuation { continuation in
            PostHogReplayIntegration.dispatchQueue.async { continuation.resume() }
        }
    }
#endif
