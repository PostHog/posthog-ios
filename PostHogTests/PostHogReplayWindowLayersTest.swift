#if os(iOS) && canImport(Metal) && (!SWIFT_PACKAGE || SessionReplay)
    import Foundation
    @testable import PostHog
    import Testing
    import UIKit

    /// Stands in for UIKit's own `_UI*` windows, which can't be created in a test.
    @objc(_UIFakeSystemOverlayWindow)
    private final class FakeSystemWindow: UIWindow {}

    private extension UIWindow.Level {
        static let rnAlert = UIWindow.Level(rawValue: UIWindow.Level.alert.rawValue + 1)
    }

    private func ids(_ windows: [UIWindow]) -> [ObjectIdentifier] {
        windows.map(ObjectIdentifier.init)
    }

    @Suite("Replay window layers: selection")
    @MainActor
    struct PostHogReplayWindowLayerSelectionTests {
        private func window(_ level: UIWindow.Level = .normal, hidden: Bool = false, alpha: CGFloat = 1) -> UIWindow {
            let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 200, height: 300))
            window.windowLevel = level
            window.alpha = alpha
            window.isHidden = hidden
            return window
        }

        private func layers(key: UIWindow, _ candidates: [UIWindow]) -> [ObjectIdentifier] {
            ids(PostHogReplayIntegration.screenshotLayers(keyWindow: key, candidates: candidates))
        }

        @Test("a key window above the app window is captured with the app window under it")
        func alertAboveApp() {
            let app = window(), alert = window(.rnAlert)
            defer { [app, alert].forEach { $0.isHidden = true } }

            #expect(layers(key: alert, [app, alert]) == ids([app, alert]))
        }

        @Test("a lone key window is captured alone")
        func singleWindow() {
            let app = window()
            defer { app.isHidden = true }

            #expect(layers(key: app, [app]) == ids([app]))
        }

        @Test("a key app window keeps today's capture, even with an overlay window above it")
        func keyAppWindowIgnoresOverlay() {
            let app = window(), overlay = window(.alert)
            defer { [app, overlay].forEach { $0.isHidden = true } }

            #expect(layers(key: app, [app, overlay]) == ids([app]))
        }

        @Test("system, hidden and transparent windows, and windows above the key window, are left out")
        func excludedWindows() {
            let app = window(), alert = window(.rnAlert)
            let system = FakeSystemWindow(frame: app.frame)
            system.windowLevel = .alert
            system.isHidden = false
            let hidden = window(.alert, hidden: true), transparent = window(.alert, alpha: 0), above = window(UIWindow.Level(rawValue: UIWindow.Level.alert.rawValue + 2))
            defer { [app, alert, system, hidden, transparent, above].forEach { $0.isHidden = true } }

            #expect(layers(key: alert, [app, system, hidden, transparent, above, alert]) == ids([app, alert]))
        }

        @Test("windows between the app window and the key window are captured in z order, up to the key window")
        func inBetweenWindowsInZOrder() {
            let app = window(), toast = window(UIWindow.Level(rawValue: 1))
            let alert = window(.rnAlert), before = window(.rnAlert), after = window(.rnAlert)
            defer { [app, toast, alert, before, after].forEach { $0.isHidden = true } }

            #expect(layers(key: alert, [before, alert, toast, app, after]) == ids([app, toast, before, alert]))
        }

        @Test("the topmost app window is the base")
        func topmostAppWindowIsBase() {
            let first = window(), second = window(), alert = window(.rnAlert)
            defer { [first, second, alert].forEach { $0.isHidden = true } }

            #expect(layers(key: alert, [first, second, alert]) == ids([second, alert]))
        }

        @Test("an opaque window covering the app window hides everything under it, so the hidden screen isn't captured")
        func opaqueCoverCutsLayersBelow() {
            let app = window(), toast = window(UIWindow.Level(rawValue: 1)), lock = window(.rnAlert)
            defer { [app, toast, lock].forEach { $0.isHidden = true } }

            lock.backgroundColor = .black
            #expect(layers(key: lock, [app, toast, lock]) == ids([lock]))

            lock.backgroundColor = nil
            let root = UIViewController()
            root.view.backgroundColor = .white
            lock.rootViewController = root
            #expect(layers(key: lock, [app, toast, lock]) == ids([lock]))

            lock.rootViewController = nil
            toast.backgroundColor = .black
            #expect(layers(key: lock, [app, toast, lock]) == ids([toast, lock]))
        }

        @Test("a window that is translucent or doesn't cover the whole app window still shows the app window under it")
        func partialOrTranslucentCoverKeepsBase() {
            let app = window(), alert = window(.rnAlert)
            defer { [app, alert].forEach { $0.isHidden = true } }

            alert.backgroundColor = UIColor.black.withAlphaComponent(0.4)
            #expect(layers(key: alert, [app, alert]) == ids([app, alert]))

            alert.backgroundColor = .black
            alert.frame = CGRect(x: 20, y: 40, width: 160, height: 200)
            #expect(layers(key: alert, [app, alert]) == ids([app, alert]))
        }

        @Test("an opaque background that is masked or rounded doesn't hide the app window, because it shows through")
        func maskedOrRoundedCoverKeepsBase() {
            let app = window(), lock = window(.rnAlert)
            defer { [app, lock].forEach { $0.isHidden = true } }
            let root = UIViewController()
            root.view.backgroundColor = .white
            lock.rootViewController = root
            #expect(layers(key: lock, [app, lock]) == ids([lock]))

            let mask = CALayer()
            mask.frame = CGRect(x: 0, y: 0, width: 100, height: 100)
            mask.backgroundColor = UIColor.black.cgColor
            root.view.layer.mask = mask
            #expect(layers(key: lock, [app, lock]) == ids([app, lock]))

            root.view.layer.mask = nil
            root.view.layer.cornerRadius = 24
            #expect(layers(key: lock, [app, lock]) == ids([app, lock]))

            root.view.layer.cornerRadius = 0
            lock.backgroundColor = .black
            lock.layer.cornerRadius = 24
            #expect(layers(key: lock, [app, lock]) == ids([app, lock]))
        }

        @Test("a dynamic color is judged in the window's own appearance")
        func dynamicColorResolvesAgainstWindowTraits() {
            let app = window(), lock = window(.rnAlert)
            defer { [app, lock].forEach { $0.isHidden = true } }
            lock.backgroundColor = UIColor { $0.userInterfaceStyle == .dark ? .black : .clear }

            lock.overrideUserInterfaceStyle = .light
            #expect(layers(key: lock, [app, lock]) == ids([app, lock]))

            lock.overrideUserInterfaceStyle = .dark
            #expect(layers(key: lock, [app, lock]) == ids([lock]))
        }

        @Test("each layer gets the mask rects of the layers above it, in its own coordinates and clipped to it")
        func upperLayerMaskRects() {
            let app = window()
            let toast = UIWindow(frame: CGRect(x: 0, y: 100, width: 200, height: 100))
            let alert = UIWindow(frame: CGRect(x: 20, y: 40, width: 160, height: 200))
            let layers = [app, toast, alert]
            let rects: [[CGRect]] = [
                [CGRect(x: 0, y: 0, width: 5, height: 5)],
                [CGRect(x: 10, y: 10, width: 30, height: 30)],
                [CGRect(x: 0, y: 0, width: 50, height: 50), CGRect(x: 0, y: 100, width: 30, height: 30), CGRect(x: 150, y: 190, width: 40, height: 40)],
            ]

            let upper = PostHogReplayIntegration.upperLayerMaskRects(rects, bounds: layers.map(\.bounds)) { rect, source, target in
                layers[target].convert(rect, from: layers[source])
            }

            #expect(upper[0] == [CGRect(x: 10, y: 110, width: 30, height: 30), CGRect(x: 20, y: 40, width: 50, height: 50),
                                 CGRect(x: 20, y: 140, width: 30, height: 30), CGRect(x: 170, y: 230, width: 30, height: 40)])
            #expect(upper[1] == [CGRect(x: 20, y: 40, width: 30, height: 30)])
            #expect(upper[2].isEmpty)
        }

        @Test("with no visible app window, or a key window outside the scene, the key window is captured alone")
        func noBase() {
            let hiddenApp = window(hidden: true), app = window(), alert = window(.rnAlert), stranger = window(.rnAlert)
            defer { [app, alert, stranger].forEach { $0.isHidden = true } }

            #expect(layers(key: alert, [hiddenApp, alert]) == ids([alert]))
            #expect(layers(key: stranger, [app, alert]) == ids([stranger]))
        }
    }

    @Suite("Replay window layers: capture", .serialized)
    @MainActor
    struct PostHogReplayWindowLayersTests: GPUCaptureTesting {
        private struct Scene {
            let app: UIWindow
            let alert: UIWindow
            let marker: UIView
            let card: UIView

            func close() {
                [app, alert].forEach { $0.isHidden = true }
            }
        }

        /// An app window with a magenta label and a blue marker, under a key window like React Native's alert: a
        /// translucent dimming view across it and an opaque card in the middle.
        private func makeScene(alertFrame: CGRect = CGRect(x: 0, y: 0, width: 200, height: 300)) -> Scene {
            let app = makeWindow()
            let label = UILabel(frame: CGRect(x: 10, y: 40, width: 180, height: 40))
            label.text = "Secret value 42"
            label.textColor = .magenta
            label.font = .boldSystemFont(ofSize: 22)
            app.addSubview(label)
            let marker = UIView(frame: CGRect(x: 10, y: 200, width: 40, height: 40))
            marker.backgroundColor = .blue
            app.addSubview(marker)

            let alert = UIWindow(frame: alertFrame)
            alert.windowLevel = .rnAlert
            alert.isHidden = false
            let dim = UIView(frame: alert.bounds)
            dim.backgroundColor = UIColor.black.withAlphaComponent(0.2)
            alert.addSubview(dim)
            let card = UIView(frame: CGRect(x: alert.bounds.midX - 50, y: alert.bounds.midY - 30, width: 100, height: 60))
            card.backgroundColor = .green
            alert.addSubview(card)

            app.layoutIfNeeded()
            alert.layoutIfNeeded()
            CATransaction.flush()
            PostHogReplayIntegration.windowLayerCandidatesForTesting = [app, alert]
            return Scene(app: app, alert: alert, marker: marker, card: card)
        }

        private func makeSut(gpu: Bool, mask: Bool = false, mirror: PostHogGPUMirrorCapture) throws
            -> (PostHogSDK, PostHogReplayIntegration, ReplaySnapshots)
        {
            let (sut, integration, snapshots) = try makeScreenshotReplaySut {
                $0.captureMethod = gpu ? .gpu : .standard
                $0.maskAllTextInputs = mask
            }
            integration.gpuMirror = mirror
            DI.main.appLifecyclePublisher = MockApplicationLifecyclePublisher()
            // drawHierarchy draws nothing in this hostless bundle.
            PostHogReplayIntegration.screenshotRendererForTesting = .presentationTree
            return (sut, integration, snapshots)
        }

        private func close(_ sut: PostHogSDK) {
            sut.close()
            DI.main.appLifecyclePublisher = ApplicationLifecyclePublisher.shared
            PostHogReplayIntegration.screenshotRendererForTesting = nil
            PostHogReplayIntegration.windowLayerCandidatesForTesting = nil
        }

        private func prewarm(_ mirror: PostHogGPUMirrorCapture, _ scene: Scene) async {
            await prewarm(mirror, for: scene.app)
            await prewarm(mirror, for: scene.alert)
        }

        private func capture(_ scene: Scene, _ integration: PostHogReplayIntegration, _ sut: PostHogSDK) async {
            CATransaction.flush()
            #expect(integration.startScreenshotCapture(window: scene.alert, screenName: nil, postHog: sut))
            await waitForCaptureToFinish(integration)
        }

        private func pixels(_ wireframe: [String: Any]) throws -> Pixels {
            let base64 = try #require((wireframe["base64"] as? String)?.components(separatedBy: ",").last)
            let data = try #require(Data(base64Encoded: base64))
            return try Pixels(#require(UIImage(data: data)?.cgImage))
        }

        @Test("the app window and the window above it go out as two positioned screenshots, app window first", arguments: [false, true])
        func layeredFrame(gpu: Bool) async throws {
            let mirror = try makeMirror()
            let (sut, integration, snapshots) = try makeSut(gpu: gpu, mirror: mirror)
            defer { close(sut) }
            let scene = makeScene(alertFrame: CGRect(x: 20, y: 40, width: 160, height: 200))
            defer { scene.close() }
            await prewarm(mirror, scene)

            await capture(scene, integration, sut)

            let wireframes = try #require(snapshots.fullSnapshots.first)
            #expect(snapshots.fullSnapshots.count == 1)
            try #require(wireframes.count == 2)
            let (base, upper) = (wireframes[0], wireframes[1])
            #expect(base["id"] as? Int == scene.app.hash)
            #expect(upper["id"] as? Int == scene.alert.hash)
            #expect([base["x"], base["y"], base["width"], base["height"]] as? [Int] == [0, 0, 200, 300])
            #expect([upper["x"], upper["y"], upper["width"], upper["height"]] as? [Int] == [20, 40, 160, 200])
            #expect(wireframes.allSatisfy { $0["type"] as? String == "screenshot" })
            #expect(wireframes.allSatisfy { ($0["base64"] as? String)?.hasPrefix("data:image/webp") == true })
            #expect(snapshots.metas.last?["width"] as? Int == 200)
            #expect(snapshots.metas.last?["height"] as? Int == 300)
            #expect(!integration.isScreenshotRenderInFlightForTesting)
            #expect(!mirror.hasAttachedFrameForTesting)
        }

        @Test("the app window under the alert is masked as configured", arguments: [false, true], [false, true])
        func baseMaskedPerConfig(gpu: Bool, mask: Bool) async throws {
            let mirror = try makeMirror()
            let (sut, integration, snapshots) = try makeSut(gpu: gpu, mask: mask, mirror: mirror)
            defer { close(sut) }
            // GPU masking draws text as `*` in the label's own colour, which here is the magenta being looked for.
            PostHogInlineMask.textColorForTesting = .blue
            defer { PostHogInlineMask.textColorForTesting = nil }
            let scene = makeScene()
            defer { scene.close() }
            await prewarm(mirror, scene)

            await capture(scene, integration, sut)

            let wireframes = try #require(snapshots.fullSnapshots.first)
            try #require(wireframes.count == 2)
            let magenta = try pixels(wireframes[0]).count(where: Self.isMagenta)
            if mask {
                #expect(magenta == 0)
            } else {
                #expect(magenta > 50)
            }
        }

        @Test("the window above keeps its transparency, so the app window shows through its dimming", arguments: [false, true])
        func upperKeepsTransparency(gpu: Bool) async throws {
            let mirror = try makeMirror()
            let (sut, integration, snapshots) = try makeSut(gpu: gpu, mirror: mirror)
            defer { close(sut) }
            let scene = makeScene()
            defer { scene.close() }
            await prewarm(mirror, scene)

            await capture(scene, integration, sut)

            let wireframes = try #require(snapshots.fullSnapshots.first)
            try #require(wireframes.count == 2)
            let upper = try pixels(wireframes[1])
            let dimmed = upper[5, 5]
            #expect(dimmed.alpha > 0 && dimmed.alpha < 255, "\(dimmed)")
            let card = upper[Int(scene.card.frame.midX), Int(scene.card.frame.midY)]
            #expect(card.alpha == 255 && card.green > 200 && card.red < 60, "\(card)")
        }

        @Test("a change in the app window alone sends a new frame; no change sends nothing", arguments: [false, true])
        func baseChangeSendsNewFrame(gpu: Bool) async throws {
            let mirror = try makeMirror()
            let (sut, integration, snapshots) = try makeSut(gpu: gpu, mirror: mirror)
            defer { close(sut) }
            let scene = makeScene()
            defer { scene.close() }
            await prewarm(mirror, scene)

            await capture(scene, integration, sut)
            #expect(snapshots.fullSnapshots.count == 1)

            await capture(scene, integration, sut)
            #expect(snapshots.fullSnapshots.count == 1)

            scene.marker.backgroundColor = .red
            await capture(scene, integration, sut)
            #expect(snapshots.fullSnapshots.count == 2)
        }

        @Test("with no window above the app window, one screenshot goes out as before", arguments: [false, true])
        func singleWindowUnchanged(gpu: Bool) async throws {
            let mirror = try makeMirror()
            let (sut, integration, snapshots) = try makeSut(gpu: gpu, mirror: mirror)
            defer { close(sut) }
            let scene = makeScene()
            defer { scene.close() }
            await prewarm(mirror, scene)

            CATransaction.flush()
            #expect(integration.startScreenshotCapture(window: scene.app, screenName: nil, postHog: sut))
            await waitForCaptureToFinish(integration)

            let wireframes = try #require(snapshots.fullSnapshots.first)
            try #require(wireframes.count == 1)
            #expect(wireframes[0]["id"] as? Int == scene.app.hash)
            #expect([wireframes[0]["x"], wireframes[0]["y"], wireframes[0]["width"], wireframes[0]["height"]] as? [Int] == [0, 0, 200, 300])
        }

        @Test("a clear window between the app window and the key window, like the surveys window, is left out of the GPU frame")
        func clearInBetweenWindowOmitted() async throws {
            let mirror = try makeMirror()
            let (sut, integration, snapshots) = try makeSut(gpu: true, mirror: mirror)
            defer { close(sut) }
            let scene = makeScene(alertFrame: CGRect(x: 20, y: 40, width: 160, height: 200))
            defer { scene.close() }
            let clear = UIWindow(frame: scene.app.frame)
            clear.windowLevel = .alert
            clear.backgroundColor = .clear
            clear.isHidden = false
            defer { clear.isHidden = true }
            PostHogReplayIntegration.windowLayerCandidatesForTesting = [scene.app, clear, scene.alert]
            await prewarm(mirror, scene)

            await capture(scene, integration, sut)

            let wireframes = try #require(snapshots.fullSnapshots.first)
            try #require(wireframes.count == 2)
            #expect(wireframes.map { $0["id"] as? Int } == [scene.app.hash, scene.alert.hash])
            #expect([wireframes[1]["x"], wireframes[1]["y"]] as? [Int] == [20, 40])
            #expect(!integration.isScreenshotRenderInFlightForTesting)
            #expect(!mirror.hasAttachedFrameForTesting)
        }

        @Test("a mask in the window above hides the app window under it too, in the app window's coordinates", arguments: [false, true])
        func upperMaskHidesBase(gpu: Bool) async throws {
            let mirror = try makeMirror()
            let (sut, integration, snapshots) = try makeSut(gpu: gpu, mirror: mirror)
            defer { close(sut) }
            let scene = makeScene(alertFrame: CGRect(x: 20, y: 40, width: 160, height: 200))
            defer { scene.close() }
            let shield = UIView(frame: CGRect(x: 0, y: 0, width: 160, height: 40))
            shield.accessibilityIdentifier = "ph-no-capture"
            scene.alert.addSubview(shield)
            await prewarm(mirror, scene)

            await capture(scene, integration, sut)

            let wireframes = try #require(snapshots.fullSnapshots.first)
            try #require(wireframes.count == 2)
            let base = try pixels(wireframes[0])
            let scale = CGFloat(base.width) / scene.app.bounds.width
            let shielded = CGRect(x: 20, y: 40, width: 160, height: 40).applying(CGAffineTransform(scaleX: scale, y: scale))
            // WebP is lossy, so a few edge pixels come back off black.
            #expect(Double(base.count(in: shielded, where: Self.isBlack)) >= 0.97 * shielded.width * shielded.height)
            let above = CGRect(x: 20, y: 30, width: 160, height: 8), beside = CGRect(x: 0, y: 42, width: 8, height: 36)
            for clear in [above, beside] {
                #expect(base.count(in: clear.applying(CGAffineTransform(scaleX: scale, y: scale)), where: Self.isBlack) == 0)
            }
            let marker = base[Int(scene.marker.frame.midX * scale), Int(scene.marker.frame.midY * scale)]
            #expect(marker.blue > 200 && marker.red < 60, "\(marker)")
        }

        @Test("a clear window with a full-window mask hides the app window under it, from the key window or one between",
              arguments: [false, true], [false, true])
        func clearMaskingWindowHidesBase(gpu: Bool, between: Bool) async throws {
            let mirror = try makeMirror()
            let (sut, integration, snapshots) = try makeSut(gpu: gpu, mirror: mirror)
            defer { close(sut) }
            let scene = makeScene()
            defer { scene.close() }
            scene.alert.subviews.forEach { $0.removeFromSuperview() }
            let card = UIView(frame: CGRect(x: 50, y: 120, width: 100, height: 60))
            card.backgroundColor = .green
            scene.alert.addSubview(card)
            let masking = UIWindow(frame: scene.app.frame)
            masking.windowLevel = .alert
            masking.isHidden = false
            defer { masking.isHidden = true }
            let shield = UIView(frame: scene.app.bounds)
            shield.accessibilityIdentifier = "ph-no-capture"
            (between ? masking : scene.alert).addSubview(shield)
            PostHogReplayIntegration.windowLayerCandidatesForTesting = between ? [scene.app, masking, scene.alert] : [scene.app, scene.alert]
            await prewarm(mirror, scene)

            await capture(scene, integration, sut)

            let wireframes = try #require(snapshots.fullSnapshots.first)
            try #require(wireframes.count >= 2)
            #expect(wireframes.first?["id"] as? Int == scene.app.hash)
            #expect(try pixels(wireframes[0]).count(where: Self.isMagenta) == 0)
        }

        @Test("a clear in-between window with a postHogMask() reporter is dropped as blank while still masking the app window")
        func clearBlankReporterWindowHidesBase() async throws {
            let mirror = try makeMirror()
            let (sut, integration, snapshots) = try makeSut(gpu: true, mirror: mirror)
            defer { close(sut) }
            let scene = makeScene()
            defer { scene.close() }
            let masking = UIWindow(frame: scene.app.frame)
            masking.windowLevel = .alert
            masking.isHidden = false
            defer { masking.isHidden = true }
            let reporter = PostHogMaskReporterUIView(frame: scene.app.bounds)
            masking.addSubview(reporter)
            defer { reporter.removeFromSuperview() }
            masking.layoutIfNeeded()
            PostHogReplayIntegration.windowLayerCandidatesForTesting = [scene.app, masking, scene.alert]
            await prewarm(mirror, scene)

            await capture(scene, integration, sut)

            let wireframes = try #require(snapshots.fullSnapshots.first)
            try #require(wireframes.count == 2)
            #expect(wireframes.map { $0["id"] as? Int } == [scene.app.hash, scene.alert.hash])
            #expect(try pixels(wireframes[0]).count(where: Self.isMagenta) == 0)
        }

        @Test("the app window under the key window never measures its masked views: only the layers above it need their rects")
        func baseLayerSkipsDeferredMeasurements() async throws {
            let mirror = try makeMirror()
            let (sut, integration, snapshots) = try makeSut(gpu: true, mirror: mirror)
            defer { close(sut) }
            let scene = makeScene()
            defer { scene.close() }
            let secret = UIView(frame: CGRect(x: 10, y: 100, width: 180, height: 60))
            secret.backgroundColor = .magenta
            secret.accessibilityIdentifier = "ph-no-capture"
            scene.app.addSubview(secret)
            await prewarm(mirror, scene)

            let measuredBefore = PostHogReplayIntegration.MaskedRegion.deferredMeasurementsForTesting
            await capture(scene, integration, sut)

            #expect(PostHogReplayIntegration.MaskedRegion.deferredMeasurementsForTesting == measuredBefore)
            let wireframes = try #require(snapshots.fullSnapshots.first)
            try #require(wireframes.count == 2)
            #expect(try pixels(wireframes[0]).count(in: secret.frame, where: Self.isMagenta) == 0)
        }

        @Test("repeated layered GPU captures don't keep reopening the presented-text budget on main")
        func layeredGPUCaptureDoesNotThrashNoteScreen() async throws {
            let mirror = try makeMirror()
            mirror.inlineMask.presentedTextBudget = .infinity
            mirror.inlineMask.textBudget = 0
            let (sut, integration, _) = try makeSut(gpu: true, mask: true, mirror: mirror)
            defer { close(sut) }
            let scene = makeScene()
            defer { scene.close() }
            let ticker = UILabel(frame: CGRect(x: 10, y: 100, width: 180, height: 30))
            scene.app.addSubview(ticker)
            await prewarm(mirror, scene)

            var counts: [Int] = []
            for i in 1 ... 6 {
                ticker.text = String(repeating: "A", count: 3 + i * 2)
                await capture(scene, integration, sut)
                counts.append(mirror.inlineMask.textDrawsOnMainForTesting)
            }

            #expect(counts[5] == counts[4], "progression: \(counts)")
        }

        @Test("a blank key window falls back instead of being left out, so the app is never sent without its cover")
        func blankKeyWindowFallsBack() async throws {
            let mirror = try makeMirror()
            let (sut, integration, snapshots) = try makeSut(gpu: true, mirror: mirror)
            defer { close(sut) }
            let scene = makeScene()
            defer { scene.close() }
            scene.alert.subviews.forEach { $0.removeFromSuperview() }
            scene.alert.backgroundColor = .clear
            CATransaction.flush()
            await prewarm(mirror, scene)

            await capture(scene, integration, sut)

            let wireframes = try #require(snapshots.fullSnapshots.first)
            #expect(snapshots.fullSnapshots.count == 1)
            #expect(wireframes.count == 2)
            #expect(!integration.isScreenshotRenderInFlightForTesting)
            #expect(!mirror.hasAttachedFrameForTesting)
        }

        @Test("an upper layer that fails to prepare drops the frame before any layer renders or the motion renderer pauses")
        func failedPrepareSkipsRenderAndPause() async throws {
            let mirror = try makeMirror()
            let (sut, integration, snapshots) = try makeSut(gpu: false, mask: true, mirror: mirror)
            defer { close(sut) }
            let scene = makeScene()
            defer { scene.close() }
            let before = integration.presentationTreeResumeTimeForTesting

            CATransaction.flush()
            #expect(integration.startScreenshotCapture(window: scene.alert, screenName: nil, postHog: sut))
            // A field that appears between the settle samples makes the frame a motion frame, which uses the presentation tree.
            let field = UITextField(frame: CGRect(x: 20, y: 20, width: 120, height: 40))
            field.text = "secret"
            scene.app.addSubview(field)
            scene.app.layoutIfNeeded()
            scene.alert.isHidden = true
            await waitForCaptureToFinish(integration)

            #expect(snapshots.fullSnapshots.isEmpty)
            #expect(integration.presentationTreeResumeTimeForTesting == before)
        }

        @Test("a layer that can't be captured drops the whole frame, never sending the other layer alone",
              arguments: [false, true], [false, true])
        func failedLayerDropsFrame(gpu: Bool, hideBase: Bool) async throws {
            let mirror = try makeMirror()
            let (sut, integration, snapshots) = try makeSut(gpu: gpu, mirror: mirror)
            defer { close(sut) }
            let scene = makeScene()
            defer { scene.close() }
            await prewarm(mirror, scene)

            CATransaction.flush()
            #expect(integration.startScreenshotCapture(window: scene.alert, screenName: nil, postHog: sut))
            (hideBase ? scene.app : scene.alert).isHidden = true
            await waitForCaptureToFinish(integration)

            #expect(snapshots.fullSnapshots.isEmpty)
            #expect(!mirror.hasAttachedFrameForTesting)
        }

        @Test("a layered GPU capture drops its frame when the session rotates mid-capture")
        func layeredGPUCaptureDropsOnSessionRotation() async throws {
            let mirror = try makeMirror()
            let (sut, integration, snapshots) = try makeSut(gpu: true, mirror: mirror)
            defer { close(sut) }
            let scene = makeScene()
            defer { scene.close() }
            await prewarm(mirror, scene)
            CATransaction.flush()
            #expect(integration.startScreenshotCapture(window: scene.alert, screenName: nil, postHog: sut))
            sut.startSession()
            await waitForCaptureToFinish(integration)
            #expect(snapshots.posts.isEmpty)
            #expect(!mirror.hasAttachedFrameForTesting)
        }
    }

    private final class CountingLayer: CALayer {
        nonisolated(unsafe) static var copies = 0
        override init() {
            super.init()
        }

        override init(layer: Any) {
            Self.copies += 1
            super.init(layer: layer)
        }

        @available(*, unavailable) required init?(coder _: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }
    }

    private final class CountingLayerWindow: UIWindow {
        override class var layerClass: AnyClass { CountingLayer.self }
    }

    @Suite("Replay window layers: app-defined base", .serialized)
    @MainActor
    struct PostHogReplayWindowLayerAppDefinedBaseTests {
        @Test("an app-defined base layer is never copied while judging a cover")
        func appDefinedBaseNotCopied() {
            let base = CountingLayerWindow(frame: CGRect(x: 0, y: 0, width: 200, height: 300))
            base.isHidden = false
            let alert = UIWindow(frame: base.frame)
            alert.windowLevel = .rnAlert
            alert.isHidden = false
            defer { [base, alert].forEach { $0.isHidden = true } }
            #expect(base.layer.isAppDefined)
            CATransaction.flush()
            CountingLayer.copies = 0
            _ = PostHogReplayIntegration.screenshotLayers(keyWindow: alert, candidates: [base, alert])
            #expect(CountingLayer.copies == 0)
        }
    }

    @Suite("Replay window layers: emission, change hash and fingerprint", .serialized)
    @MainActor
    struct PostHogReplayWindowLayerEmissionTests {
        private func image(_ color: UIColor) -> UIImage {
            UIGraphicsImageRenderer(size: CGSize(width: 40, height: 40)).image { context in
                color.setFill()
                context.fill(CGRect(x: 0, y: 0, width: 40, height: 40))
            }
        }

        /// Rounds to zero pixels, so the masked render fails as it does when its allocation fails.
        private func unrenderableImage() -> UIImage {
            let pixel = CGContext(data: nil, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                                  space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            return UIImage(cgImage: pixel.makeImage()!, scale: 10000, orientation: .up)
        }

        private func wireframe(_ id: Int, image: UIImage? = nil, base64: String? = nil, masks: [CGRect]? = nil) -> RRScreenshotFrame {
            let wireframe = RRScreenshotFrame()
            wireframe.id = id
            wireframe.type = "screenshot"
            wireframe.image = image
            wireframe.base64 = base64
            wireframe.maskableWidgets = masks
            return wireframe
        }

        private func send(_ wireframes: [RRScreenshotFrame]) throws -> ReplaySnapshots {
            let (sut, integration, snapshots) = try makeScreenshotReplaySut()
            defer { sut.close() }
            let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 200, height: 300))
            integration.captureSnapshot(wireframes, window: window, windowSize: window.bounds.size, screenName: nil,
                                        postHog: sut, timestampDate: Date())
            PostHogReplayIntegration.dispatchQueue.sync {}
            return snapshots
        }

        @Test("layers that encode are sent together, base first")
        func layersSentTogether() throws {
            let snapshots = try send([wireframe(1, image: image(.white)), wireframe(2, image: image(.green))])

            let wireframes = try #require(snapshots.fullSnapshots.first)
            #expect(wireframes.map { $0["id"] as? Int } == [1, 2])
        }

        @Test("a layer whose masked render fails drops the whole frame")
        func maskRenderFailureDropsFrame() throws {
            let snapshots = try send([wireframe(1, image: image(.white)),
                                      wireframe(2, image: unrenderableImage(), masks: [CGRect(x: 0, y: 0, width: 10, height: 10)])])

            #expect(snapshots.fullSnapshots.isEmpty)
        }

        @Test("a layer with no image drops the whole frame")
        func missingImageDropsFrame() throws {
            let snapshots = try send([wireframe(1), wireframe(2, image: image(.green))])

            #expect(snapshots.fullSnapshots.isEmpty)
        }

        @Test("an upper layer that isn't WebP would paint over the base without transparency, so the frame is dropped")
        func opaqueUpperLayerDropsFrame() throws {
            let snapshots = try send([wireframe(1, image: image(.white)), wireframe(2, base64: "data:image/jpeg;base64,AAAA")])

            #expect(snapshots.fullSnapshots.isEmpty)
        }

        @Test("one layer hashes as before; a change in the base layer alone changes the scene hash")
        func sceneHash() {
            let base: [String: Any] = ["base64": "base"], upper: [String: Any] = ["base64": "upper"]
            #expect(PostHogReplayIntegration.frameHash(for: [base]) == PostHogReplayIntegration.frameHash(for: base))
            #expect(PostHogReplayIntegration.frameHash(for: [base, upper]) == PostHogReplayIntegration.frameHash(for: [base, upper]))
            #expect(PostHogReplayIntegration.frameHash(for: [base, upper]) != PostHogReplayIntegration.frameHash(for: [["base64": "base2"] as [String: Any], upper]))
            #expect(PostHogReplayIntegration.frameHash(for: [base, upper]) != PostHogReplayIntegration.frameHash(for: [base]))
            let moved: [String: Any] = ["base64": "upper", "x": 20]
            #expect(PostHogReplayIntegration.frameHash(for: [base, ["base64": "upper", "x": 10] as [String: Any]])
                != PostHogReplayIntegration.frameHash(for: [base, moved]))
        }

        @Test("the idle fingerprint of a layered screen sees a change in the base window")
        func layeredFingerprint() {
            let app = UIWindow(frame: CGRect(x: 0, y: 0, width: 200, height: 300))
            let alert = UIWindow(frame: app.frame)
            // A hidden window draws nothing, so the fingerprint skips it.
            app.isHidden = false
            alert.isHidden = false
            defer { [app, alert].forEach { $0.isHidden = true } }
            let label = UILabel(frame: CGRect(x: 10, y: 10, width: 100, height: 20))
            label.text = "Loading"
            app.addSubview(label)

            #expect(PostHogReplayIntegration.structureFingerprint(ofLayers: [app]) == PostHogReplayIntegration.structureFingerprint(of: app))
            let before = PostHogReplayIntegration.structureFingerprint(ofLayers: [app, alert])
            label.text = "Done"
            #expect(PostHogReplayIntegration.structureFingerprint(ofLayers: [app, alert]) != before)
        }
    }

    #if TEST_PRESENTATION_MASKS
        /// UIKit presentation needs an app host; run through `make testPresentationMasks`.
        @Suite("Replay window layers: presented cover")
        @MainActor
        struct PostHogReplayWindowLayerPresentedCoverTests {
            @Test("a transparent window whose root presents an opaque full-screen controller is a cover, so the app window under it isn't captured")
            func presentedFullScreenCoverCutsLayersBelow() async throws {
                let scene = try #require(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
                let app = UIWindow(windowScene: scene), lock = UIWindow(windowScene: scene)
                app.frame = CGRect(x: 0, y: 0, width: 200, height: 300)
                app.isHidden = false
                lock.frame = app.frame
                lock.windowLevel = .rnAlert
                defer { [app, lock].forEach { $0.isHidden = true } }
                let root = UIViewController()
                root.view.backgroundColor = .clear
                lock.rootViewController = root
                lock.makeKeyAndVisible()
                root.view.frame = lock.bounds
                #expect(ids(PostHogReplayIntegration.screenshotLayers(keyWindow: lock, candidates: [app, lock])) == ids([app, lock]))

                let cover = UIViewController()
                cover.modalPresentationStyle = .fullScreen
                cover.view.backgroundColor = .white
                root.present(cover, animated: false)
                var presented = false
                for _ in 0 ..< 100 where !presented {
                    lock.layoutIfNeeded()
                    try await Task.sleep(nanoseconds: 50_000_000)
                    presented = cover.view.window === lock && !cover.isBeingPresented
                }
                try #require(presented, "the cover did not finish presenting")

                #expect(ids(PostHogReplayIntegration.screenshotLayers(keyWindow: lock, candidates: [app, lock])) == ids([lock]))
            }

            @Test("a window whose opaque background is still fading in doesn't hide the app window yet")
            func coverFadingInKeepsBase() async throws {
                let scene = try #require(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
                let app = UIWindow(windowScene: scene), lock = UIWindow(windowScene: scene)
                app.frame = CGRect(x: 0, y: 0, width: 200, height: 300)
                app.isHidden = false
                lock.frame = app.frame
                lock.windowLevel = .rnAlert
                lock.isHidden = false
                defer { [app, lock].forEach { $0.isHidden = true } }
                lock.backgroundColor = .black
                let fade = CABasicAnimation(keyPath: "backgroundColor")
                fade.fromValue = UIColor.clear.cgColor
                fade.duration = 100
                lock.layer.add(fade, forKey: "fade")
                defer { lock.layer.removeAllAnimations() }
                var rendered = false
                for _ in 0 ..< 100 where !rendered {
                    try await Task.sleep(nanoseconds: 20_000_000)
                    rendered = lock.layer.presentation().map { ($0.backgroundColor?.alpha ?? 1) < 1 } ?? false
                }
                try #require(rendered, "the fade never reached the presentation layer")

                #expect(ids(PostHogReplayIntegration.screenshotLayers(keyWindow: lock, candidates: [app, lock])) == ids([app, lock]))
                lock.layer.removeAllAnimations()
                var settled = false
                for _ in 0 ..< 100 where !settled {
                    try await Task.sleep(nanoseconds: 20_000_000)
                    settled = lock.layer.presentation()?.backgroundColor?.alpha == 1
                }
                try #require(settled, "the presentation layer never settled")
                #expect(ids(PostHogReplayIntegration.screenshotLayers(keyWindow: lock, candidates: [app, lock])) == ids([lock]))
            }

            @Test("an opaque window still fading in or sliding in doesn't hide the app window yet", arguments: ["opacity", "position.y"])
            func coverAnimatingInKeepsBase(keyPath: String) async throws {
                let scene = try #require(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
                let app = UIWindow(windowScene: scene), lock = UIWindow(windowScene: scene)
                app.frame = CGRect(x: 0, y: 0, width: 200, height: 300)
                app.isHidden = false
                lock.frame = app.frame
                lock.windowLevel = .rnAlert
                lock.isHidden = false
                lock.backgroundColor = .black
                defer { [app, lock].forEach { $0.isHidden = true } }
                #expect(ids(PostHogReplayIntegration.screenshotLayers(keyWindow: lock, candidates: [app, lock])) == ids([lock]))

                let animation = CABasicAnimation(keyPath: keyPath)
                let modelY = lock.layer.position.y
                if keyPath == "opacity" {
                    animation.fromValue = Float(0)
                    animation.toValue = Float(0)
                } else {
                    animation.fromValue = modelY + 300
                    animation.toValue = modelY + 300
                }
                animation.duration = 100
                lock.layer.add(animation, forKey: "animateIn")
                defer { lock.layer.removeAllAnimations() }
                var rendered = false
                for _ in 0 ..< 100 where !rendered {
                    try await Task.sleep(nanoseconds: 20_000_000)
                    rendered = lock.layer.presentation().map {
                        keyPath == "opacity" ? $0.opacity < 1 : $0.position.y > modelY
                    } ?? false
                }
                try #require(rendered, "the animation never reached the presentation layer")

                #expect(ids(PostHogReplayIntegration.screenshotLayers(keyWindow: lock, candidates: [app, lock])) == ids([app, lock]))
            }

            @Test("a detached root view left under a translucent full-screen presentation is not a cover")
            func detachedRootIsNotACover() async throws {
                let scene = try #require(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
                let app = UIWindow(windowScene: scene), lock = UIWindow(windowScene: scene)
                app.frame = CGRect(x: 0, y: 0, width: 200, height: 300)
                app.isHidden = false
                lock.frame = app.frame
                lock.windowLevel = .rnAlert
                defer { [app, lock].forEach { $0.isHidden = true } }
                let root = UIViewController()
                root.view.backgroundColor = .white
                lock.rootViewController = root
                lock.makeKeyAndVisible()
                root.view.frame = lock.bounds
                #expect(ids(PostHogReplayIntegration.screenshotLayers(keyWindow: lock, candidates: [app, lock])) == ids([lock]))

                let cover = UIViewController()
                cover.modalPresentationStyle = .fullScreen
                cover.view.backgroundColor = UIColor.black.withAlphaComponent(0.3)
                root.present(cover, animated: false)
                var presented = false
                for _ in 0 ..< 100 where !presented {
                    lock.layoutIfNeeded()
                    try await Task.sleep(nanoseconds: 50_000_000)
                    presented = cover.view.window === lock && !cover.isBeingPresented
                }
                try #require(presented, "the cover did not finish presenting")
                let layers = PostHogReplayIntegration.screenshotLayers(keyWindow: lock, candidates: [app, lock])
                #expect(ids(layers) == ids([app, lock]))
            }
        }
    #endif
#endif
