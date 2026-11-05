#if os(iOS)
    import Foundation
    @testable import PostHog
    import QuartzCore
    import Testing
    import UIKit

    @Suite("Replay masking never copies a presentation that can trap", .serialized)
    @MainActor
    struct PostHogMaskPresentationSafetyTest {
        /// The default path's pixels and mask rects for a settled capture in `band`, nil when it skips the frame.
        private func settledCapture(_ window: UIWindow, band: PostHogReplayIntegration.SettleBand,
                                    integration: PostHogReplayIntegration = PostHogReplayIntegration()) throws
            -> (image: UIImage, rects: [CGRect], preferFidelityRenderer: Bool)?
        {
            let regions = try #require(integration.collectMaskedRegions(in: window))
            guard let rendering = PostHogReplayIntegration.settledRendering(of: window, band: band, inflatedRects: nil, regions: regions) else {
                return nil
            }
            return try (#require(window.toImage(preferFidelityRenderer: rendering.preferFidelityRenderer)), #require(rendering.rects),
                        rendering.preferFidelityRenderer)
        }

        private func motionCapture(_ window: UIWindow, integration: PostHogReplayIntegration = PostHogReplayIntegration()) throws
            -> (image: UIImage, rects: [CGRect])
        {
            window.layoutIfNeeded()
            let capture = try #require(try settledCapture(window, band: .motion, integration: integration), "the motion frame was skipped")
            #expect(!capture.preferFidelityRenderer)
            return (capture.image, capture.rects)
        }

        private func commit() async throws {
            CATransaction.flush()
            try await Task.sleep(nanoseconds: 50_000_000)
        }

        // MARK: - Layers whose presentation can't be copied

        /// A masked field under a container whose app layer class can't be copied, committed and settled. Converting a
        /// copy of the field's presentation would copy the container's too.
        private func fieldUnderUncopyableContainer(in window: UIWindow) async throws -> (container: UIView, field: UIView) {
            try #require(!CALayer.isPresentationSafe(TrappingLayer.self))
            let container = TrappingView(frame: CGRect(x: 20, y: 20, width: 160, height: 160))
            let field = secretField(CGRect(x: 10, y: 10, width: 120, height: 60))
            container.addSubview(field)
            window.addSubview(container)
            window.layoutIfNeeded()
            try await commit()
            return (container, field)
        }

        @Test("A masked view under a static app layer that can't be copied is masked over the whole window, without copying that layer")
        func maskedViewUnderStaticUncopyableContainer() async throws {
            let window = makeReplayTestWindow()
            let (_, field) = try await fieldUnderUncopyableContainer(in: window)

            let rects = try #require(PostHogReplayIntegration().collectMaskableRects(in: window))
            #expect(rects.contains { $0.contains(window.bounds) && $0.contains(field.convert(field.bounds, to: window)) }, "\(rects)")
        }

        @Test("A masked view under a moving app layer that can't be copied is masked over the whole window, even inside a smaller ancestor",
              arguments: [false, true])
        func maskedViewUnderMovingUncopyableContainerFailsClosed(insideSmallerAncestor: Bool) async throws {
            let window = makeReplayTestWindow()
            let (container, field) = try await fieldUnderUncopyableContainer(in: window)
            if insideSmallerAncestor {
                let holder = UIView(frame: CGRect(x: 10, y: 10, width: 100, height: 100))
                window.addSubview(holder)
                holder.addSubview(container)
            }
            try await animateDown(container.layer, by: 150, checksPresentation: false)

            let rects = try #require(PostHogReplayIntegration().collectMaskableRects(in: window))
            #expect(rects.contains { $0.contains(window.bounds) && $0.contains(field.convert(field.bounds, to: window)) }, "\(rects)")
        }

        @Test("A masked view moving under an app layer with its own init(layer:) is masked over the whole window, since that layer isn't copied either")
        func movingViewUnderStaticAppLayerIsMaskedOverTheWindow() async throws {
            let window = makeReplayTestWindow()
            try #require(!CALayer.isPresentationSafe(AppAnimatableLayer.self))
            let holder = UIView(frame: CGRect(x: 20, y: 20, width: 100, height: 100))
            let app = AppLayerView(frame: CGRect(x: 10, y: 10, width: 80, height: 80))
            let field = secretField(CGRect(x: 5, y: 5, width: 60, height: 30))
            app.addSubview(field)
            holder.addSubview(app)
            window.addSubview(holder)
            window.layoutIfNeeded()
            try await commit()
            // Presented far below the holder, the model still inside it.
            try await hold(field.layer, keyPath: "position", at: NSValue(cgPoint: CGPoint(x: 35, y: 220)))
            try #require(app.layer.animationKeys() == nil)

            let presented = CGRect(x: 35, y: 235, width: 60, height: 30)
            let rects = try #require(PostHogReplayIntegration().collectMaskableRects(in: window))
            #expect(rects.contains { $0.contains(window.bounds) && $0.contains(presented) }, "\(rects)")
        }

        @Test("A masked view whose own app layer can't be copied is masked where it sits while nothing moves it, and over the whole window while something does",
              arguments: [false, true])
        func maskedUncopyableViewIsMaskedFromItsModel(moving: Bool) async throws {
            let window = makeReplayTestWindow()
            try #require(!CALayer.isPresentationSafe(TrappingLayer.self))
            let view = TrappingView(frame: CGRect(x: 20, y: 40, width: 120, height: 60))
            view.backgroundColor = .magenta
            view.accessibilityIdentifier = "ph-no-capture"
            window.addSubview(view)
            window.layoutIfNeeded()
            try await commit()
            if moving {
                try await animateDown(view.layer, by: 150, checksPresentation: false)
            }

            let rects = try #require(PostHogReplayIntegration().collectMaskableRects(in: window))
            if moving {
                #expect(rects.contains { $0.contains(window.bounds) }, "\(rects)")
            } else {
                #expect(rects == [view.frame])
            }
        }

        @Test("A motion frame of a window holding a layer whose presentation can't be copied is skipped, while still and drift frames draw with drawHierarchy",
              arguments: [false, true])
        func motionFrameOfUncopyableWindowIsSkipped(animating: Bool) async throws {
            let window = makeReplayTestWindow()
            try #require(!CALayer.isPresentationSafe(TrappingLayer.self))
            let view = TrappingView(frame: CGRect(x: 20, y: 20, width: 100, height: 100))
            view.backgroundColor = .magenta
            window.addSubview(view)
            window.addSubview(secretField(CGRect(x: 20, y: 160, width: 120, height: 60)))
            window.layoutIfNeeded()
            try await commit()
            if animating {
                try await hold(view.layer, keyPath: "opacity", at: Float(1))
            }

            let regions = try #require(PostHogReplayIntegration().collectMaskedRegions(in: window))
            #expect(!window.layer.canRenderPresentationTree)
            #expect(PostHogReplayIntegration.settledRendering(of: window, band: .motion, inflatedRects: nil, regions: regions) == nil)
            for band in [PostHogReplayIntegration.SettleBand.still, .drift] {
                let rendering = try #require(PostHogReplayIntegration.settledRendering(of: window, band: band, inflatedRects: nil, regions: regions))
                #expect(rendering.preferFidelityRenderer)
                #expect(rendering.rects == regions.map(\.rect))
            }
        }

        @Test("A masked view under an app layer moved since its last commit, without an animation, keeps what the screen shows masked through the settle check",
              arguments: [20, 150] as [CGFloat])
        func uncommittedAppLayerMoveStaysMaskedThroughTheSettleCheck(distance: CGFloat) async throws {
            let window = makeReplayTestWindow()
            let integration = PostHogReplayIntegration()
            let container = AppLayerView(frame: CGRect(x: 20, y: 20, width: 160, height: 100))
            let field = secretField(CGRect(x: 10, y: 10, width: 120, height: 60))
            container.addSubview(field)
            window.addSubview(container)
            window.layoutIfNeeded()
            try await commit()
            let committed = field.convert(field.bounds, to: window)
            let sentinel = integration.collectMaskedRegions(in: window)

            // No run-loop turn in between: the model moves, the screen still shows the last commit.
            container.frame.origin.y += distance
            try #require(container.layer.animationKeys() == nil)
            let regions = integration.collectMaskedRegions(in: window)
            let verdict = PostHogReplayIntegration.settleVerdict(before: sentinel, after: regions)
            let rendering = try #require(PostHogReplayIntegration.settledRendering(of: window, band: verdict.band,
                                                                                   inflatedRects: verdict.inflatedRects, regions: regions))
            // drawHierarchy, which shows the last commit.
            #expect(rendering.preferFidelityRenderer)
            let rects = try #require(rendering.rects)
            #expect(rects.contains { $0.contains(committed) && $0.contains(field.convert(field.bounds, to: window)) }, "\(rects)")
        }

        @Test("A masked view under an app layer set to alpha 0 since its last commit stays masked, since the screen still shows it")
        func maskedViewUnderUncommittedAppLayerFadeStaysMasked() async throws {
            let window = makeReplayTestWindow()
            try #require(!CALayer.isPresentationSafe(AppAnimatableLayer.self))
            let container = AppLayerView(frame: CGRect(x: 20, y: 20, width: 160, height: 100))
            let field = secretField(CGRect(x: 10, y: 10, width: 120, height: 60))
            container.addSubview(field)
            window.addSubview(container)
            window.layoutIfNeeded()
            try await commit()

            // No run-loop turn in between: the screen still shows the last commit.
            container.alpha = 0
            try #require(container.layer.animationKeys() == nil)

            let rects = try #require(PostHogReplayIntegration().collectMaskableRects(in: window))
            #expect(rects.contains { $0.contains(field.convert(field.bounds, to: window)) }, "\(rects)")
        }

        @Test("A masked view under a plain view set to alpha 0 and committed is no longer masked")
        func maskedViewUnderCommittedTransparentViewIsDropped() async throws {
            let window = makeReplayTestWindow()
            let container = UIView(frame: CGRect(x: 20, y: 20, width: 160, height: 100))
            let field = secretField(CGRect(x: 10, y: 10, width: 120, height: 60))
            container.addSubview(field)
            window.addSubview(container)
            window.layoutIfNeeded()
            try await commit()
            container.alpha = 0
            try await commit()

            let rects = try #require(PostHogReplayIntegration().collectMaskableRects(in: window))
            #expect(!rects.contains { $0.intersects(field.convert(field.bounds, to: window)) }, "\(rects)")
        }

        // MARK: - The presentation tree

        @Test("A view added under a parent mid-animation, before it commits, is masked where the parent's presentation places it")
        func uncommittedChildUnderAnimatingParentIsMasked() async throws {
            let window = makeReplayTestWindow()
            let parent = UIView(frame: CGRect(x: 20, y: 20, width: 160, height: 100))
            window.addSubview(parent)
            CATransaction.flush()
            try await animateDown(parent.layer, by: 150)
            let field = secretField(CGRect(x: 10, y: 10, width: 120, height: 60))
            parent.addSubview(field)
            try #require(field.layer.presentation() == nil)
            let expected = try #require(parent.layer.presentation()).convert(field.frame, to: window.layer)

            let (image, rects) = try motionCapture(window)
            #expect(rects.contains { $0.insetBy(dx: -1, dy: -1).contains(expected) }, "\(rects)")
            // The presentation tree the default path renders doesn't hold the uncommitted view yet.
            #expect(try maskedPixels(image, rects).points(where: \.isMagenta).isEmpty)
        }

        @Test("A masked view whose shadow is fading out, the model already at no shadow, keeps the shadow it still draws masked")
        func fadingShadowOfMaskedViewIsMasked() async throws {
            let window = makeReplayTestWindow()
            let field = secretField(CGRect(x: 20, y: 40, width: 120, height: 60))
            field.layer.shadowColor = UIColor.magenta.cgColor
            field.layer.shadowRadius = 0
            field.layer.shadowOffset = CGSize(width: 0, height: 100)
            field.layer.shadowOpacity = 0
            window.addSubview(field)
            CATransaction.flush()
            try await hold(field.layer, keyPath: "shadowOpacity", at: Float(1))
            try #require(field.layer.presentation()?.shadowOpacity == 1)

            let rects = try #require(PostHogReplayIntegration().collectMaskableRects(in: window))
            // The magenta inset in the field, repeated by the shadow 100pt below.
            let shadow = CGRect(x: 25, y: 145, width: 110, height: 50)
            #expect(rects.contains { $0.insetBy(dx: -1, dy: -1).contains(shadow) }, "\(rects)")
        }

        // MARK: - Content cleared since the last commit

        @Test("A sensitive label cleared since its last display stays masked while its layer still shows the old text")
        func clearedLabelStaysMaskedUntilRedrawn() async throws {
            let (sut, integration, _) = try makeScreenshotReplaySut()
            defer { sut.close() }
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
            let (sut, integration, _) = try makeScreenshotReplaySut()
            defer { sut.close() }
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
            let (sut, integration, _) = try makeScreenshotReplaySut()
            defer { sut.close() }
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

        @Test("The mask walk never copies an image view's presentation when its app layer class can't be copied, and masks it whenever images are",
              arguments: [false, true])
        func imageViewWithUncopyableLayerIsWalkedWithoutItsPresentation(maskAllImages: Bool) async throws {
            let (sut, integration, _) = try makeScreenshotReplaySut { $0.maskAllImages = maskAllImages }
            defer { sut.close() }
            let window = makeReplayTestWindow()
            try #require(!CALayer.isPresentationSafe(TrappingLayer.self))
            // A symbol, which an image view whose presentation can be read leaves unmasked.
            let view = TrappingImageView(image: UIImage(systemName: "star.fill"))
            view.frame = CGRect(x: 20, y: 40, width: 40, height: 40)
            window.addSubview(view)
            window.layoutIfNeeded()
            CATransaction.flush()
            // An animation puts the layer in the presentation tree, so presentation() would copy it.
            try await hold(view.layer, keyPath: "opacity", at: Float(1))

            // Whether the image it still shows was replaced since the last commit can't be read, so it's masked.
            let rects = try #require(integration.collectMaskableRects(in: window))
            #expect(rects.contains { $0.contains(view.frame) } == maskAllImages)
            #expect(maskAllImages || !rects.contains { $0.intersects(view.frame) })
        }

        @Test("An unclipped image view whose app layer class can't be copied, its image cleared this turn, stays masked as far as an image can reach")
        func clearedOverflowingImageViewWithUncopyableLayerStaysMasked() async throws {
            let (sut, integration, _) = try makeScreenshotReplaySut()
            defer { sut.close() }
            let window = makeReplayTestWindow()
            try #require(!CALayer.isPresentationSafe(TrappingLayer.self))
            let photo = try magentaImage(CGSize(width: 160, height: 160))
            try #require(!photo.isSymbolImage)
            let imageView = TrappingImageView(image: photo)
            imageView.contentMode = .center
            imageView.clipsToBounds = false
            imageView.frame = CGRect(x: 80, y: 100, width: 40, height: 40)
            window.addSubview(imageView)
            window.layoutIfNeeded()
            try await commit()
            // A 160x160 image centered on the 40x40 bounds at (80, 100).
            let drawn = CGRect(x: 20, y: 40, width: 160, height: 160)

            // No run-loop turn in between: the presentation layer may still hold the photo.
            imageView.image = nil

            let rects = try #require(integration.collectMaskableRects(in: window))
            #expect(rects.contains { $0.insetBy(dx: -1, dy: -1).contains(drawn) }, "\(rects)")
        }

        @Test("An oriented image replaced since the last commit is masked where its rotated pixels land")
        func replacedOrientedImageIsMaskedWhereItLands() async throws {
            let (sut, integration, _) = try makeScreenshotReplaySut()
            defer { sut.close() }
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
            let (sut, integration, _) = try makeScreenshotReplaySut()
            defer { sut.close() }
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
