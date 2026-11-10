#if os(iOS)
    import Foundation
    @testable import PostHog
    import Testing
    import UIKit

    @Suite("Replay touch capture", .serialized)
    @MainActor
    struct PostHogReplayCaptureTouchesTests {
        private final class Touch: UITouch {
            var recordedPhase: UITouch.Phase
            var recordedLocation: CGPoint

            init(phase: UITouch.Phase, location: CGPoint) {
                recordedPhase = phase
                recordedLocation = location
                super.init()
            }

            override var phase: UITouch.Phase { recordedPhase }
            override func location(in _: UIView?) -> CGPoint {
                recordedLocation
            }
        }

        private final class TouchEvent: UIEvent {
            private let touches: [Touch]
            var touchesRead = false

            init(location: CGPoint = CGPoint(x: 123, y: 456)) {
                touches = [Touch(phase: .began, location: location), Touch(phase: .ended, location: location)]
                super.init()
            }

            init(_ touch: Touch) {
                touches = [touch]
                super.init()
            }

            override var type: UIEvent.EventType { .touches }
            override func touches(for _: UIWindow) -> Set<UITouch>? {
                touchesRead = true
                return Set(touches)
            }
        }

        private func makeSut(captureTouches: Bool? = nil, maskAllTextInputs: Bool = true) throws
            -> (PostHogSDK, PostHogReplayIntegration, ReplaySnapshots)
        {
            try makeScreenshotReplaySut { config in
                if let captureTouches {
                    config.captureTouches = captureTouches
                }
                config.maskAllTextInputs = maskAllTextInputs
            }
        }

        // Reports `presented` as its presentation without running a UIKit transition.
        private final class PresentingController: UIViewController {
            private let presented: UIViewController

            init(presenting presented: UIViewController) {
                self.presented = presented
                super.init(nibName: nil, bundle: nil)
            }

            @available(*, unavailable)
            required init?(coder _: NSCoder) {
                fatalError("init(coder:) has not been implemented")
            }

            override var presentedViewController: UIViewController? { presented }
        }

        private func makeWindow(root: UIViewController = UIViewController()) -> UIWindow {
            let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
            window.rootViewController = root
            window.makeKeyAndVisible()
            root.view.frame = window.bounds
            return window
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

        @Test("Touches inside a ph-no-capture view are dropped", arguments: [true, false])
        func noCaptureViewDropped(markWithIdentifier: Bool) async throws {
            let (sut, integration, snapshots) = try makeSut()
            defer { sut.close() }
            let window = makeWindow()
            defer { window.isHidden = true }
            let container = UIView(frame: CGRect(x: 20, y: 100, width: 300, height: 300))
            if markWithIdentifier {
                container.accessibilityIdentifier = "ph-no-capture"
            } else {
                container.accessibilityLabel = "ph-no-capture"
            }
            let button = UIButton(frame: CGRect(x: 50, y: 50, width: 100, height: 44))
            container.addSubview(button)
            window.rootViewController?.view.addSubview(container)

            integration.handleApplicationEvent(event: TouchEvent(location: CGPoint(x: 120, y: 170)), date: Date(), window: window)
            await drainReplayQueue()
            #expect(snapshots.touches.isEmpty)
        }

        private func send(_ touch: Touch, phase: UITouch.Phase, to integration: PostHogReplayIntegration, in window: UIWindow) {
            touch.recordedPhase = phase
            integration.handleApplicationEvent(event: TouchEvent(touch), date: Date(), window: window)
        }

        private func addNoCaptureView(to window: UIWindow) -> UIView {
            let masked = UIView(frame: CGRect(x: 20, y: 100, width: 300, height: 300))
            masked.accessibilityIdentifier = "ph-no-capture"
            window.rootViewController?.view.addSubview(masked)
            return masked
        }

        @Test("A touch that began on a ph-no-capture view stays dropped after the view is removed", arguments: [true, false])
        func beganMaskedEndAfterRemovalDropped(removeView: Bool) async throws {
            let (sut, integration, snapshots) = try makeSut()
            defer { sut.close() }
            let window = makeWindow()
            defer { window.isHidden = true }
            let masked = addNoCaptureView(to: window)
            let touch = Touch(phase: .began, location: CGPoint(x: 120, y: 170))

            send(touch, phase: .began, to: integration, in: window)
            if removeView {
                masked.removeFromSuperview()
            } else {
                masked.isHidden = true
            }
            send(touch, phase: .ended, to: integration, in: window)
            await drainReplayQueue()
            #expect(snapshots.touches.isEmpty)
        }

        @Test("A cancelled masked touch does not suppress a later unmasked touch on the same object")
        func cancelledMaskedTouchClearsSuppression() async throws {
            let (sut, integration, snapshots) = try makeSut()
            defer { sut.close() }
            let window = makeWindow()
            defer { window.isHidden = true }
            _ = addNoCaptureView(to: window)
            let touch = Touch(phase: .began, location: CGPoint(x: 120, y: 170))

            send(touch, phase: .began, to: integration, in: window)
            send(touch, phase: .cancelled, to: integration, in: window)
            touch.recordedLocation = CGPoint(x: 150, y: 600)
            send(touch, phase: .began, to: integration, in: window)
            send(touch, phase: .ended, to: integration, in: window)
            await drainReplayQueue()
            #expect(snapshots.touches.compactMap { $0["type"] as? Int } == [7, 9])
            #expect(snapshots.touches.allSatisfy { $0["x"] as? Int == 150 && $0["y"] as? Int == 600 })
        }

        @Test("A touch that began outside masks and ended on a ph-no-capture view keeps only its start")
        func endedInsideMaskDropsEnd() async throws {
            let (sut, integration, snapshots) = try makeSut()
            defer { sut.close() }
            let window = makeWindow()
            defer { window.isHidden = true }
            _ = addNoCaptureView(to: window)
            let touch = Touch(phase: .began, location: CGPoint(x: 150, y: 600))

            send(touch, phase: .began, to: integration, in: window)
            touch.recordedLocation = CGPoint(x: 120, y: 170)
            send(touch, phase: .ended, to: integration, in: window)
            await drainReplayQueue()
            #expect(snapshots.touches.compactMap { $0["type"] as? Int } == [7])
            #expect(snapshots.touches.first?["x"] as? Int == 150)
        }

        @Test("Touches inside a postHogMask() region are dropped")
        func maskRegionDropped() async throws {
            let (sut, integration, snapshots) = try makeSut()
            defer { sut.close() }
            let window = makeWindow()
            defer { window.isHidden = true }
            let reporter = PostHogMaskReporterUIView(frame: CGRect(x: 20, y: 100, width: 200, height: 200))
            window.rootViewController?.view.addSubview(reporter)
            defer { reporter.removeFromSuperview() }
            window.layoutIfNeeded()

            integration.handleApplicationEvent(event: TouchEvent(location: CGPoint(x: 100, y: 150)), date: Date(), window: window)
            await drainReplayQueue()
            #expect(snapshots.touches.isEmpty)
        }

        @Test("Touches outside explicit masks are kept")
        func outsideMaskKept() async throws {
            let (sut, integration, snapshots) = try makeSut()
            defer { sut.close() }
            let window = makeWindow()
            defer { window.isHidden = true }
            let masked = UIView(frame: CGRect(x: 20, y: 100, width: 100, height: 100))
            masked.accessibilityIdentifier = "ph-no-capture"
            window.rootViewController?.view.addSubview(masked)
            let reporter = PostHogMaskReporterUIView(frame: CGRect(x: 200, y: 100, width: 100, height: 100))
            window.rootViewController?.view.addSubview(reporter)
            defer { reporter.removeFromSuperview() }
            window.layoutIfNeeded()

            integration.handleApplicationEvent(event: TouchEvent(location: CGPoint(x: 150, y: 500)), date: Date(), window: window)
            await drainReplayQueue()
            #expect(snapshots.touches.count == 2)
            #expect(snapshots.touches.allSatisfy { $0["x"] as? Int == 150 && $0["y"] as? Int == 500 })
        }

        @Test("Touches on a camera window are dropped")
        func cameraWindowDropped() async throws {
            let (sut, integration, snapshots) = try makeSut()
            defer { sut.close() }
            let picker = PostHogReplayCameraTest.CameraPicker()
            let window = makeWindow(root: picker)
            defer { window.isHidden = true }
            #expect(window.hasCameraForReplay())

            integration.handleApplicationEvent(event: TouchEvent(location: CGPoint(x: 100, y: 150)), date: Date(), window: window)
            await drainReplayQueue()
            #expect(snapshots.touches.isEmpty)
        }

        @Test("Touches on a ph-no-capture view inside a cover under a ph-no-mask ancestor are kept")
        func noMaskCoverAncestorKept() async throws {
            let (sut, integration, snapshots) = try makeSut()
            defer { sut.close() }
            let cover = UIViewController()
            let root = PresentingController(presenting: cover)
            let window = makeWindow(root: root)
            defer { window.isHidden = true }
            let unmasked = UIView(frame: window.bounds)
            unmasked.accessibilityIdentifier = "ph-no-mask"
            window.addSubview(unmasked)
            cover.view.frame = unmasked.bounds
            cover.view.backgroundColor = .white
            unmasked.addSubview(cover.view)
            let masked = UIView(frame: CGRect(x: 20, y: 100, width: 200, height: 200))
            masked.accessibilityIdentifier = "ph-no-capture"
            cover.view.addSubview(masked)
            #expect(PostHogPresentationCover.frontmostFullWindowCover(in: window) === cover.view)

            integration.handleApplicationEvent(event: TouchEvent(location: CGPoint(x: 100, y: 150)), date: Date(), window: window)
            await drainReplayQueue()
            #expect(snapshots.touches.count == 2)
        }

        @Test("Touches on a ph-no-capture view at its in-flight animated position are dropped")
        func animatingNoCaptureViewDropped() async throws {
            let (sut, integration, snapshots) = try makeSut()
            defer { sut.close() }
            let window = makeWindow()
            defer { window.isHidden = true }
            let masked = UIView(frame: CGRect(x: 20, y: 100, width: 100, height: 100))
            masked.accessibilityIdentifier = "ph-no-capture"
            window.rootViewController?.view.addSubview(masked)
            let drawnCenter = CGPoint(x: 270, y: 600)
            let animation = CABasicAnimation(keyPath: "position")
            animation.fromValue = NSValue(cgPoint: drawnCenter)
            animation.toValue = NSValue(cgPoint: drawnCenter)
            animation.duration = 1000
            masked.layer.add(animation, forKey: "move")
            CATransaction.flush()
            defer { masked.layer.removeAllAnimations() }
            let presented = try #require(masked.layer.presentation())
            #expect(presented.position == drawnCenter)
            #expect(!masked.frame.contains(drawnCenter))

            integration.handleApplicationEvent(event: TouchEvent(location: drawnCenter), date: Date(), window: window)
            await drainReplayQueue()
            #expect(snapshots.touches.isEmpty)
        }

        @Test("Touches on a text field masked by maskAllTextInputs are kept")
        func maskAllTextInputsKept() async throws {
            let (sut, integration, snapshots) = try makeSut(maskAllTextInputs: true)
            defer { sut.close() }
            let window = makeWindow()
            defer { window.isHidden = true }
            let textField = UITextField(frame: CGRect(x: 20, y: 100, width: 300, height: 44))
            textField.text = "secret"
            window.rootViewController?.view.addSubview(textField)
            #expect(integration.collectMaskableRects(in: window)?.isEmpty == false)

            integration.handleApplicationEvent(event: TouchEvent(location: CGPoint(x: 100, y: 120)), date: Date(), window: window)
            await drainReplayQueue()
            #expect(snapshots.touches.count == 2)
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
            // drawHierarchy has no window scene in this hostless bundle and failed draws are dropped, so render
            // through the presentation tree and hand the frame to the emission step the bridge would reach.
            let wireframe = RRWireframe()
            wireframe.type = "screenshot"
            wireframe.image = try #require(window.toImage(renderer: .presentationTree))
            integration.captureSnapshot(
                wireframe,
                window: window,
                windowSize: window.bounds.size,
                screenName: nil,
                postHog: sut,
                timestampDate: Date()
            )
            await drainReplayQueue()
            let screenshot = try #require(snapshots.screenshots.first)
            #expect(!(screenshot["base64"] as? String ?? "").isEmpty)
            #expect(snapshots.touches.isEmpty)
            #expect(sut.isSessionReplayActive())
        }
    }
#endif
