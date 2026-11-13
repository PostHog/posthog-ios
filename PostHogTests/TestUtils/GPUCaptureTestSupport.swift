#if os(iOS) && canImport(Metal)
    import Foundation
    @testable import PostHog
    import Testing
    import UIKit

    /// A prewarmed mirror, a window, and an SDK whose replay config the integration reads. Its recording is stopped, so
    /// its own capture loop stays out of the way.
    @MainActor
    struct GPUCaptureFixture {
        let mirror: PostHogGPUMirrorCapture
        let window: UIWindow
        let sut: PostHogSDK
        let integration: PostHogReplayIntegration
        var config: PostHogSessionReplayConfig { sut.config.sessionReplayConfig }
        var mask: PostHogInlineMask { mirror.inlineMask }

        func close() {
            window.rootViewController = nil
            window.isHidden = true
            sut.close()
        }
    }

    /// Fixtures shared by the GPU capture suites.
    @MainActor
    protocol GPUCaptureTesting {}

    extension GPUCaptureTesting {
        static func isMagenta(_ pixel: RGBA) -> Bool {
            pixel.red > 200 && pixel.green < 60 && pixel.blue > 200
        }

        /// Magenta of any brightness, a dark magenta included.
        static func isMagentaHue(_ pixel: RGBA) -> Bool {
            Int(pixel.red) - Int(pixel.green) > 40 && Int(pixel.blue) - Int(pixel.green) > 40
        }

        static func isStar(_ pixel: RGBA) -> Bool {
            pixel.red < 80 && pixel.green < 80 && pixel.blue > 180
        }

        static func isBlack(_ pixel: RGBA) -> Bool {
            pixel.red < 20 && pixel.green < 20 && pixel.blue < 20 && pixel.alpha > 230
        }

        func makeFixture(window: UIWindow? = nil, gpu: Bool = true) async throws -> GPUCaptureFixture {
            let mirror = try makeMirror()
            let window = window ?? makeWindow()
            let (sut, integration, _) = try makeScreenshotReplaySut { $0.screenshotModeGPUCapture = gpu }
            sut.stopSessionRecording()
            await prewarm(mirror, for: window)
            return GPUCaptureFixture(mirror: mirror, window: window, sut: sut, integration: integration)
        }

        func capture(_ fixture: GPUCaptureFixture, scale: CGFloat = 1) async throws -> PostHogReplayIntegration.MaskCaptureForTesting {
            fixture.window.layoutIfNeeded()
            // Displays freshly added views, as the app's own commit would have before a capture.
            CATransaction.flush()
            let result = await withCheckedContinuation { continuation in
                fixture.integration.gpuPathCaptureForTesting(window: fixture.window, mirror: fixture.mirror, scale: scale) {
                    continuation.resume(returning: $0)
                }
            }
            return try #require(result)
        }

        /// Masked text draws as `*` in `color` (nil for the text's own), and the first frame (bars) must leak nothing either,
        /// unless `checkingFirstFrame` is off.
        func captureStars(_ fixture: GPUCaptureFixture, color: UIColor? = .blue,
                          checkingFirstFrame: Bool = true) async throws -> PostHogReplayIntegration.MaskCaptureForTesting
        {
            PostHogInlineMask.textColorForTesting = color
            defer { PostHogInlineMask.textColorForTesting = nil }
            let first = try await capture(fixture)
            if checkingFirstFrame { try expectFullyMasked(first) }
            fixture.mask.waitForTextDrawsForTesting()
            return try await capture(fixture)
        }

        /// No magenta left and no region left to the rect pass: inline masking alone covered everything.
        @discardableResult
        func expectFullyMasked(_ result: PostHogReplayIntegration.MaskCaptureForTesting,
                               sourceLocation: SourceLocation = #_sourceLocation) throws -> Pixels
        {
            let pixels = try Pixels(result.image)
            #expect(pixels.count(where: Self.isMagenta) == 0, "source pixels left", sourceLocation: sourceLocation)
            #expect(result.rectRegions.isEmpty, "regions left to the rect pass", sourceLocation: sourceLocation)
            return pixels
        }

        func checkerboard(_ size: CGSize, cell: CGFloat = 4) throws -> UIImage {
            try #require(PostHogGraphicsImageRenderer(size: size, scale: 1).image { context in
                for y in stride(from: 0, to: size.height, by: cell) {
                    for x in stride(from: 0, to: size.width, by: cell) {
                        context.setFillColor((Int(x / cell + y / cell) % 2 == 0 ? UIColor.magenta : UIColor.black).cgColor)
                        context.fill(CGRect(x: x, y: y, width: cell, height: cell))
                    }
                }
            })
        }

        func makeMirror() throws -> PostHogGPUMirrorCapture {
            // Its own instance per test, so no renderer or frame carries over between tests.
            try #require(PostHogGPUMirrorCapture(), "the simulator has no Metal device")
        }

        func makeWindow(frame: CGRect = CGRect(x: 0, y: 0, width: 200, height: 300), background: UIColor = .white) -> UIWindow {
            let window = UIWindow(frame: frame)
            window.backgroundColor = background
            // Shown without becoming key, so the SDK's own capture loop never picks it up.
            window.isHidden = false
            return window
        }

        func prewarm(_ mirror: PostHogGPUMirrorCapture, for window: UIWindow, scale: CGFloat = 1) async {
            await withCheckedContinuation { continuation in
                mirror.prewarm(size: window.bounds.size, scale: scale) { continuation.resume() }
            }
        }

        func noCaptureView(_ frame: CGRect, color: UIColor = .magenta) -> UIView {
            let view = UIView(frame: frame)
            view.backgroundColor = color
            view.accessibilityIdentifier = "ph-no-capture"
            return view
        }

        /// Magenta layer contents: drawn content, which a mask has to remove, unlike a background colour.
        func magentaContents(_ size: CGSize) throws -> CGImage {
            let format = UIGraphicsImageRendererFormat()
            format.scale = 1
            return try #require(UIGraphicsImageRenderer(size: size, format: format).image { context in
                UIColor.magenta.setFill()
                context.fill(CGRect(origin: .zero, size: size))
            }.cgImage)
        }
    }
#endif
