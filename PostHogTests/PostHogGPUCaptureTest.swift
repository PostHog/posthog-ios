#if os(iOS) && canImport(Metal)
    import Foundation
    @testable import PostHog
    import QuartzCore
    import Testing
    import UIKit

    private final class MetalView: UIView {
        override class var layerClass: AnyClass { CAMetalLayer.self }
    }

    @Suite("Replay GPU capture", .serialized)
    @MainActor
    struct PostHogGPUCaptureTest {
        private struct RGBA: Equatable {
            let red: UInt8, green: UInt8, blue: UInt8, alpha: UInt8

            static let magenta = RGBA(red: 255, green: 0, blue: 255, alpha: 255)
            static let blue = RGBA(red: 0, green: 0, blue: 255, alpha: 255)
            static let white = RGBA(red: 255, green: 255, blue: 255, alpha: 255)
            static let red = RGBA(red: 255, green: 0, blue: 0, alpha: 255)
        }

        /// RGBA8 pixels, 1x.
        private struct Pixels {
            let width: Int
            let height: Int
            private let bytes: [UInt8]

            init(_ image: CGImage) throws {
                width = image.width
                height = image.height
                var bytes = [UInt8](repeating: 0, count: width * height * 4)
                let context = try #require(CGContext(
                    data: &bytes, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                    space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                ))
                context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
                self.bytes = bytes
            }

            subscript(x: Int, y: Int) -> RGBA {
                let index = (y * width + x) * 4
                return RGBA(red: bytes[index], green: bytes[index + 1], blue: bytes[index + 2], alpha: bytes[index + 3])
            }

            func points(where predicate: (RGBA) -> Bool) -> [CGPoint] {
                var points: [CGPoint] = []
                for y in 0 ..< height {
                    for x in 0 ..< width where predicate(self[x, y]) {
                        points.append(CGPoint(x: x, y: y))
                    }
                }
                return points
            }
        }

        private static func isMagenta(_ pixel: RGBA) -> Bool {
            pixel.red > 200 && pixel.green < 60 && pixel.blue > 200
        }

        private func makeMirror() throws -> PostHogGPUMirrorCapture {
            // Its own instance per test, so no renderer or frame carries over between tests.
            try #require(PostHogGPUMirrorCapture(), "the simulator has no Metal device")
        }

        private func makeWindow(background: UIColor = .white) -> UIWindow {
            let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 200, height: 300))
            window.backgroundColor = background
            // Shown without becoming key, so the SDK's own capture loop never picks it up.
            window.isHidden = false
            return window
        }

        private func prewarm(_ mirror: PostHogGPUMirrorCapture, for window: UIWindow) async {
            await withCheckedContinuation { continuation in
                mirror.prewarm(size: window.bounds.size) { continuation.resume() }
            }
        }

        /// Turn 1 and turn 2 of a capture, without the replay pipeline around them: the pixels and the mask rects.
        private func render(_ window: UIWindow, with mirror: PostHogGPUMirrorCapture) async throws -> (CGImage, [CGRect]) {
            window.layoutIfNeeded()
            let frame = try #require(mirror.build(window: window))
            let rects = try #require(PostHogReplayIntegration().collectMaskableRects(in: window, culledLayers: frame.culledLayers))
            frame.freeze()
            #expect(frame.encode())
            let image = await withCheckedContinuation { continuation in
                frame.readback(on: .global()) { continuation.resume(returning: $0) }
            }
            frame.release()
            return try (#require(image), rects)
        }

        private func noCaptureView(_ frame: CGRect, color: UIColor = .magenta) -> UIView {
            let view = UIView(frame: frame)
            view.backgroundColor = color
            view.accessibilityIdentifier = "ph-no-capture"
            return view
        }

        // MARK: - Mask walk

        @Test("The mask walk skips exactly the subtrees the mirror left out of the frame")
        func maskWalkSkipsOnlyCulledSubtrees() async throws {
            let mirror = try makeMirror()
            let window = makeWindow()
            await prewarm(mirror, for: window)

            let visible = noCaptureView(CGRect(x: 10, y: 10, width: 40, height: 40))
            let partlyVisible = noCaptureView(CGRect(x: 180, y: 60, width: 40, height: 40))

            let clipper = UIView(frame: CGRect(x: 10, y: 120, width: 60, height: 60))
            clipper.clipsToBounds = true
            let clippedAway = noCaptureView(CGRect(x: 100, y: 0, width: 40, height: 40))
            clipper.addSubview(clippedAway)

            let farAway = noCaptureView(CGRect(x: 10, y: 5000, width: 40, height: 40))

            for view in [visible, partlyVisible, clipper, farAway] {
                window.addSubview(view)
            }
            window.layoutIfNeeded()

            let frame = try #require(mirror.build(window: window))
            defer { frame.release() }
            let integration = PostHogReplayIntegration()
            let unculled = try #require(integration.collectMaskableRects(in: window))
            let culled = try #require(integration.collectMaskableRects(in: window, culledLayers: frame.culledLayers))

            #expect(frame.culledLayers.contains(ObjectIdentifier(clippedAway.layer)))
            #expect(frame.culledLayers.contains(ObjectIdentifier(farAway.layer)))
            #expect(!frame.culledLayers.contains(ObjectIdentifier(visible.layer)))
            #expect(!frame.culledLayers.contains(ObjectIdentifier(partlyVisible.layer)))

            let visibleRects = [visible.frame, partlyVisible.frame]
            let culledRects = [clippedAway.convert(clippedAway.bounds, to: window), farAway.frame]
            #expect(Set(unculled.map(NSCoder.string(for:))) == Set((visibleRects + culledRects).map(NSCoder.string(for:))))
            #expect(Set(culled.map(NSCoder.string(for:))) == Set(visibleRects.map(NSCoder.string(for:))))
        }

        // MARK: - Pixels

        @Test("Mask rects line up with the mirrored pixels, and masking covers them")
        func maskRectsCoverMirroredPixels() async throws {
            let mirror = try makeMirror()
            let window = makeWindow()
            await prewarm(mirror, for: window)

            let marker = UIView(frame: CGRect(x: 120, y: 20, width: 30, height: 30))
            marker.backgroundColor = .blue
            let moved = UIView(frame: CGRect(x: 10, y: 100, width: 150, height: 150))
            moved.bounds.origin = CGPoint(x: 5, y: 10)
            moved.transform = CGAffineTransform(scaleX: 0.8, y: 0.8)
            // Inset inside its masked field, as text is: masks are drawn with rounded corners.
            let field = noCaptureView(CGRect(x: 30, y: 40, width: 60, height: 50), color: .clear)
            let secret = UIView(frame: field.bounds.insetBy(dx: 5, dy: 5))
            secret.backgroundColor = .magenta
            field.addSubview(secret)
            moved.addSubview(field)
            window.addSubview(marker)
            window.addSubview(moved)

            let (image, rects) = try await render(window, with: mirror)
            let pixels = try Pixels(image)
            let fieldRect = field.convert(field.bounds, to: window)
            #expect(rects.contains(fieldRect))

            // Upright and in place: the marker sits where UIKit lays it out.
            #expect(pixels[135, 35] == .blue)
            #expect(pixels[135, 265] == .white)

            let magenta = pixels.points(where: Self.isMagenta)
            #expect(!magenta.isEmpty)
            let secretRect = secret.convert(secret.bounds, to: window)
            let covering = secretRect.insetBy(dx: -1, dy: -1)
            #expect(magenta.allSatisfy { covering.contains(CGPoint(x: $0.x + 0.5, y: $0.y + 0.5)) })
            let inner = secretRect.insetBy(dx: 1, dy: 1)
            #expect(Self.isMagenta(pixels[Int(inner.midX), Int(inner.midY)]))
            #expect(Self.isMagenta(pixels[Int(inner.minX), Int(inner.minY)]))
            #expect(Self.isMagenta(pixels[Int(inner.maxX) - 1, Int(inner.maxY) - 1]))

            let uiImage = UIImage(cgImage: image, scale: PostHogGPUMirrorCapture.scale, orientation: .up)
            let masked = try #require(RRWireframe.maskImage(uiImage, maskableWidgets: rects)?.cgImage)
            #expect(try Pixels(masked).points(where: Self.isMagenta).isEmpty)
        }

        @Test("An empty window size never waits for a renderer, so a capture can't keep re-waiting for one")
        func emptySizeNeedsNoPrewarm() throws {
            let mirror = try makeMirror()
            #expect(!mirror.needsPrewarm(for: .zero))
            #expect(!mirror.needsPrewarm(for: CGSize(width: 200, height: 0)))
            #expect(mirror.needsPrewarm(for: CGSize(width: 200, height: 300)))
        }

        @Test("Metal layers render as the placeholder instead of their pixels or nothing")
        func metalLayerRendersPlaceholder() async throws {
            let mirror = try makeMirror()
            let window = makeWindow(background: .red)
            await prewarm(mirror, for: window)

            let metal = MetalView(frame: CGRect(x: 20, y: 40, width: 160, height: 100))
            window.addSubview(metal)

            let pixels = try await Pixels(render(window, with: mirror).0)

            #expect(pixels[10, 10] == .red)
            var grey = 0
            for y in 40 ..< 140 {
                for x in 20 ..< 180 {
                    let pixel = pixels[x, y]
                    #expect(pixel.alpha == 255)
                    if pixel.red == pixel.green, pixel.green == pixel.blue, pixel.red > 100 {
                        grey += 1
                    }
                }
            }
            #expect(grey > 160 * 100 * 8 / 10)
        }

        // MARK: - Lifecycle

        private func makeSut(gpuCapture: Bool = true) throws -> (PostHogSDK, PostHogReplayIntegration, ReplaySnapshots) {
            try makeScreenshotReplaySut { $0.screenshotModeGPUCapture = gpuCapture }
        }

        /// Waits for the capture to give the render slot back, through both turns and the readback.
        private func waitForCaptureToFinish(_ integration: PostHogReplayIntegration) async {
            await waitUntil(timeout: 2) { !integration.isScreenshotRenderInFlightForTesting }
            #expect(!integration.isScreenshotRenderInFlightForTesting)
            await drainReplayQueue()
        }

        private func windowWithContent() -> UIWindow {
            let window = makeWindow()
            window.addSubview(noCaptureView(CGRect(x: 10, y: 10, width: 40, height: 40)))
            window.layoutIfNeeded()
            return window
        }

        @Test("A first capture waits for its renderer, uploads one screenshot and gives the slot back")
        func captureCompletes() async throws {
            let mirror = try makeMirror()
            let (sut, integration, snapshots) = try makeSut()
            integration.gpuMirror = mirror
            defer { sut.close() }
            let mockLifecycle = MockApplicationLifecyclePublisher()
            DI.main.appLifecyclePublisher = mockLifecycle
            defer { DI.main.appLifecyclePublisher = ApplicationLifecyclePublisher.shared }
            let window = windowWithContent()

            // No renderer yet: the capture keeps the slot while one is built off-main, then resumes.
            #expect(mirror.needsPrewarm(for: window.bounds.size))
            #expect(integration.startScreenshotCapture(window: window, screenName: nil, postHog: sut))
            #expect(integration.isScreenshotRenderInFlightForTesting)

            await waitForCaptureToFinish(integration)
            #expect(!mirror.hasAttachedFrameForTesting)
            #expect(snapshots.screenshots.count == 1)
        }

        @Test("Replay stopping between the two turns drops the frame and frees the slot")
        func replayStoppedBetweenTurns() async throws {
            let mirror = try makeMirror()
            let (sut, integration, snapshots) = try makeSut()
            integration.gpuMirror = mirror
            defer { sut.close() }
            let window = windowWithContent()
            await prewarm(mirror, for: window)

            #expect(integration.startScreenshotCapture(window: window, screenName: nil, postHog: sut))
            sut.stopSessionRecording()

            await waitForCaptureToFinish(integration)
            #expect(!mirror.hasAttachedFrameForTesting)
            #expect(snapshots.screenshots.isEmpty)
        }

        @Test("The window going away between the two turns drops the frame and frees the slot")
        func windowGoneBetweenTurns() async throws {
            let mirror = try makeMirror()
            let (sut, integration, snapshots) = try makeSut()
            integration.gpuMirror = mirror
            defer { sut.close() }
            let mockLifecycle = MockApplicationLifecyclePublisher()
            DI.main.appLifecyclePublisher = mockLifecycle
            defer { DI.main.appLifecyclePublisher = ApplicationLifecyclePublisher.shared }
            await prewarm(mirror, for: makeWindow())

            weak var weakWindow: UIWindow?
            // The pool drains UIKit's autoreleased references; a shown window is retained by the app until hidden.
            let started = autoreleasepool {
                let window = windowWithContent()
                weakWindow = window
                let started = integration.startScreenshotCapture(window: window, screenName: nil, postHog: sut)
                window.isHidden = true
                return started
            }
            #expect(started)
            #expect(weakWindow == nil)

            await waitForCaptureToFinish(integration)
            #expect(!mirror.hasAttachedFrameForTesting)
            #expect(snapshots.screenshots.isEmpty)
        }

        @Test("The app going to the background between the two turns drops the frame and frees the slot")
        func backgroundedBetweenTurns() async throws {
            let mirror = try makeMirror()
            let (sut, integration, snapshots) = try makeSut()
            integration.gpuMirror = mirror
            defer { sut.close() }
            let mockLifecycle = MockApplicationLifecyclePublisher()
            DI.main.appLifecyclePublisher = mockLifecycle
            defer { DI.main.appLifecyclePublisher = ApplicationLifecyclePublisher.shared }
            let window = windowWithContent()
            await prewarm(mirror, for: window)

            #expect(integration.startScreenshotCapture(window: window, screenName: nil, postHog: sut))
            mockLifecycle.isInBackground = true

            await waitForCaptureToFinish(integration)
            #expect(!mirror.hasAttachedFrameForTesting)
            #expect(snapshots.screenshots.isEmpty)
        }

        @Test("With the flag off, a capture takes the default path and never touches the GPU capture")
        func flagOffTakesDefaultPath() async throws {
            let mirror = try makeMirror()
            let (sut, integration, _) = try makeSut(gpuCapture: false)
            defer { sut.close() }
            integration.gpuMirror = mirror
            let window = windowWithContent()

            #expect(integration.startScreenshotCapture(window: window, screenName: nil, postHog: sut))
            await waitForCaptureToFinish(integration)
            #expect(mirror.needsPrewarm(for: window.bounds.size))
            #expect(!mirror.hasAttachedFrameForTesting)
        }

        // MARK: - Routing

        @Test("GPU capture is used only when its flag is on, and wins over background capture", arguments: [
            (gpu: false, background: false, expected: PostHogReplayIntegration.ScreenshotCapturePath.settled),
            (gpu: false, background: true, expected: .background),
            (gpu: true, background: false, expected: .gpu),
            (gpu: true, background: true, expected: .gpu),
        ])
        func capturePath(_ flags: (gpu: Bool, background: Bool, expected: PostHogReplayIntegration.ScreenshotCapturePath)) {
            let config = PostHogSessionReplayConfig()
            config.screenshotModeGPUCapture = flags.gpu
            config.screenshotModeBackgroundCapture = flags.background
            #expect(PostHogReplayIntegration.screenshotCapturePath(config) == flags.expected)
        }
    }
#endif
