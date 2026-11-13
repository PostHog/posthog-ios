#if os(iOS)
    import Foundation
    @testable import PostHog
    import QuartzCore
    import Testing
    import UIKit

    @Suite("Replay masking of content cleared since the last commit", .serialized)
    @MainActor
    struct PostHogClearedContentMaskingTest {
        private typealias Sut = (sdk: PostHogSDK, integration: PostHogReplayIntegration)

        private func makeSut() -> Sut {
            let config = PostHogConfig(projectToken: "phc_clearedContentMaskingTest")
            config.disableReachabilityForTesting = true
            config.sessionReplayConfig.maskAllTextInputs = true
            config.sessionReplayConfig.maskAllImages = true
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

        private func motionCapture(_ window: UIWindow, integration: PostHogReplayIntegration) throws -> (image: UIImage, rects: [CGRect]) {
            window.layoutIfNeeded()
            let rects = try #require(integration.collectMaskableRects(in: window))
            let image = try #require(window.toImage(renderer: .presentationTree))
            return (image, rects)
        }

        private func commit() async throws {
            CATransaction.flush()
            try await Task.sleep(nanoseconds: 50_000_000)
        }

        @Test("A sensitive label cleared since its last display stays masked while its layer still shows the old text")
        func clearedLabelStaysMaskedUntilRedrawn() async throws {
            let sut = makeSut()
            defer { teardown(sut) }
            let integration = sut.integration
            let window = makeReplayTestWindow()
            defer { window.isHidden = true }
            let label = UILabel(frame: CGRect(x: 20, y: 40, width: 160, height: 80))
            label.text = "SECRET"
            label.font = .boldSystemFont(ofSize: 48)
            label.textColor = .magenta
            window.addSubview(label)
            window.layoutIfNeeded()
            CATransaction.flush()
            try #require(!label.layer.needsDisplay())
            try #require(try #require(integration.collectMaskableRects(in: window)).contains(label.frame))

            // No run-loop turn in between: the layer still holds the old text's bitmap.
            label.text = ""

            let (image, rects) = try motionCapture(window, integration: integration)
            #expect(rects.contains(label.frame))
            try expectMagentaMasked(image, rects)
        }

        @Test("A sensitive image view cleared since its last commit stays masked while its layer still shows the old image")
        func clearedImageViewStaysMaskedUntilCommitted() async throws {
            let sut = makeSut()
            defer { teardown(sut) }
            let integration = sut.integration
            let window = makeReplayTestWindow()
            defer { window.isHidden = true }
            let size = CGSize(width: 160, height: 80)
            let format = UIGraphicsImageRendererFormat()
            format.scale = 1
            let photo = UIGraphicsImageRenderer(size: size, format: format).image { context in
                UIColor.white.setFill()
                context.fill(CGRect(origin: .zero, size: size))
                UIColor.magenta.setFill()
                context.fill(CGRect(x: 10, y: 10, width: 140, height: 60))
            }
            let imageView = UIImageView(image: photo)
            imageView.frame = CGRect(x: 20, y: 40, width: 160, height: 80)
            window.addSubview(imageView)
            let symbol = UIImageView(image: UIImage(systemName: "star.fill"))
            symbol.frame = CGRect(x: 20, y: 200, width: 40, height: 40)
            window.addSubview(symbol)
            window.layoutIfNeeded()
            try await commit()
            try #require(imageView.layer.presentation()?.contents != nil)
            let committedRects = try #require(integration.collectMaskableRects(in: window))
            try #require(committedRects.contains { $0.insetBy(dx: -1, dy: -1).contains(imageView.frame) })
            // Committed and unchanged, a symbol stays unmasked.
            #expect(!committedRects.contains { $0.intersects(symbol.frame) })

            // No run-loop turn in between: the presentation layer still holds the photo.
            imageView.image = nil

            let (image, rects) = try motionCapture(window, integration: integration)
            try expectMagentaMasked(image, rects)
            #expect(!rects.contains { $0.intersects(symbol.frame) })
        }

        @Test("An unclipped centered image view cleared since its last commit keeps the larger old image it still draws masked")
        func clearedOverflowingImageStaysMaskedWhereItDraws() async throws {
            let sut = makeSut()
            defer { teardown(sut) }
            let integration = sut.integration
            let window = makeReplayTestWindow()
            defer { window.isHidden = true }
            let size = CGSize(width: 160, height: 160)
            let format = UIGraphicsImageRendererFormat()
            format.scale = 1
            let photo = UIGraphicsImageRenderer(size: size, format: format).image { context in
                UIColor.white.setFill()
                context.fill(CGRect(origin: .zero, size: size))
                UIColor.magenta.setFill()
                context.fill(CGRect(x: 10, y: 10, width: 140, height: 140))
            }
            try #require(!photo.isSymbolImage)
            let imageView = try await clearedImageView(photo, frame: CGRect(x: 80, y: 100, width: 40, height: 40), contentMode: .center,
                                                       in: window)
            // A 160x160 image centered on the 40x40 bounds at (80, 100).
            let drawn = CGRect(x: 20, y: 40, width: 160, height: 160)

            let (image, rects) = try motionCapture(window, integration: integration)
            let covering = try #require(rects.first { $0.insetBy(dx: -1, dy: -1).contains(drawn) }, "\(rects)")
            // The extent is conservative: the bounds grown on every side by the image's 120pt overflow, plus its 160pt side in case it's drawn turned.
            #expect(imageView.frame.insetBy(dx: -281, dy: -281).contains(covering), "\(covering)")
            try expectMagentaMasked(image, rects)
            #expect(imageView.replacedImageExtent != nil)
        }

        @Test("An oriented image replaced since the last commit is masked where its rotated pixels land")
        func replacedOrientedImageIsMaskedWhereItLands() async throws {
            let sut = makeSut()
            defer { teardown(sut) }
            let integration = sut.integration
            let window = makeReplayTestWindow()
            defer { window.isHidden = true }
            // Stored 200x100, drawn 100x200.
            let image = try magentaImage(CGSize(width: 200, height: 100), orientation: .right)
            try #require(image.size == CGSize(width: 100, height: 200))
            let imageView = try await clearedImageView(image, frame: CGRect(x: 50, y: 100, width: 100, height: 60), contentMode: .center, in: window)
            let drawn = CGRect(x: 50, y: 30, width: 100, height: 200)

            // The layer's contents carry no orientation, so the mask reaches past the measured size by the image's longest side.
            let rects = try #require(integration.collectMaskableRects(in: window))
            #expect(rects.contains { $0.insetBy(dx: -1, dy: -1).contains(drawn) }, "\(rects)")
            #expect(imageView.replacedImageExtent != nil)
        }

        @Test("An image replaced since the last commit is masked from the bounds it's presented with, not the model's")
        func replacedImageIsMeasuredFromPresentedBounds() async throws {
            let sut = makeSut()
            defer { teardown(sut) }
            let integration = sut.integration
            let window = makeReplayTestWindow()
            defer { window.isHidden = true }
            let image = try magentaImage(CGSize(width: 160, height: 160))
            // Presented smaller than the model, so the image hangs further past the presented bounds.
            let presentedBounds = CGRect(x: 0, y: 0, width: 40, height: 40)
            let imageView = try await clearedImageView(image, frame: CGRect(x: 50, y: 50, width: 100, height: 100), contentMode: .topLeft,
                                                       in: window)
            { imageView in
                try await hold(imageView.layer, keyPath: "bounds", at: NSValue(cgRect: presentedBounds))
            }
            let presented = try #require(imageView.layer.presentation())
            try #require(presented.bounds == presentedBounds)
            let windowPresented = try #require(window.layer.presentation())
            let drawn = CGRect(origin: windowPresented.convert(presented.bounds.origin, from: presented), size: CGSize(width: 160, height: 160))

            let rects = try #require(integration.collectMaskableRects(in: window))
            let covering = try #require(rects.first { $0.insetBy(dx: -1, dy: -1).contains(drawn) }, "\(rects)")
            let presentedFrame = CGRect(origin: drawn.origin, size: presentedBounds.size)
            #expect(presentedFrame.insetBy(dx: -281, dy: -281).contains(covering), "\(covering)")
        }

        @Test("An oriented image cleared in a default scale-to-fill view is masked within the view")
        func clearedOrientedImageInFillViewIsMaskedWithinTheView() async throws {
            let sut = makeSut()
            defer { teardown(sut) }
            let integration = sut.integration
            let window = makeReplayTestWindow()
            defer { window.isHidden = true }
            let image = try magentaImage(CGSize(width: 200, height: 100), orientation: .right)
            let imageView = try await clearedImageView(image, frame: CGRect(x: 50, y: 100, width: 100, height: 60), contentMode: .scaleToFill,
                                                       in: window)

            let (rendered, rects) = try motionCapture(window, integration: integration)
            let limit = window.bounds.insetBy(dx: -1, dy: -1)
            #expect(rects.allSatisfy { limit.contains($0) }, "\(rects)")
            #expect(rects.contains { $0.insetBy(dx: -1, dy: -1).contains(imageView.frame) }, "\(rects)")
            try expectMagentaMasked(rendered, rects)
        }

        @Test("A sensitive label with no text is not masked once settled")
        func emptyLabelIsNotMaskedOnceSettled() async throws {
            let sut = makeSut()
            defer { teardown(sut) }
            let integration = sut.integration
            let window = makeReplayTestWindow()
            defer { window.isHidden = true }
            let label = UILabel(frame: CGRect(x: 20, y: 40, width: 160, height: 80))
            window.addSubview(label)
            window.layoutIfNeeded()
            try await commit()
            #expect(try #require(integration.collectMaskableRects(in: window)).isEmpty)

            label.text = "SECRET"
            window.layoutIfNeeded()
            try await commit()
            label.text = ""
            window.layoutIfNeeded()
            try await commit()
            #expect(try #require(integration.collectMaskableRects(in: window)).isEmpty)
        }

        @Test("A photo replaced by another image in the same turn stays masked while the old photo still draws")
        func photoReplacedByAnotherImageStaysMasked() async throws {
            let sut = makeSut()
            defer { teardown(sut) }
            let integration = sut.integration
            let window = makeReplayTestWindow()
            defer { window.isHidden = true }
            let imageView = try UIImageView(image: magentaImage(CGSize(width: 160, height: 80)))
            imageView.frame = CGRect(x: 20, y: 40, width: 160, height: 80)
            window.addSubview(imageView)
            window.layoutIfNeeded()
            try await commit()
            try #require(imageView.layer.presentation()?.contents != nil)

            imageView.image = UIImage(systemName: "star.fill")

            let (image, rects) = try motionCapture(window, integration: integration)
            try expectMagentaMasked(image, rects)
        }

        @Test("A symbol swapped for another symbol in the same turn keeps its image wireframe")
        func swappedSymbolKeepsImageWireframe() async throws {
            let sut = makeSut()
            defer { teardown(sut) }
            let window = makeReplayTestWindow()
            defer { window.isHidden = true }
            let symbol = UIImageView(image: UIImage(systemName: "star.fill"))
            symbol.frame = CGRect(x: 20, y: 40, width: 40, height: 40)
            window.addSubview(symbol)
            window.layoutIfNeeded()
            try await commit()

            symbol.image = UIImage(systemName: "heart.fill")

            let root = try #require(sut.integration.toWireframe(window))
            let imageWireframe = try #require(imageWireframes(in: root).first)
            #expect(imageWireframe.image != nil)
        }

        @Test("A no-capture image view showing a replaced image masks its unclipped subviews too")
        func noCaptureReplacedImageMasksItsSubviews() async throws {
            let sut = makeSut()
            defer { teardown(sut) }
            sut.sdk.config.sessionReplayConfig.maskAllTextInputs = false
            sut.sdk.config.sessionReplayConfig.maskAllImages = false
            let window = makeReplayTestWindow()
            defer { window.isHidden = true }
            let parent = try UIImageView(image: magentaImage(CGSize(width: 60, height: 60)))
            parent.contentMode = .scaleToFill
            parent.clipsToBounds = false
            parent.accessibilityIdentifier = "ph-no-capture"
            parent.frame = CGRect(x: 20, y: 40, width: 60, height: 60)
            window.addSubview(parent)
            let child = UILabel(frame: CGRect(x: 80, y: 100, width: 80, height: 40))
            child.text = "SECRET"
            parent.addSubview(child)
            let unmasked = UILabel(frame: CGRect(x: 0, y: 140, width: 80, height: 40))
            unmasked.text = "PUBLIC"
            unmasked.accessibilityIdentifier = "ph-no-mask"
            parent.addSubview(unmasked)
            window.layoutIfNeeded()
            try await commit()
            try #require(parent.layer.presentation()?.contents != nil)

            parent.image = nil

            let rects = try #require(sut.integration.collectMaskableRects(in: window))
            let childRect = child.convert(child.bounds, to: window)
            #expect(rects.contains { $0.insetBy(dx: -1, dy: -1).contains(childRect) }, "\(rects)")
            let unmaskedRect = unmasked.convert(unmasked.bounds, to: window)
            #expect(!rects.contains { $0.intersects(unmaskedRect) }, "\(rects)")
        }

        @Test("An image view with an app-defined layer class isn't copied for its presentation")
        func customLayerImageViewIsNotCopiedForPresentation() async throws {
            let sut = makeSut()
            defer { teardown(sut) }
            let window = makeReplayTestWindow()
            defer { window.isHidden = true }
            let symbol = CopyCountingImageView(image: UIImage(systemName: "star.fill"))
            symbol.frame = CGRect(x: 20, y: 40, width: 40, height: 40)
            window.addSubview(symbol)
            window.layoutIfNeeded()
            try await commit()
            try #require(symbol.layer is CopyCountingLayer)
            try await hold(symbol.layer, keyPath: "opacity", at: 1)
            CopyCountingLayer.copies = 0

            let rects = try #require(sut.integration.collectMaskableRects(in: window))
            #expect(CopyCountingLayer.copies == 0)
            #expect(!rects.contains { $0.intersects(symbol.frame) }, "\(rects)")
        }

        private func imageWireframes(in wireframe: RRWireframe) -> [RRWireframe] {
            (wireframe.type == "image" ? [wireframe] : []) + (wireframe.childWireframes ?? []).flatMap(imageWireframes)
        }
    }

    private final class CopyCountingLayer: CALayer {
        nonisolated(unsafe) static var copies = 0

        override init() {
            super.init()
        }

        override init(layer: Any) {
            Self.copies += 1
            super.init(layer: layer)
        }

        @available(*, unavailable)
        required init?(coder _: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }
    }

    private final class CopyCountingImageView: UIImageView {
        override class var layerClass: AnyClass {
            CopyCountingLayer.self
        }
    }
#endif
