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

        private func prewarm(_ mirror: PostHogGPUMirrorCapture, for window: UIWindow, scale: CGFloat = 1) async {
            await withCheckedContinuation { continuation in
                mirror.prewarm(size: window.bounds.size, scale: scale) { continuation.resume() }
            }
        }

        /// Turn 1 and turn 2 of a capture, without the replay pipeline around them: the pixels and the mask rects.
        private func render(_ window: UIWindow, with mirror: PostHogGPUMirrorCapture, scale: CGFloat = 1) async throws -> (CGImage, [CGRect]) {
            window.layoutIfNeeded()
            let frame = try #require(mirror.build(window: window, scale: scale))
            #expect(frame.scale == scale)
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

            let frame = try #require(mirror.build(window: window, scale: 1))
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

        @Test("Mask rects line up with the mirrored pixels at each output scale, and masking covers them", arguments: [1, 0.5] as [CGFloat])
        func maskRectsCoverMirroredPixels(scale: CGFloat) async throws {
            let mirror = try makeMirror()
            let window = makeWindow()
            await prewarm(mirror, for: window, scale: scale)

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

            let (image, rects) = try await render(window, with: mirror, scale: scale)
            let pixels = try Pixels(image)
            #expect(pixels.width == Int((200 * scale).rounded(.up)))
            #expect(pixels.height == Int((300 * scale).rounded(.up)))
            let fieldRect = field.convert(field.bounds, to: window)
            #expect(rects.contains(fieldRect))

            func pixel(_ x: CGFloat, _ y: CGFloat) -> RGBA {
                pixels[Int(x * scale), Int(y * scale)]
            }

            // Upright and in place: the marker sits where UIKit lays it out.
            #expect(pixel(135, 35) == .blue)
            #expect(pixel(135, 265) == .white)

            let magenta = pixels.points(where: Self.isMagenta)
            #expect(!magenta.isEmpty)
            let secretRect = secret.convert(secret.bounds, to: window)
            let covering = secretRect.insetBy(dx: -1 / scale, dy: -1 / scale)
            #expect(magenta.allSatisfy { covering.contains(CGPoint(x: ($0.x + 0.5) / scale, y: ($0.y + 0.5) / scale)) })
            let inner = secretRect.insetBy(dx: 1 / scale, dy: 1 / scale)
            #expect(Self.isMagenta(pixel(inner.midX, inner.midY)))
            #expect(Self.isMagenta(pixel(inner.minX, inner.minY)))
            #expect(Self.isMagenta(pixel(inner.maxX - 1 / scale, inner.maxY - 1 / scale)))

            let uiImage = UIImage(cgImage: image, scale: scale, orientation: .up)
            let maskedImage = try #require(RRWireframe.maskImage(uiImage, maskableWidgets: rects)?.cgImage)
            let masked = try Pixels(maskedImage)
            #expect(masked.width == pixels.width && masked.height == pixels.height)
            #expect(masked.points(where: Self.isMagenta).isEmpty)
        }

        @Test("Renderers are cached per output scale")
        func renderersAreKeyedByScale() async throws {
            let mirror = try makeMirror()
            let window = makeWindow()
            await prewarm(mirror, for: window, scale: 3)
            #expect(!mirror.needsPrewarm(for: window.bounds.size, scale: 3))
            #expect(mirror.needsPrewarm(for: window.bounds.size, scale: 1.5))
        }

        @Test("An empty window size never waits for a renderer, so a capture can't keep re-waiting for one")
        func emptySizeNeedsNoPrewarm() throws {
            let mirror = try makeMirror()
            #expect(!mirror.needsPrewarm(for: .zero, scale: 1))
            #expect(!mirror.needsPrewarm(for: CGSize(width: 200, height: 0), scale: 1))
            #expect(mirror.needsPrewarm(for: CGSize(width: 200, height: 300), scale: 1))
        }

        @Test("Metal layers render as the placeholder instead of their pixels or nothing", arguments: [1, 0.5] as [CGFloat])
        func metalLayerRendersPlaceholder(scale: CGFloat) async throws {
            let mirror = try makeMirror()
            let window = makeWindow(background: .red)
            await prewarm(mirror, for: window, scale: scale)

            let metal = MetalView(frame: CGRect(x: 20, y: 40, width: 160, height: 100))
            window.addSubview(metal)

            let pixels = try await Pixels(render(window, with: mirror, scale: scale).0)

            #expect(pixels[Int(10 * scale), Int(10 * scale)] == .red)
            let region = CGRect(x: 20, y: 40, width: 160, height: 100).applying(CGAffineTransform(scaleX: scale, y: scale))
            var grey = 0, transparent = 0
            for y in Int(region.minY) ..< Int(region.maxY) {
                for x in Int(region.minX) ..< Int(region.maxX) {
                    let pixel = pixels[x, y]
                    if pixel.alpha != 255 {
                        transparent += 1
                    }
                    if pixel.red == pixel.green, pixel.green == pixel.blue, pixel.red > 100 {
                        grey += 1
                    }
                }
            }
            #expect(transparent == 0)
            #expect(grey > Int(region.width * region.height) * 8 / 10)
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

        /// A window with magenta content inset in a masked field, as text sits in a text field: masks are drawn
        /// with rounded corners, so a fully magenta field would show at the corners.
        private func windowWithContent() -> UIWindow {
            let window = makeWindow()
            let field = noCaptureView(CGRect(x: 10, y: 10, width: 60, height: 50), color: .clear)
            let secret = UIView(frame: field.bounds.insetBy(dx: 5, dy: 5))
            secret.backgroundColor = .magenta
            field.addSubview(secret)
            window.addSubview(field)
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
            #expect(mirror.needsPrewarm(for: window.bounds.size, scale: 1))
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
            #expect(mirror.needsPrewarm(for: window.bounds.size, scale: 1))
            #expect(!mirror.hasAttachedFrameForTesting)
        }

        @Test("Both capture paths upload one pixel per point by default, and screenshotScale times native when set", arguments: [
            (gpu: true, scale: nil, width: 200, height: 300), (gpu: true, scale: 1, width: 600, height: 900),
            (gpu: true, scale: 0.5, width: 300, height: 450), (gpu: false, scale: nil, width: 200, height: 300),
            (gpu: false, scale: 1, width: 600, height: 900), (gpu: false, scale: 0.5, width: 300, height: 450),
        ] as [(gpu: Bool, scale: NSNumber?, width: Int, height: Int)])
        func uploadedScreenshotSize(_ capture: (gpu: Bool, scale: NSNumber?, width: Int, height: Int)) async throws {
            let mirror = try makeMirror()
            let (sut, integration, snapshots) = try makeScreenshotReplaySut {
                $0.screenshotModeGPUCapture = capture.gpu
                $0.screenshotScale = capture.scale
            }
            integration.gpuMirror = mirror
            defer { sut.close() }
            let mockLifecycle = MockApplicationLifecyclePublisher()
            DI.main.appLifecyclePublisher = mockLifecycle
            defer { DI.main.appLifecyclePublisher = ApplicationLifecyclePublisher.shared }
            let window = windowWithContent()
            try #require(window.screen.scale == 3, "the expected sizes are for a 3x simulator")

            #expect(integration.startScreenshotCapture(window: window, screenName: nil, postHog: sut))
            await waitForCaptureToFinish(integration)

            let image = try snapshots.firstScreenshotImage()
            #expect(image.width == capture.width)
            #expect(image.height == capture.height)
            #expect(try Pixels(image).points(where: Self.isMagenta).isEmpty)
        }

        @Test("screenshotScale resolves to one pixel per point by default on 3x and 2x screens, and multiplies native when set",
              arguments: [
                  (screenshotScale: nil, nativeScale: 3, expected: 1), (screenshotScale: nil, nativeScale: 2, expected: 1),
                  (screenshotScale: 1, nativeScale: 3, expected: 3), (screenshotScale: 1, nativeScale: 2, expected: 2),
                  (screenshotScale: 0.5, nativeScale: 3, expected: 1.5), (screenshotScale: 0.5, nativeScale: 2, expected: 1),
              ] as [(screenshotScale: NSNumber?, nativeScale: CGFloat, expected: CGFloat)])
        func screenshotPixelScale(_ scales: (screenshotScale: NSNumber?, nativeScale: CGFloat, expected: CGFloat)) {
            let config = PostHogSessionReplayConfig()
            config.screenshotScale = scales.screenshotScale
            #expect(config.screenshotPixelScale(nativeScale: scales.nativeScale) == scales.expected)
        }

        @Test("Default-path masks cover the content at screenshotScale 0.5")
        func defaultPathMasksCoverAtHalfScale() throws {
            let window = windowWithContent()

            let image = try #require(window.toImage(preferFidelityRenderer: false, scale: 0.5))
            let raw = try Pixels(#require(image.cgImage))
            #expect(raw.width == 100 && raw.height == 150)
            #expect(!raw.points(where: Self.isMagenta).isEmpty)

            let rects = try #require(PostHogReplayIntegration().collectMaskableRects(in: window))
            let maskedImage = try #require(RRWireframe.maskImage(image, maskableWidgets: rects)?.cgImage)
            let masked = try Pixels(maskedImage)
            #expect(masked.width == raw.width && masked.height == raw.height)
            #expect(masked.points(where: Self.isMagenta).isEmpty)
        }

        @Test("Shared high-resolution contents are filtered when the mirror downscales them, not point-sampled")
        func downscaledContentsAreFiltered() async throws {
            let mirror = try makeMirror()
            let window = makeWindow()
            await prewarm(mirror, for: window, scale: 0.5)

            // A 1 px black column every 6 px at 3x: thin strokes, as in small glyphs, one per output pixel at 0.5x.
            // Point or bilinear sampling lands between strokes and drops them; filtering keeps 1/6 of each.
            let side = 120
            let stripes = try #require(CGContext(data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0,
                                                 space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                                 bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            stripes.setFillColor(UIColor.white.cgColor)
            stripes.fill(CGRect(x: 0, y: 0, width: side, height: side))
            stripes.setFillColor(UIColor.black.cgColor)
            for x in stride(from: 0, to: side, by: 6) {
                stripes.fill(CGRect(x: x, y: 0, width: 1, height: side))
            }
            let view = UIView(frame: CGRect(x: 20, y: 20, width: 40, height: 40))
            view.layer.contents = stripes.makeImage()
            view.layer.contentsScale = 3
            window.addSubview(view)

            let pixels = try await Pixels(render(window, with: mirror, scale: 0.5).0)
            // The view covers 20 x 20 output pixels; keep clear of its edges.
            let greys = (12 ..< 28).flatMap { y in (12 ..< 28).map { x in Int(pixels[x, y].red) } }
            // 5/6 white: about 212.
            #expect(greys.allSatisfy { (190 ... 235).contains($0) }, "min \(greys.min() ?? -1) max \(greys.max() ?? -1)")
        }

        @Test("screenshotScale defaults to nil, set values are clamped to 0.1...1, and NaN or infinity reset it to nil", arguments: [
            (input: -Double.greatestFiniteMagnitude, expected: 0.1), (input: -1, expected: 0.1), (input: 0, expected: 0.1),
            (input: Double.leastNonzeroMagnitude, expected: 0.1), (input: 0.05, expected: 0.1), (input: 0.1, expected: 0.1),
            (input: 0.333, expected: 0.333), (input: 0.5, expected: 0.5), (input: 1, expected: 1), (input: 2, expected: 1),
            (input: Double.greatestFiniteMagnitude, expected: 1), (input: Double.nan, expected: nil),
            (input: -Double.infinity, expected: nil), (input: Double.infinity, expected: nil),
        ] as [(input: Double, expected: Double?)])
        func screenshotScaleIsClamped(_ scale: (input: Double, expected: Double?)) {
            let config = PostHogSessionReplayConfig()
            #expect(config.screenshotScale == nil)
            config.screenshotScale = 0.25
            config.screenshotScale = NSNumber(value: scale.input)
            #expect(config.screenshotScale?.doubleValue == scale.expected)
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
