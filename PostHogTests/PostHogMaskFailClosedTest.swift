//
//  Fail-closed masking coverage (GitHub issue #821). Three paths could put content
//  the config masks into an uploaded snapshot: a screenshot sent raw after the
//  masked render failed, and two visibility checks that skipped a subtree the
//  screenshot still draws — a zero-size non-clipping parent (React Native's default
//  `overflow: visible` wrapper) and a view whose model alpha already parked at 0
//  while it fades out.
//

#if os(iOS) && (!SWIFT_PACKAGE || SessionReplay)
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
        override func presentation() -> Self? {
            let presentation = FadingOutLayer()
            presentation.bounds = bounds
            presentation.position = position
            presentation.opacity = 1
            // `presentationLayer` is imported as `-> Self?`, and this class is final,
            // so the cast always succeeds.
            return presentation as? Self
        }
    }

    private final class FadingOutView: UIView {
        override class var layerClass: AnyClass { FadingOutLayer.self }
    }

    private final class CustomDrawnSecretView: UIView {
        override func draw(_ rect: CGRect) {
            ("Sensitive content" as NSString).draw(in: rect, withAttributes: [.foregroundColor: UIColor.black])
        }
    }

    private final class CollapsingLayer: CALayer {
        var renderedBounds: CGRect = .zero

        override func presentation() -> Self? {
            let presentation = CollapsingLayer()
            presentation.bounds = renderedBounds
            presentation.position = position
            presentation.opacity = opacity
            return presentation as? Self
        }
    }

    private final class CollapsingView: UIView {
        override class var layerClass: AnyClass { CollapsingLayer.self }
    }

    @Suite("Replay masking fails closed", .serialized)
    @MainActor
    struct PostHogMaskFailClosedTest {
        private typealias Sut = (sdk: PostHogSDK, integration: PostHogReplayIntegration)

        private func makeSut(maskAllTextInputs: Bool = true, maskAllImages: Bool = true) -> Sut {
            let config = PostHogConfig(projectToken: "phc_maskFailClosedTest")
            config.disableReachabilityForTesting = true
            config.sessionReplayConfig.maskAllTextInputs = maskAllTextInputs
            config.sessionReplayConfig.maskAllImages = maskAllImages
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

        private func captureSnapshotTypes(
            failures: [Bool],
            queueTogether: Bool = false,
            episodeFirstFrames: Set<Int> = []
        ) -> [[Int]] {
            captureSnapshots(failures: failures, queueTogether: queueTogether, episodeFirstFrames: episodeFirstFrames)
                .map { $0.compactMap { $0["type"] as? Int } }
        }

        private func captureSnapshots(
            failures: [Bool],
            queueTogether: Bool = false,
            episodeFirstFrames: Set<Int> = [],
            windowSizes: [CGSize] = []
        ) -> [[[String: Any]]] {
            let server = MockPostHogServer()
            server.start()
            defer { server.stop() }

            let lock = NSLock()
            var captured: [[[String: Any]]] = []
            let config = PostHogConfig(projectToken: "phc_snapshotMetadataTest", host: "http://localhost:9001")
            config.disableReachabilityForTesting = true
            config.disableQueueTimerForTesting = true
            config.captureApplicationLifecycleEvents = false
            config.setBeforeSend { event in
                if event.event == "$snapshot", let snapshots = event.properties["$snapshot_data"] as? [[String: Any]] {
                    lock.withLock { captured.append(snapshots) }
                }
                return nil
            }
            let sdk = PostHogSDK.with(config)
            defer { sdk.close() }
            let integration = PostHogReplayIntegration()
            let window = makeWindow(containing: UIView())
            let queue = PostHogReplayIntegration.dispatchQueue

            if queueTogether {
                queue.suspend()
            }
            for (index, fails) in failures.enumerated() {
                let wireframe = RRWireframe()
                wireframe.type = "screenshot"
                wireframe.image = fails ? makeUnrenderableImage() : makeRenderableImage()
                wireframe.maskableWidgets = [CGRect(x: index * 5, y: 0, width: 10, height: 10)]
                if index < windowSizes.count {
                    window.frame = CGRect(origin: .zero, size: windowSizes[index])
                }
                integration.captureSnapshot(
                    wireframe,
                    window: window,
                    windowSize: window.bounds.size,
                    screenName: "Screen \(index)",
                    postHog: sdk,
                    timestampDate: Date(),
                    episodeFirstFrame: episodeFirstFrames.contains(index)
                )
                if !queueTogether {
                    queue.sync {}
                }
            }
            if queueTogether {
                queue.resume()
                queue.sync {}
            }
            return lock.withLock { captured }
        }

        @Test("first-frame failure preserves metadata for recovery")
        func firstFrameFailurePreservesMetadata() {
            #expect(captureSnapshotTypes(failures: [true, false]) == [[4, 2]])
        }

        @Test("a queued recovery frame includes metadata after the first render fails")
        func queuedRecoveryIncludesMetadata() {
            #expect(captureSnapshotTypes(failures: [true, false, false], queueTogether: true) == [[4, 2], [2]])
        }

        @Test("a later render failure does not resend metadata that was already sent")
        func laterFailureDoesNotResendMetadata() {
            #expect(captureSnapshotTypes(failures: [false, true, false]) == [[4, 2], [2]])
        }

        @Test("queued successful frames send metadata only once")
        func queuedSuccessesSendMetadataOnce() {
            #expect(captureSnapshotTypes(failures: [false, false], queueTogether: true) == [[4, 2], [2]])
        }

        @Test("a failed opening frame of a new bridge episode keeps its metadata pending")
        func failedEpisodeOpeningPreservesMetadata() {
            #expect(captureSnapshotTypes(failures: [false, true, false], episodeFirstFrames: [1]) == [[4, 2], [4, 2]])
        }

        @Test("metadata is resent when the same window changes size, as on rotation or a fold")
        func windowResizeResendsMetadata() {
            let portrait = CGSize(width: 320, height: 640)
            let landscape = CGSize(width: 640, height: 320)
            let snapshots = captureSnapshots(
                failures: [false, false, false, false],
                windowSizes: [portrait, landscape, landscape, portrait]
            )
            #expect(snapshots.map { $0.compactMap { $0["type"] as? Int } } == [[4, 2], [4, 2], [2], [4, 2]])
            let metaSizes = snapshots.flatMap { $0 }
                .filter { $0["type"] as? Int == 4 }
                .compactMap { $0["data"] as? [String: Any] }
                .map { [$0["width"] as? Int, $0["height"] as? Int] }
            #expect(metaSizes == [[320, 640], [640, 320], [320, 640]])
        }

        @Test("a sub-point resize that reports the same size does not resend metadata")
        func subPointResizeKeepsMetadata() {
            #expect(captureSnapshots(
                failures: [false, false, false],
                windowSizes: [CGSize(width: 320, height: 640), CGSize(width: 320.2, height: 640.3), CGSize(width: 640, height: 320)]
            ).map { $0.compactMap { $0["type"] as? Int } } == [[4, 2], [2], [4, 2]])
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

        @Test("a preceding sibling cannot clear an inherited no-capture mask", arguments: [true, false])
        func inheritedMaskSurvivesSiblingTraversal(zeroSizeFirstChild: Bool) throws {
            let sut = makeSut()
            defer { teardown(sut) }

            let parent = UIView(frame: CGRect(x: 0, y: 0, width: 320, height: 640))
            parent.accessibilityIdentifier = "ph-no-capture"
            let firstChild = UIView(frame: zeroSizeFirstChild ? .zero : CGRect(x: 0, y: 0, width: 20, height: 20))
            firstChild.clipsToBounds = false
            parent.addSubview(firstChild)
            let secret = CustomDrawnSecretView(frame: CGRect(x: 24, y: 120, width: 200, height: 32))
            parent.addSubview(secret)
            let window = makeWindow(containing: parent)

            let rects = try #require(sut.integration.collectMaskableRects(in: window))
            #expect(rects.contains(secret.frame))
        }

        @Test("a full-window no-capture leaf is masked itself")
        func fullWindowNoCaptureLeaf() throws {
            let sut = makeSut()
            defer { teardown(sut) }

            let secret = CustomDrawnSecretView(frame: CGRect(x: 0, y: 0, width: 320, height: 640))
            secret.accessibilityIdentifier = "ph-no-capture"
            let window = makeWindow(containing: secret)
            try #require(secret.toAbsoluteRect(window).equalTo(window.frame))

            #expect(sut.integration.collectMaskableRects(in: window) == [secret.frame])
        }

        @Test("inherited masking respects explicit no-mask and stays within the marked subtree")
        func inheritedMaskRespectsScopeAndNoMask() {
            let sut = makeSut()
            defer { teardown(sut) }

            let parent = UIView(frame: CGRect(x: 0, y: 0, width: 320, height: 640))
            parent.accessibilityIdentifier = "ph-no-capture"
            let unmaskedChild = CustomDrawnSecretView(frame: CGRect(x: 24, y: 80, width: 200, height: 32))
            unmaskedChild.accessibilityIdentifier = "ph-no-mask"
            parent.addSubview(unmaskedChild)
            let secret = CustomDrawnSecretView(frame: CGRect(x: 24, y: 120, width: 200, height: 32))
            parent.addSubview(secret)
            let window = makeWindow(containing: parent)
            window.addSubview(CustomDrawnSecretView(frame: CGRect(x: 24, y: 160, width: 200, height: 32)))

            #expect(sut.integration.collectMaskableRects(in: window) == [secret.frame])
        }

        @Test("a collapsed clipping parent is walked while its presentation bounds remain visible", arguments: [true, false])
        func collapsingClippingParentUsesRenderedBounds(presentationIsVisible: Bool) throws {
            let sut = makeSut()
            defer { teardown(sut) }

            let wrapper = CollapsingView(frame: .zero)
            wrapper.clipsToBounds = true
            let layer = try #require(wrapper.layer as? CollapsingLayer)
            layer.renderedBounds = presentationIsVisible ? CGRect(x: 0, y: 0, width: 320, height: 640) : .zero
            let label = makeSecretLabel(frame: CGRect(x: 24, y: 120, width: 200, height: 32))
            wrapper.addSubview(label)
            let window = makeWindow(containing: wrapper)

            #expect(wrapper.frame == .zero)
            #expect(sut.integration.collectMaskableRects(in: window) == (presentationIsVisible ? [label.frame] : []))
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

        // MARK: - Content drawn outside a masked view's bounds

        private func makePhoto(size: CGSize) -> UIImage {
            let format = UIGraphicsImageRendererFormat()
            format.scale = 1
            return UIGraphicsImageRenderer(size: size, format: format).image { context in
                UIColor.red.setFill()
                context.fill(CGRect(origin: .zero, size: size))
            }
        }

        private func isCovered(_ target: CGRect, by rects: [CGRect]?) -> Bool {
            rects?.contains { $0.contains(target) } == true
        }

        @Test("an unclipped aspect-fill image is masked where it overflows its view", arguments: [false, true])
        func unclippedAspectFillImage(clipsToBounds: Bool) {
            let sut = makeSut()
            defer { teardown(sut) }

            let imageView = UIImageView(frame: CGRect(x: 100, y: 120, width: 100, height: 100))
            imageView.contentMode = .scaleAspectFill
            imageView.clipsToBounds = clipsToBounds
            imageView.image = makePhoto(size: CGSize(width: 200, height: 100))
            let window = makeWindow(containing: imageView)

            // Filling 100x100 with a 2:1 image draws it 200x100, centred: 50pt past each side.
            let expected = clipsToBounds ? imageView.frame : CGRect(x: 50, y: 120, width: 200, height: 100)
            #expect(sut.integration.collectMaskableRects(in: window) == [expected])
        }

        @Test("an unclipped image drawn at its natural size is masked where it overflows its view")
        func unclippedTopLeftImage() {
            let sut = makeSut()
            defer { teardown(sut) }

            let imageView = UIImageView(frame: CGRect(x: 100, y: 120, width: 50, height: 50))
            imageView.contentMode = .topLeft
            imageView.clipsToBounds = false
            imageView.image = makePhoto(size: CGSize(width: 120, height: 80))
            let window = makeWindow(containing: imageView)

            #expect(sut.integration.collectMaskableRects(in: window) == [CGRect(x: 100, y: 120, width: 120, height: 80)])
        }

        private func attributedText(with attachment: NSTextAttachment) -> NSAttributedString {
            let text = NSMutableAttributedString(string: "Receipt ")
            text.append(NSAttributedString(attachment: attachment))
            return text
        }

        @Test("an image attachment in text is masked when only images are masked", arguments: ["label", "textView"])
        func imageAttachmentInText(kind: String) {
            let sut = makeSut(maskAllTextInputs: false, maskAllImages: true)
            defer { teardown(sut) }

            let text = attributedText(with: NSTextAttachment(image: makePhoto(size: CGSize(width: 24, height: 24))))
            let frame = CGRect(x: 24, y: 120, width: 200, height: 40)
            let view: UIView
            switch kind {
            case "label":
                let label = UILabel(frame: frame)
                label.attributedText = text
                view = label
            default:
                let textView = UITextView(frame: frame)
                textView.attributedText = text
                view = textView
            }
            let window = makeWindow(containing: view)

            #expect(isCovered(frame, by: sut.integration.collectMaskableRects(in: window)))
        }

        @Test("a symbol attachment in text stays visible when only images are masked")
        func symbolAttachmentInLabel() throws {
            let sut = makeSut(maskAllTextInputs: false, maskAllImages: true)
            defer { teardown(sut) }

            let label = UILabel(frame: CGRect(x: 24, y: 120, width: 200, height: 40))
            label.attributedText = try attributedText(with: NSTextAttachment(image: #require(UIImage(systemName: "star"))))
            let window = makeWindow(containing: label)

            #expect(sut.integration.collectMaskableRects(in: window) == [])
        }

        @Test("an unclipped label's layer shadow is masked with the label", arguments: [false, true])
        func labelLayerShadow(clipsToBounds: Bool) {
            let sut = makeSut()
            defer { teardown(sut) }

            let label = makeSecretLabel(frame: CGRect(x: 24, y: 120, width: 200, height: 32))
            label.clipsToBounds = clipsToBounds
            label.layer.shadowOpacity = 1
            label.layer.shadowOffset = CGSize(width: 0, height: 60)
            label.layer.shadowRadius = 0
            let window = makeWindow(containing: label)

            let rects = sut.integration.collectMaskableRects(in: window)
            if clipsToBounds {
                // A clipping layer clips its shadow too, so the mask stays on the label.
                #expect(rects == [label.frame])
            } else {
                #expect(isCovered(label.frame.union(label.frame.offsetBy(dx: 0, dy: 60)), by: rects))
            }
        }

        @Test("a masked button's title drawn outside the button is masked")
        func buttonTitleOutsideBounds() throws {
            let sut = makeSut()
            defer { teardown(sut) }

            let button = UIButton(type: .system)
            button.frame = CGRect(x: 24, y: 120, width: 100, height: 44)
            button.clipsToBounds = false
            button.setTitle("SSN 123-45-6789", for: .normal)
            button.contentHorizontalAlignment = .left
            button.titleEdgeInsets = UIEdgeInsets(top: 0, left: 200, bottom: 0, right: -200)
            let window = makeWindow(containing: button)
            button.layoutIfNeeded()

            let title = try #require(button.titleLabel)
            let titleRect = title.toAbsoluteRect(window)
            try #require(!button.frame.contains(titleRect), "the title must sit outside the button for this test")

            #expect(isCovered(titleRect, by: sut.integration.collectMaskableRects(in: window)))
        }
    }
#endif
