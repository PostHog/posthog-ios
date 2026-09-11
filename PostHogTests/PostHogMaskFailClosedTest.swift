//
//  Fail-closed masking coverage (GitHub issue #821). Three paths could put content
//  the config masks into an uploaded snapshot: a screenshot sent raw after the
//  masked render failed, and two visibility checks that skipped a subtree the
//  screenshot still draws — a zero-size non-clipping parent (React Native's default
//  `overflow: visible` wrapper) and a view whose model alpha already parked at 0
//  while it fades out.
//

#if os(iOS)
    import CoreGraphics
    import Foundation
    @testable import PostHog
    import Testing
    import UIKit

    /// A layer that reports an in-flight fade: the model opacity is 0 while the
    /// presentation layer the screenshot renders is still opaque. Deterministic stand-in
    /// for `UIView.animate { view.alpha = 0 }`, whose presentation values need a real
    /// render server commit.
    private final class FadingOutLayer: CALayer {
        override func presentation() -> CALayer? {
            let presentation = CALayer()
            presentation.bounds = bounds
            presentation.position = position
            presentation.opacity = 1
            return presentation
        }
    }

    private final class FadingOutView: UIView {
        override class var layerClass: AnyClass { FadingOutLayer.self }
    }

    @Suite("Replay masking fails closed", .serialized)
    @MainActor
    struct PostHogMaskFailClosedTest {
        private typealias Sut = (sdk: PostHogSDK, integration: PostHogReplayIntegration)

        private func makeSut() -> Sut {
            let config = PostHogConfig(projectToken: "phc_maskFailClosedTest")
            config.disableReachabilityForTesting = true
            config.sessionReplayConfig.maskAllTextInputs = true
            PostHogReplayIntegration.clearInstalls()
            let sdk = PostHogSDK.with(config)
            let integration = PostHogReplayIntegration()
            _ = integration.install(sdk)
            return (sdk, integration)
        }

        private func teardown(_ sut: Sut) {
            sut.integration.uninstall(sut.sdk)
            sut.sdk.close()
        }

        private func makeWindow(containing view: UIView) -> UIWindow {
            let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 640))
            window.addSubview(view)
            window.layoutIfNeeded()
            return window
        }

        private func makeSecretLabel(frame: CGRect) -> UILabel {
            let label = UILabel(frame: frame)
            label.text = "SSN 123-45-6789"
            return label
        }

        // MARK: - Mask render failure

        /// An image whose pixel size rounds to zero, so `PostHogGraphicsImageRenderer`
        /// returns nil exactly as it does when the full-frame malloc or the CGContext fails.
        private func makeUnrenderableImage() -> UIImage {
            let pixel = CGContext(
                data: nil, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )!
            return UIImage(cgImage: pixel.makeImage()!, scale: 8, orientation: .up)
        }

        private func makeRenderableImage() -> UIImage {
            UIGraphicsImageRenderer(size: CGSize(width: 40, height: 40)).image { context in
                UIColor.white.setFill()
                context.fill(CGRect(x: 0, y: 0, width: 40, height: 40))
            }
        }

        @Test("a screenshot whose masked render fails carries no image and is marked for dropping")
        func maskRenderFailureDropsTheFrame() {
            let wireframe = RRWireframe()
            wireframe.type = "screenshot"
            wireframe.image = makeUnrenderableImage()
            wireframe.maskableWidgets = [CGRect(x: 0, y: 0, width: 10, height: 10)]

            let dict = wireframe.toDict()

            #expect(dict["base64"] == nil)
            #expect(wireframe.maskRenderFailed)
        }

        @Test("a screenshot with nothing to mask still sends the image")
        func unmaskedScreenshotStillSends() {
            let wireframe = RRWireframe()
            wireframe.type = "screenshot"
            wireframe.image = makeRenderableImage()

            let dict = wireframe.toDict()

            #expect(dict["base64"] != nil)
            #expect(!wireframe.maskRenderFailed)
        }

        @Test("a successful masked render sends the redacted image")
        func maskedScreenshotSends() {
            let wireframe = RRWireframe()
            wireframe.type = "screenshot"
            wireframe.image = makeRenderableImage()
            wireframe.maskableWidgets = [CGRect(x: 0, y: 0, width: 10, height: 10)]

            let dict = wireframe.toDict()

            #expect(dict["base64"] != nil)
            #expect(!wireframe.maskRenderFailed)
        }

        // MARK: - Zero-size parents

        @Test("text inside a zero-size non-clipping parent is masked")
        func zeroSizeNonClippingParentIsTraversed() {
            let sut = makeSut()
            defer { teardown(sut) }

            let wrapper = UIView(frame: .zero)
            wrapper.clipsToBounds = false
            let label = makeSecretLabel(frame: CGRect(x: 24, y: 120, width: 200, height: 32))
            wrapper.addSubview(label)
            let window = makeWindow(containing: wrapper)

            #expect(sut.integration.collectMaskableRects(in: window) == [CGRect(x: 24, y: 120, width: 200, height: 32)])
        }

        @Test("a zero-size clipping parent draws nothing, so its subtree is skipped")
        func zeroSizeClippingParentIsSkipped() {
            let sut = makeSut()
            defer { teardown(sut) }

            let wrapper = UIView(frame: .zero)
            wrapper.clipsToBounds = true
            wrapper.addSubview(makeSecretLabel(frame: CGRect(x: 24, y: 120, width: 200, height: 32)))
            let window = makeWindow(containing: wrapper)

            #expect(sut.integration.collectMaskableRects(in: window) == [])
        }

        // MARK: - Fading views

        @Test("text inside a view that is fading out is masked")
        func fadingOutParentIsTraversed() {
            let sut = makeSut()
            defer { teardown(sut) }

            let fading = FadingOutView(frame: CGRect(x: 0, y: 0, width: 320, height: 640))
            fading.alpha = 0
            fading.addSubview(makeSecretLabel(frame: CGRect(x: 24, y: 120, width: 200, height: 32)))
            let window = makeWindow(containing: fading)

            #expect(sut.integration.collectMaskableRects(in: window) == [CGRect(x: 24, y: 120, width: 200, height: 32)])
        }

        @Test("a fully transparent view draws nothing, so its subtree is skipped")
        func transparentParentIsSkipped() {
            let sut = makeSut()
            defer { teardown(sut) }

            let transparent = UIView(frame: CGRect(x: 0, y: 0, width: 320, height: 640))
            transparent.alpha = 0
            transparent.addSubview(makeSecretLabel(frame: CGRect(x: 24, y: 120, width: 200, height: 32)))
            let window = makeWindow(containing: transparent)

            #expect(sut.integration.collectMaskableRects(in: window) == [])
        }
    }
#endif
