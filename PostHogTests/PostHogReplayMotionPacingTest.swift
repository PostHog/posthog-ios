#if os(iOS) && (!SWIFT_PACKAGE || SessionReplay)
    import Foundation
    @testable import PostHog
    import QuartzCore
    import Testing
    import UIKit

    @Suite("Replay motion renderer pacing", .serialized)
    @MainActor
    struct PostHogReplayMotionPacingTest {
        private func makeWindow() -> UIWindow {
            let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 200, height: 300))
            window.backgroundColor = .white
            // Shown without becoming key, so the SDK's own capture loop never picks it up.
            window.isHidden = false
            return window
        }

        /// A text field that appears between the two settle samples: the samples can't be paired, so the verdict is motion.
        private func addTextField(to window: UIWindow) {
            // An empty field isn't masked, so it would leave both samples empty and the verdict still.
            let field = UITextField(frame: CGRect(x: 20, y: 20, width: 120, height: 40))
            field.text = "secret"
            window.addSubview(field)
            window.layoutIfNeeded()
        }

        @Test("a motion frame renders the presentation tree and pauses that renderer after it")
        func motionFramePausesRenderer() async throws {
            let (sut, integration, snapshots) = try makeScreenshotReplaySut()
            defer { sut.close() }
            let mockLifecycle = MockApplicationLifecyclePublisher()
            DI.main.appLifecyclePublisher = mockLifecycle
            defer { DI.main.appLifecyclePublisher = ApplicationLifecyclePublisher.shared }
            let window = makeWindow()
            defer { window.isHidden = true }
            let start = CACurrentMediaTime()

            #expect(integration.startScreenshotCapture(window: window, screenName: nil, postHog: sut))
            addTextField(to: window)
            await waitForCaptureToFinish(integration)

            #expect(snapshots.screenshots.count == 1)
            #expect(integration.presentationTreeResumeTimeForTesting > start)
        }

        @Test("a motion frame skips while the presentation-tree renderer is paused, and frees the render slot")
        func pausedMotionFrameSkips() async throws {
            let (sut, integration, snapshots) = try makeScreenshotReplaySut()
            defer { sut.close() }
            let mockLifecycle = MockApplicationLifecyclePublisher()
            DI.main.appLifecyclePublisher = mockLifecycle
            defer { DI.main.appLifecyclePublisher = ApplicationLifecyclePublisher.shared }
            let window = makeWindow()
            defer { window.isHidden = true }
            let paused = CACurrentMediaTime() + 60
            integration.presentationTreeResumeTimeForTesting = paused

            #expect(integration.startScreenshotCapture(window: window, screenName: nil, postHog: sut))
            addTextField(to: window)
            await waitForCaptureToFinish(integration)

            #expect(snapshots.screenshots.isEmpty)
            #expect(integration.presentationTreeResumeTimeForTesting == paused)
        }

        @Test("a settled frame still captures while the presentation-tree renderer is paused")
        func settledFrameCapturesWhilePaused() async throws {
            let (sut, integration, snapshots) = try makeScreenshotReplaySut()
            defer { sut.close() }
            // drawHierarchy draws nothing in this hostless bundle, so the settled frame renders through this instead.
            PostHogReplayIntegration.screenshotRendererForTesting = .presentationTree
            defer { PostHogReplayIntegration.screenshotRendererForTesting = nil }
            let mockLifecycle = MockApplicationLifecyclePublisher()
            DI.main.appLifecyclePublisher = mockLifecycle
            defer { DI.main.appLifecyclePublisher = ApplicationLifecyclePublisher.shared }
            let window = makeWindow()
            defer { window.isHidden = true }
            let paused = CACurrentMediaTime() + 60
            integration.presentationTreeResumeTimeForTesting = paused

            #expect(integration.startScreenshotCapture(window: window, screenName: nil, postHog: sut))
            await waitForCaptureToFinish(integration)

            #expect(snapshots.screenshots.count == 1)
            // Only a motion frame's render paces the renderer.
            #expect(integration.presentationTreeResumeTimeForTesting == paused)
        }
    }
#endif
