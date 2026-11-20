#if os(iOS) && canImport(Metal)
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
                $0.screenshotModeGPUCapture = gpu
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

        @Test("only screenshot mode off the background path layers the windows, so the idle fingerprint follows the same layers")
        func captureLayersFollowConfig() {
            let scene = makeScene()
            defer {
                scene.close()
                PostHogReplayIntegration.windowLayerCandidatesForTesting = nil
            }
            func layers(screenshot: Bool, gpu: Bool = false, background: Bool = false) -> [ObjectIdentifier] {
                let config = PostHogSessionReplayConfig()
                config.screenshotMode = screenshot
                config.screenshotModeGPUCapture = gpu
                config.screenshotModeBackgroundCapture = background
                return ids(PostHogReplayIntegration.captureLayers(for: scene.alert, config: config))
            }

            #expect(layers(screenshot: true) == ids([scene.app, scene.alert]))
            #expect(layers(screenshot: true, gpu: true, background: true) == ids([scene.app, scene.alert]))
            #expect(layers(screenshot: true, background: true) == ids([scene.alert]))
            #expect(layers(screenshot: false) == ids([scene.alert]))
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

        private func wireframe(_ id: Int, image: UIImage? = nil, base64: String? = nil, masks: [CGRect]? = nil) -> RRWireframe {
            let wireframe = RRWireframe()
            wireframe.id = id
            wireframe.type = "screenshot"
            wireframe.image = image
            wireframe.base64 = base64
            wireframe.maskableWidgets = masks
            return wireframe
        }

        private func send(_ wireframes: [RRWireframe]) throws -> ReplaySnapshots {
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
#endif
