#if os(iOS)
    import Foundation
    @testable import PostHog
    import Testing
    import UIKit

    @Suite("Replay touch capture", .serialized)
    @MainActor
    struct PostHogReplayCaptureTouchesTests {
        private final class Touch: UITouch {
            private let recordedPhase: UITouch.Phase

            init(phase: UITouch.Phase) {
                recordedPhase = phase
                super.init()
            }

            override var phase: UITouch.Phase { recordedPhase }
            override func location(in _: UIView?) -> CGPoint {
                CGPoint(x: 123, y: 456)
            }
        }

        private final class TouchEvent: UIEvent {
            var touchesRead = false
            override var type: UIEvent.EventType { .touches }
            override func touches(for _: UIWindow) -> Set<UITouch>? {
                touchesRead = true
                return [Touch(phase: .began), Touch(phase: .ended)]
            }
        }

        private final class Snapshots {
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

        private func makeSut(captureTouches: Bool? = nil) throws -> (PostHogSDK, PostHogReplayIntegration, Snapshots) {
            let config = PostHogConfig(projectToken: UUID().uuidString)
            config.sessionReplay = true
            config.sessionReplayConfig.screenshotMode = true
            config.sessionReplayConfig.captureNetworkTelemetry = false
            if let captureTouches {
                config.sessionReplayConfig.captureTouches = captureTouches
            }
            config.disableReachabilityForTesting = true
            config.disableQueueTimerForTesting = true
            config.disableFlushOnBackgroundForTesting = true
            config.disableRemoteConfigForTesting = true
            config.preloadFeatureFlags = false
            config.captureApplicationLifecycleEvents = false
            config.captureScreenViews = false
            let snapshots = Snapshots()
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

        private func drainReplayQueue() async {
            await withCheckedContinuation { continuation in
                PostHogReplayIntegration.dispatchQueue.async { continuation.resume() }
            }
        }

        @Test("Touch capture defaults to enabled and preserves began/ended coordinates")
        func defaultEnabled() async throws {
            let (sut, integration, snapshots) = try makeSut()
            defer { sut.close() }
            #expect(sut.config.sessionReplayConfig.captureTouches)
            let event = TouchEvent()
            integration.handleApplicationEvent(event: event, date: Date(), window: UIWindow())
            await drainReplayQueue()
            #expect(event.touchesRead)
            #expect(snapshots.touches.count == 2)
            #expect(Set(snapshots.touches.compactMap { $0["type"] as? Int }) == [7, 9])
            #expect(snapshots.touches.allSatisfy { $0["x"] as? Int == 123 && $0["y"] as? Int == 456 })
        }

        @Test("Initially disabled touch capture does not even read coordinates")
        func initiallyDisabled() async throws {
            let (sut, integration, snapshots) = try makeSut(captureTouches: false)
            defer { sut.close() }
            let event = TouchEvent()
            integration.handleApplicationEvent(event: event, date: Date(), window: UIWindow())
            await drainReplayQueue()
            #expect(!event.touchesRead)
            #expect(snapshots.touches.isEmpty)
        }

        @Test("Disabling touch capture leaves real screenshot rendering and emission active")
        func screenshotsRemainActive() async throws {
            let (sut, integration, snapshots) = try makeSut(captureTouches: false)
            defer { sut.close() }
            let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
            window.rootViewController = UIViewController()
            window.rootViewController?.view.backgroundColor = .red
            window.makeKeyAndVisible()
            defer { window.isHidden = true }
            #expect(integration.captureBridgeSnapshot(episodeFirstFrame: false, window: window))
            await drainReplayQueue()
            let screenshot = try #require(snapshots.screenshots.first)
            #expect(!(screenshot["base64"] as? String ?? "").isEmpty)
            #expect(snapshots.touches.isEmpty)
            #expect(sut.isSessionReplayActive())
        }
    }
#endif
