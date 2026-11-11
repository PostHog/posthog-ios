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
            let image = try #require(window.toImage(preferFidelityRenderer: false))
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
            #expect(rects.contains { $0.insetBy(dx: -1, dy: -1).contains(drawn) }, "\(rects)")
            try expectMagentaMasked(image, rects)
            #expect(imageView.replacedImageExtent != nil)
        }

        @Test("An oriented image replaced since the last commit is masked where its rotated pixels land")
        func replacedOrientedImageIsMaskedWhereItLands() async throws {
            let sut = makeSut()
            defer { teardown(sut) }
            let integration = sut.integration
            let window = makeReplayTestWindow()
            // Stored 200x100, drawn 100x200.
            let image = try magentaImage(CGSize(width: 200, height: 100), orientation: .right)
            try #require(image.size == CGSize(width: 100, height: 200))
            let imageView = try await clearedImageView(image, frame: CGRect(x: 50, y: 100, width: 100, height: 60), contentMode: .center, in: window)
            let drawn = CGRect(x: 50, y: 30, width: 100, height: 200)

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
            #expect(rects.contains { $0.insetBy(dx: -1, dy: -1).contains(drawn) }, "\(rects)")
        }
    }
#endif
