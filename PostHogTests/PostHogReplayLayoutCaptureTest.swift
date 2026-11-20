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
            case uiKit, plainTitled, swiftUI

            var testDescription: String { rawValue }

            var expectedHref: String? {
                switch self {
                case .uiKit: "Checkout"
                // The title is display text, so it never becomes the href.
                case .plainTitled: nil
                case .swiftUI: "Text"
                }
            }

            @MainActor func makeController() -> UIViewController {
                switch self {
                case .uiKit, .plainTitled:
                    let controller = self == .uiKit ? CheckoutViewController() : UIViewController()
                    controller.title = "Invoice for Jane Doe"
                    let label = UILabel(frame: CGRect(x: 20, y: 100, width: 200, height: 40))
                    label.text = "secret"
                    controller.view.addSubview(label)
                    return controller
                case .swiftUI:
                    return UIHostingController(rootView: Text("secret"))
                }
            }
        }

        private final class CheckoutViewController: UIViewController {}

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

            let (sut, _, snapshots) = try makeScreenshotReplaySut()
            defer { sut.close() }

            // Each frame is encoded on the serial replay queue, which is slow on the simulator.
            // Nudge sparingly so frames don't pile up, then let the queue drain before closing.
            for _ in 0 ..< 40 where snapshots.screenshots.isEmpty {
                window.setNeedsLayout()
                window.layoutIfNeeded()
                try await Task.sleep(nanoseconds: 500_000_000)
            }
            await drainReplayQueue()

            let screenshot = try #require(snapshots.screenshots.first, "No screenshot was captured")
            #expect(!(screenshot["base64"] as? String ?? "").isEmpty)
            let href = try #require(snapshots.metaHrefs.first)
            #expect(href == root.expectedHref)
        }
    }
#endif
