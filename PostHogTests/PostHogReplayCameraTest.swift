#if os(iOS)
    @testable import PostHog
    import Testing
    import UIKit

    @Suite("Replay camera exclusion", .serialized)
    @MainActor
    struct PostHogReplayCameraTest {
        // Exercise controller containment without starting a camera capture session.
        private final class CameraPicker: UIImagePickerController {
            override var sourceType: UIImagePickerController.SourceType {
                get { .camera }
                set {}
            }

            override func loadView() {
                view = UIView()
            }
        }

        private func window(root: UIViewController) -> UIWindow {
            let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 200, height: 300))
            window.rootViewController = root
            window.makeKeyAndVisible()
            root.view.frame = window.bounds
            return window
        }

        @Test("Camera frames are rejected before masking and by every screenshot renderer")
        func cameraFramesAreDiscarded() {
            let window = window(root: CameraPicker())
            defer { window.isHidden = true }
            #expect(window.hasCameraForReplay())
            #expect(PostHogReplayIntegration().collectMaskableRects(in: window) == nil)
            #expect(window.toImage(preferFidelityRenderer: false) == nil)
            #expect(window.toImage(preferFidelityRenderer: true) == nil)
            #expect(window.toImage(afterScreenUpdates: true) == nil)
        }

        @Test("Nested attached cameras block capture until removed, without affecting another window")
        func containedCameraAndRemoval() throws {
            let root = UIViewController()
            let container = UIViewController()
            root.addChild(container)
            root.view.addSubview(container.view)
            container.didMove(toParent: root)
            let picker = CameraPicker()
            container.addChild(picker)
            let window = window(root: root)
            defer { window.isHidden = true }
            // A retained, offscreen controller does not put camera layers in the window.
            #expect(!window.hasCameraForReplay())
            container.view.addSubview(picker.view)
            picker.didMove(toParent: container)
            #expect(window.hasCameraForReplay())
            let other = self.window(root: UIViewController())
            defer { other.isHidden = true }
            #expect(!other.hasCameraForReplay())
            picker.willMove(toParent: nil)
            picker.view.removeFromSuperview()
            picker.removeFromParent()
            #expect(!window.hasCameraForReplay())
            #expect(PostHogReplayIntegration().collectMaskableRects(in: window) != nil)
            #expect(window.toImage(preferFidelityRenderer: false) != nil)
        }

        @Test("A skipped bridge frame leaves recording active and releases the next capture")
        func bridgeRecoversAfterCamera() throws {
            let config = PostHogConfig(projectToken: UUID().uuidString)
            config.sessionReplay = true
            config.sessionReplayConfig.screenshotMode = true
            config.sessionReplayConfig.captureNetworkTelemetry = false
            config.disableReachabilityForTesting = true
            config.disableQueueTimerForTesting = true
            config.disableFlushOnBackgroundForTesting = true
            config.disableRemoteConfigForTesting = true
            config.preloadFeatureFlags = false
            config.captureApplicationLifecycleEvents = false
            config.captureScreenViews = false
            config.setBeforeSend { _ in nil }
            PostHogStorage(config).setDictionary(forKey: .remoteConfig, contents: ["sessionRecording": ["endpoint": "/s/"]])
            PostHogReplayIntegration.clearInstalls()
            let sdk = PostHogSDK.with(config)
            defer { sdk.close() }
            let integration = try #require(sdk.getReplayIntegration())
            let window = window(root: CameraPicker())
            defer { window.isHidden = true }
            #expect(sdk.isSessionReplayActive())
            #expect(!integration.captureBridgeSnapshot(episodeFirstFrame: true, window: window))
            #expect(!integration.captureBridgeSnapshot(episodeFirstFrame: false, window: window))
            #expect(sdk.isSessionReplayActive())
            window.rootViewController = UIViewController()
            window.rootViewController?.view.backgroundColor = .red
            #expect(integration.captureBridgeSnapshot(episodeFirstFrame: false, window: window))
            #expect(sdk.isSessionReplayActive())
        }

        @Test("Photo-library pickers are not excluded")
        func photoLibraryIsNotCamera() {
            let picker = UIImagePickerController()
            picker.sourceType = .photoLibrary
            let window = window(root: picker)
            defer { window.isHidden = true }
            #expect(!window.hasCameraForReplay())
        }

        @Test("Background screenshot entry checks camera state on main")
        func backgroundCameraFrameIsDiscarded() async {
            let window = window(root: CameraPicker())
            defer { window.isHidden = true }
            let discarded = await withCheckedContinuation { continuation in
                DispatchQueue.global().async {
                    continuation.resume(returning: window.toImage() == nil)
                }
            }
            #expect(discarded)
        }
    }
#endif

#if os(iOS) && TEST_CAMERA_REPLAY
    @Suite("System camera replay regression", .serialized)
    @MainActor
    struct PostHogSystemCameraReplayTest {
        private func waitUntil(_ condition: () -> Bool) async throws {
            let deadline = DispatchTime.now().uptimeNanoseconds + 5_000_000_000
            while !condition(), DispatchTime.now().uptimeNanoseconds < deadline {
                try await Task.sleep(nanoseconds: 50_000_000)
            }
        }

        @Test("Real camera flash changes discard frames; capture resumes after dismissal")
        func flashChanges() async throws {
            try #require(UIImagePickerController.isSourceTypeAvailable(.camera), "Requires a camera-capable runtime")
            let scene = try #require(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
            let window = UIWindow(windowScene: scene)
            window.frame = scene.coordinateSpace.bounds
            let root = UIViewController()
            window.rootViewController = root
            window.makeKeyAndVisible()
            defer {
                window.isHidden = true
                window.rootViewController = nil
            }
            let picker = UIImagePickerController()
            picker.sourceType = .camera
            root.present(picker, animated: false)
            try await waitUntil { picker.viewIfLoaded?.window === window }
            try #require(picker.viewIfLoaded?.window === window)
            let integration = PostHogReplayIntegration()
            for step in 0 ..< 30 {
                picker.cameraFlashMode = step.isMultiple(of: 2) ? .on : .off
                try await Task.sleep(nanoseconds: 50_000_000)
                #expect(integration.collectMaskableRects(in: window) == nil)
                #expect(window.toImage(preferFidelityRenderer: false) == nil)
                #expect(window.toImage(preferFidelityRenderer: true) == nil)
                #expect(window.toImage(afterScreenUpdates: true) == nil)
            }
            root.dismiss(animated: false)
            try await waitUntil { picker.viewIfLoaded?.window == nil }
            try #require(picker.viewIfLoaded?.window == nil)
            #expect(integration.collectMaskableRects(in: window) != nil)
            #expect(window.toImage(preferFidelityRenderer: false) != nil)
        }
    }
#endif
