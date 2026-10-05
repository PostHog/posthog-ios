#if os(iOS) && TEST_PRESENTATION_MASKS
    import Foundation
    @testable import PostHog
    import SwiftUI
    import Testing
    import UIKit

    // Needs the app host: snapshot() reads the key window of a foreground-active scene.
    @Suite("Replay layout-driven capture", .serialized)
    @MainActor
    struct PostHogReplayLayoutCaptureTest {
        enum Root: String, CaseIterable, CustomTestStringConvertible {
            case uiKit, swiftUI

            var testDescription: String { rawValue }

            var expectedHref: String {
                switch self {
                case .uiKit: "Checkout"
                case .swiftUI: "Text"
                }
            }

            @MainActor func makeController() -> UIViewController {
                switch self {
                case .uiKit:
                    let controller = UIViewController()
                    controller.title = "Checkout"
                    let label = UILabel(frame: CGRect(x: 20, y: 100, width: 200, height: 40))
                    label.text = "secret"
                    controller.view.addSubview(label)
                    return controller
                case .swiftUI:
                    return UIHostingController(rootView: Text("secret"))
                }
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

            private func data(ofType type: Int) -> [[String: Any]] {
                lock.withLock {
                    values.filter { $0["type"] as? Int == type }.compactMap { $0["data"] as? [String: Any] }
                }
            }

            var metas: [[String: Any]] { data(ofType: 4) }
            var wireframes: [[String: Any]] { data(ofType: 2).flatMap { $0["wireframes"] as? [[String: Any]] ?? [] } }
        }

        private func drainReplayQueue() async {
            await withCheckedContinuation { continuation in
                PostHogReplayIntegration.dispatchQueue.async { continuation.resume() }
            }
        }

        @Test("Default config captures UIKit and SwiftUI screens as screenshots", arguments: Root.allCases)
        func defaultConfigCapturesScreenshots(_ root: Root) async throws {
            let scene = try #require(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
            let window = UIWindow(windowScene: scene)
            window.frame = scene.coordinateSpace.bounds
            window.rootViewController = root.makeController()
            window.makeKeyAndVisible()
            defer {
                window.isHidden = true
                window.rootViewController = nil
            }
            try #require(UIApplication.getCurrentWindow() === window)

            let config = PostHogConfig(projectToken: UUID().uuidString)
            config.sessionReplay = true
            config.sessionReplayConfig.captureNetworkTelemetry = false
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
            defer { sut.close() }
            #expect(sut.isSessionReplayActive())

            // Each frame is encoded on the serial replay queue, which is slow on the simulator.
            // Nudge sparingly so frames don't pile up, then let the queue drain before closing.
            for _ in 0 ..< 40 where snapshots.wireframes.isEmpty {
                window.setNeedsLayout()
                window.layoutIfNeeded()
                try await Task.sleep(nanoseconds: 500_000_000)
            }
            await drainReplayQueue()

            let wireframe = try #require(snapshots.wireframes.first, "No snapshot was captured")
            #expect(wireframe["type"] as? String == "screenshot")
            #expect(!(wireframe["base64"] as? String ?? "").isEmpty)
            #expect(snapshots.metas.first?["href"] as? String == root.expectedHref)
        }
    }
#endif
