#if os(iOS) && canImport(Metal)
    import Foundation
    @testable import PostHog
    import QuartzCore
    import SwiftUI
    import Testing
    import UIKit

    @Suite("Replay GPU inline masking", .serialized)
    @MainActor
    struct PostHogGPUInlineMaskTest: GPUCaptureTesting {
        private func image(_ size: CGSize, _ draw: (CGContext) -> Void) throws -> UIImage {
            let image = PostHogGraphicsImageRenderer(size: size, scale: 1).image(actions: draw)
            return try #require(image)
        }

        private func secretLabel(_ frame: CGRect, text: String = "Secret value 42") -> UILabel {
            let label = UILabel(frame: frame)
            label.text = text
            label.textColor = .magenta
            label.font = .boldSystemFont(ofSize: 22)
            return label
        }

        // MARK: - Text

        @Test("A masked label is drawn as `*` in place, with no rect left for it")
        func labelIsStarred() async throws {
            let fixture = try await makeFixture()
            defer { fixture.close() }
            let label = secretLabel(CGRect(x: 10, y: 40, width: 180, height: 40))
            fixture.window.addSubview(label)

            fixture.config.maskAllTextInputs = false
            #expect(try await Pixels(capture(fixture).image).count(where: Self.isMagenta) > 50)
            fixture.config.maskAllTextInputs = true

            let result = try await captureStars(fixture)
            let pixels = try expectFullyMasked(result)
            #expect(result.inlineRegionCount == 1)
            #expect(pixels.count(in: label.frame, where: Self.isStar) > 30)
            #expect(pixels.count(in: CGRect(x: 0, y: 100, width: 200, height: 200), where: Self.isStar) == 0)
        }

        @Test("`*` is drawn in the label's own colour and font, inside its text rect")
        func starsUseLabelStyle() async throws {
            let fixture = try await makeFixture()
            defer { fixture.close() }
            let label = UILabel(frame: CGRect(x: 10, y: 40, width: 180, height: 60))
            label.text = "John Smith"
            label.textColor = .red
            label.font = .systemFont(ofSize: 30)
            label.textAlignment = .right
            fixture.window.addSubview(label)

            let pixels = try await Pixels(captureStars(fixture, color: nil).image)
            let isRed = { (pixel: RGBA) in pixel.red > 200 && pixel.green < 60 && pixel.blue < 60 }
            #expect(pixels.count(in: label.frame, where: isRed) > 40)
            // Right-aligned: the text's left end is empty.
            #expect(pixels.count(in: CGRect(x: 10, y: 40, width: 40, height: 60), where: isRed) == 0)
            #expect(pixels.count(in: CGRect(x: 0, y: 110, width: 200, height: 190), where: isRed) == 0)
        }

        @Test("A masked button keeps its chrome and draws its title as `*`")
        func buttonTitleIsStarred() async throws {
            let fixture = try await makeFixture()
            defer { fixture.close() }
            let button = UIButton(type: .system)
            button.frame = CGRect(x: 20, y: 40, width: 160, height: 50)
            button.setTitle("Pay Jane Doe", for: .normal)
            button.setTitleColor(.magenta, for: .normal)
            button.titleLabel?.font = .boldSystemFont(ofSize: 22)
            button.backgroundColor = .green
            fixture.window.addSubview(button)

            let pixels = try await expectFullyMasked(captureStars(fixture))
            #expect(pixels.count(in: button.frame, where: Self.isStar) > 20)
            #expect(pixels[25, 45] == .green)
        }

        @Test("A text field being edited drops its caret and selection and draws one `*` per character")
        func editingTextFieldIsStarred() async throws {
            let fixture = try await makeFixture()
            defer { fixture.close() }
            let field = UITextField(frame: CGRect(x: 10, y: 40, width: 180, height: 44))
            field.text = "my secret value"
            field.textColor = .magenta
            field.tintColor = .magenta
            field.font = .boldSystemFont(ofSize: 20)
            field.borderStyle = .roundedRect
            fixture.window.addSubview(field)
            fixture.window.makeKey()
            defer { field.resignFirstResponder() }
            field.becomeFirstResponder()
            try #require(field.isFirstResponder)
            field.selectedTextRange = field.textRange(from: field.beginningOfDocument, to: field.endOfDocument)

            let pixels = try await expectFullyMasked(captureStars(fixture))
            #expect(pixels.count(in: field.frame, where: Self.isStar) > 30)
        }

        @Test("A secure field draws one `*` per character, and an empty field its placeholder, masked")
        func secureAndPlaceholderFieldsAreStarred() async throws {
            let fixture = try await makeFixture()
            defer { fixture.close() }
            let secure = UITextField(frame: CGRect(x: 10, y: 40, width: 180, height: 44))
            secure.isSecureTextEntry = true
            secure.text = "hunter2"
            secure.textColor = .magenta
            secure.font = .boldSystemFont(ofSize: 24)
            let empty = UITextField(frame: CGRect(x: 10, y: 120, width: 180, height: 44))
            empty.attributedPlaceholder = NSAttributedString(string: "Your email", attributes: [.foregroundColor: UIColor.magenta,
                                                                                                .font: UIFont.boldSystemFont(ofSize: 24)])
            fixture.window.addSubview(secure)
            fixture.window.addSubview(empty)

            let result = try await captureStars(fixture)
            let pixels = try expectFullyMasked(result)
            #expect(result.inlineRegionCount == 2)
            #expect(pixels.count(in: secure.frame, where: Self.isStar) > 20)
            #expect(pixels.count(in: empty.frame, where: Self.isStar) > 20)
        }

        @Test("A scrolled text view draws its visible text as `*`, and nothing else of it")
        func scrolledTextViewIsStarred() async throws {
            let fixture = try await makeFixture()
            defer { fixture.close() }
            let textView = UITextView(frame: CGRect(x: 10, y: 40, width: 180, height: 140))
            textView.text = (1 ... 40).map { "Line \($0) private note" }.joined(separator: "\n")
            textView.textColor = .magenta
            textView.font = .boldSystemFont(ofSize: 17)
            fixture.window.addSubview(textView)
            textView.layoutIfNeeded()
            textView.contentOffset = CGPoint(x: 0, y: 240)

            let pixels = try await expectFullyMasked(captureStars(fixture))
            #expect(pixels.count(in: textView.frame, where: Self.isStar) > 200)
            #expect(pixels.count(in: CGRect(x: 0, y: 190, width: 200, height: 110), where: Self.isStar) == 0)
        }

        @Test("A text shadow, drawn into the label's own contents, doesn't survive")
        func labelShadowIsDropped() async throws {
            let fixture = try await makeFixture()
            defer { fixture.close() }
            let label = secretLabel(CGRect(x: 10, y: 40, width: 180, height: 40))
            label.textColor = .black
            label.shadowColor = .magenta
            label.shadowOffset = CGSize(width: 3, height: 3)
            let layerShadow = secretLabel(CGRect(x: 10, y: 120, width: 180, height: 40))
            layerShadow.textColor = .black
            layerShadow.layer.shadowColor = UIColor.magenta.cgColor
            layerShadow.layer.shadowOpacity = 1
            layerShadow.layer.shadowRadius = 0
            layerShadow.layer.shadowOffset = CGSize(width: 4, height: 4)
            fixture.window.addSubview(label)
            fixture.window.addSubview(layerShadow)

            try await expectFullyMasked(captureStars(fixture))
        }

        // MARK: - Images

        @Test("A masked image is blurred to colour blobs on the GPU: no detail at the checkerboard's scale")
        func imageIsBlurred() async throws {
            let fixture = try await makeFixture()
            defer { fixture.close() }
            #expect(fixture.mirror.inlineMask.imageBlur == .verified)
            let checker = try UIImageView(image: checkerboard(CGSize(width: 160, height: 100)))
            checker.frame = CGRect(x: 20, y: 20, width: 160, height: 100)
            let text = try UIImageView(image: image(CGSize(width: 160, height: 100)) { context in
                UIColor.white.setFill()
                context.fill(CGRect(x: 0, y: 0, width: 160, height: 100))
                ("SSN 078-05-1120" as NSString).draw(at: CGPoint(x: 4, y: 36), withAttributes: [.font: UIFont.boldSystemFont(ofSize: 20)])
            })
            text.frame = CGRect(x: 20, y: 160, width: 160, height: 100)
            fixture.window.addSubview(checker)
            fixture.window.addSubview(text)

            let pixels = try await expectFullyMasked(capture(fixture))
            #expect(pixels.maxNeighbourStep(in: checker.frame.insetBy(dx: 2, dy: 2)) <= 12)
            #expect(pixels.maxNeighbourStep(in: text.frame.insetBy(dx: 2, dy: 2)) <= 12)
            // Blurred, not blacked out: the checkerboard averages to a dark magenta.
            let middle = pixels[100, 70]
            #expect(middle.red > 60 && middle.green < 40 && middle.blue > 60, "\(middle)")
            // Clipped to its bounds.
            #expect(pixels[100, 140] == .white)
        }

        @Test("When the blur self-check fails, masked images are filled black")
        func failedBlurCheckFillsImagesBlack() async throws {
            let fixture = try await makeFixture()
            defer { fixture.close() }
            fixture.mirror.inlineMask.recordImageBlurCheck(passed: false)
            // A failure sticks, even if a later check passes.
            fixture.mirror.inlineMask.recordImageBlurCheck(passed: true)
            #expect(fixture.mirror.inlineMask.imageBlur == .failed)
            let checker = try UIImageView(image: checkerboard(CGSize(width: 160, height: 100)))
            checker.frame = CGRect(x: 20, y: 20, width: 160, height: 100)
            fixture.window.addSubview(checker)

            let pixels = try await expectFullyMasked(capture(fixture))
            #expect(pixels.count(in: checker.frame, where: Self.isBlack) == 160 * 100)
        }

        @Test("The blur self-check passes the gaussian blur and fails a render that keeps the detail")
        func blurSelfCheck() async throws {
            let mirror = try makeMirror()
            let results = await Task.detached {
                (mirror.checkImageBlur(), mirror.checkImageBlur { _ in true })
            }.value
            #expect(results.0)
            #expect(!results.1)
        }

        @Test("An image that spills past its bounds is clipped to them: the rect pass would miss the spill")
        func imageOverflowIsClipped() async throws {
            let fixture = try await makeFixture()
            defer { fixture.close() }
            let spilling = try UIImageView(image: checkerboard(CGSize(width: 140, height: 140)))
            spilling.contentMode = .center
            spilling.frame = CGRect(x: 70, y: 100, width: 60, height: 60)
            let container = noCaptureView(CGRect(x: 70, y: 200, width: 40, height: 40), color: .clear)
            container.layer.contents = try magentaContents(CGSize(width: 120, height: 120))
            container.layer.contentsGravity = .center
            fixture.window.addSubview(spilling)
            fixture.window.addSubview(container)

            let pixels = try await expectFullyMasked(capture(fixture))
            #expect(pixels.count(in: CGRect(x: 10, y: 100, width: 50, height: 60), where: { $0.red < 200 }) == 0)
        }

        // MARK: - Containers and effects

        @Test("A ph-no-capture container keeps its chrome and masks everything drawn inside it")
        func noCaptureContainerKeepsChrome() async throws {
            let fixture = try await makeFixture()
            defer { fixture.close() }
            let container = noCaptureView(CGRect(x: 10, y: 20, width: 180, height: 260), color: .green)
            container.layer.cornerRadius = 12
            let label = secretLabel(CGRect(x: 10, y: 10, width: 160, height: 40))
            let image = try UIImageView(image: checkerboard(CGSize(width: 80, height: 60)))
            image.frame = CGRect(x: 10, y: 60, width: 80, height: 60)
            let nested = noCaptureView(CGRect(x: 10, y: 140, width: 80, height: 60), color: .clear)
            nested.layer.contents = try magentaContents(CGSize(width: 80, height: 60))
            let deeper = UIView(frame: CGRect(x: 100, y: 140, width: 60, height: 60))
            let drawn = CALayer()
            drawn.frame = deeper.bounds
            drawn.contents = try magentaContents(CGSize(width: 60, height: 60))
            deeper.layer.addSublayer(drawn)
            for view in [label, image, nested, deeper] {
                container.addSubview(view)
            }
            fixture.window.addSubview(container)

            let pixels = try await expectFullyMasked(captureStars(fixture))
            #expect(pixels[100, 270] == .green)
            #expect(pixels.count(in: label.convert(label.bounds, to: fixture.window), where: Self.isStar) > 20)
            #expect(pixels.count(in: CGRect(x: 21, y: 161, width: 78, height: 58), where: Self.isBlack) == 78 * 58)
            #expect(pixels.count(in: CGRect(x: 111, y: 161, width: 58, height: 58), where: Self.isBlack) == 58 * 58)
        }

        @Test("Background colours are chrome: kept on a ph-no-capture view and everything under it, while drawn content is masked")
        func backgroundColorsAreKeptAsChrome() async throws {
            let fixture = try await makeFixture()
            defer { fixture.close() }
            let container = noCaptureView(CGRect(x: 10, y: 20, width: 180, height: 200), color: .green)
            let child = UIView(frame: CGRect(x: 10, y: 10, width: 80, height: 60))
            child.backgroundColor = .orange
            let drawn = UIView(frame: CGRect(x: 10, y: 100, width: 80, height: 60))
            drawn.backgroundColor = .orange
            drawn.layer.contents = try magentaContents(drawn.bounds.size)
            container.addSubview(child)
            container.addSubview(drawn)
            fixture.window.addSubview(container)

            let pixels = try await expectFullyMasked(capture(fixture))
            let isOrange = { (pixel: RGBA) in pixel.red > 240 && (110 ... 150).contains(pixel.green) && pixel.blue < 20 }
            #expect(pixels[150, 200] == .green)
            #expect(pixels.count(in: CGRect(x: 21, y: 31, width: 78, height: 58), where: isOrange) == 78 * 58)
            // A view with drawn content is filled black over its background.
            #expect(pixels.count(in: CGRect(x: 21, y: 121, width: 78, height: 58), where: Self.isBlack) == 78 * 58)
        }

        @Test("A blur over masked text samples the masked copy, not the text")
        func visualEffectOverMaskedText() async throws {
            let fixture = try await makeFixture()
            defer { fixture.close() }
            let label = secretLabel(CGRect(x: 10, y: 40, width: 180, height: 80), text: "████")
            label.font = .systemFont(ofSize: 60)
            let blur = UIVisualEffectView(effect: UIBlurEffect(style: .light))
            blur.frame = CGRect(x: 0, y: 20, width: 200, height: 120)
            fixture.window.addSubview(label)
            fixture.window.addSubview(blur)

            let pixels = try await expectFullyMasked(captureStars(fixture))
            #expect(pixels.count(where: { $0.red > 150 && $0.green < 120 && $0.blue > 150 }) == 0)
        }

        @Test("Masks the walk doesn't make are unchanged: ph-no-mask stays visible, postHogMask reporters stay rects")
        func noMaskAndReportersAreUnchanged() async throws {
            let fixture = try await makeFixture()
            defer { fixture.close() }
            let visible = secretLabel(CGRect(x: 10, y: 20, width: 180, height: 40))
            visible.accessibilityIdentifier = "ph-no-mask"
            let reporter = PostHogMaskReporterUIView(frame: CGRect(x: 20, y: 200, width: 100, height: 60))
            fixture.window.addSubview(visible)
            fixture.window.addSubview(reporter)
            defer { reporter.removeFromSuperview() }
            fixture.window.layoutIfNeeded()

            let result = try await capture(fixture)
            #expect(result.inlineRegionCount == 0)
            #expect(result.rectRegions == [reporter.frame])
            #expect(try Pixels(result.image).count(in: visible.frame, where: Self.isMagenta) > 50)
        }

        // MARK: - Portals

        private func makePortal(showing source: CALayer, frame: CGRect, matchesPosition: Bool = true, matchesTransform: Bool = true) throws -> CALayer {
            let portalClass = try #require(NSClassFromString("CAPortalLayer") as? CALayer.Type)
            let portal = portalClass.init()
            portal.frame = frame
            portal.masksToBounds = true
            portal.setValue(source, forKey: "sourceLayer")
            portal.setValue(true, forKey: "hidesSourceLayer")
            portal.setValue(matchesPosition, forKey: "matchesPosition")
            portal.setValue(matchesTransform, forKey: "matchesTransform")
            portal.setValue(0, forKey: "sourceContextId")
            return portal
        }

        @Test("Text a matched portal draws where it sits, clipped away there, is masked in the portal's copy")
        func matchedPortalTextIsStarred() async throws {
            let fixture = try await makeFixture()
            defer { fixture.close() }
            let clipper = UIView(frame: CGRect(x: 10, y: 200, width: 40, height: 40))
            clipper.clipsToBounds = true
            let label = secretLabel(CGRect(x: 10, y: -150, width: 160, height: 40))
            clipper.addSubview(label)
            fixture.window.addSubview(clipper)
            let labelRect = label.convert(label.bounds, to: fixture.window)
            fixture.window.layer.addSublayer(try makePortal(showing: label.layer, frame: labelRect))

            let pixels = try await expectFullyMasked(captureStars(fixture))
            #expect(pixels.count(in: labelRect, where: Self.isStar) > 30)
        }

        @Test("Text a lens portal draws at its own position is masked there, with no rect for the portal")
        func lensPortalTextIsStarred() async throws {
            let fixture = try await makeFixture()
            defer { fixture.close() }
            let source = UIView(frame: CGRect(x: 10, y: 20, width: 180, height: 60))
            source.addSubview(secretLabel(CGRect(x: 5, y: 10, width: 170, height: 40)))
            fixture.window.addSubview(source)
            let portalRect = CGRect(x: 10, y: 180, width: 180, height: 60)
            fixture.window.layer.addSublayer(try makePortal(showing: source.layer, frame: portalRect, matchesPosition: false, matchesTransform: false))

            let pixels = try await expectFullyMasked(captureStars(fixture))
            #expect(pixels.count(in: portalRect, where: Self.isStar) > 30)
        }

        @Test("A portal showing an unmasked view from inside a masked container is masked with the container")
        func portalOfDescendantIsMaskedWithItsAncestor() async throws {
            let fixture = try await makeFixture()
            defer { fixture.close() }
            let container = noCaptureView(CGRect(x: 10, y: 20, width: 180, height: 80), color: .clear)
            // Unmasked itself, so it's no region of its own: only the container's mask covers it.
            let source = UIView(frame: CGRect(x: 10, y: 10, width: 160, height: 60))
            source.accessibilityIdentifier = "ph-no-mask"
            let drawn = CALayer()
            drawn.frame = source.bounds
            drawn.contents = try magentaContents(source.bounds.size)
            source.layer.addSublayer(drawn)
            container.addSubview(source)
            fixture.window.addSubview(container)
            let portalRect = CGRect(x: 20, y: 180, width: 160, height: 60)
            fixture.window.layer.addSublayer(try makePortal(showing: source.layer, frame: portalRect, matchesPosition: false, matchesTransform: false))

            let pixels = try await expectFullyMasked(capture(fixture))
            #expect(pixels.count(in: portalRect, where: Self.isBlack) == 160 * 60)
        }

        // MARK: - iOS 26 SwiftUI layers

        @available(iOS 26.0, *)
        @Test("iOS 26 SwiftUI text and image layers are masked as `*` rows and a blur")
        func swiftUILayersAreMasked() async throws {
            let fixture = try await makeFixture()
            defer { fixture.close() }
            let magenta = Color(red: 1, green: 0, blue: 1)
            let checker = try checkerboard(CGSize(width: 120, height: 80))
            let host = UIHostingController(rootView: VStack(spacing: 30) {
                Text("Secret value").font(.system(size: 28, weight: .bold)).foregroundStyle(magenta)
                Image(uiImage: checker)
            })
            host.view.frame = fixture.window.bounds
            fixture.window.addSubview(host.view)

            fixture.config.maskAllTextInputs = false
            fixture.config.maskAllImages = false
            let control = try await Pixels(capture(fixture).image)
            try #require(control.count(where: Self.isMagenta) > 200, "SwiftUI didn't render in this hostless window")
            fixture.config.maskAllTextInputs = true
            fixture.config.maskAllImages = true

            let result = try await captureStars(fixture)
            let pixels = try expectFullyMasked(result)
            #expect(result.inlineRegionCount >= 2)
            #expect(pixels.count(where: Self.isStar) > 30)
        }

        @Test("Every class the mask walk masks as text, an image, a web view or a sandboxed view has a masking kind of its own")
        func walkedClassesHaveMaskingKinds() async throws {
            let fixture = try await makeFixture()
            defer { fixture.close() }
            let classes = fixture.integration.maskedClassesForTesting
            #expect(classes.count >= 10)
            for (view, layer) in classes {
                let tag = fixture.integration.inlineMaskTag(view: view, layer: layer)
                #expect(tag != .container, "\(view.map(NSStringFromClass) ?? "no view") / \(NSStringFromClass(layer))")
            }
        }

        // MARK: - Drawing off main, the budget and the default path

        @Test("Uncached text shows as bars, is drawn off the main thread, and shows as `*` from a later capture on")
        func textIsDrawnOffMainForLaterCaptures() async throws {
            let fixture = try await makeFixture()
            defer { fixture.close() }
            let label = secretLabel(CGRect(x: 10, y: 40, width: 180, height: 40))
            fixture.window.addSubview(label)
            let mask = fixture.mirror.inlineMask
            PostHogInlineMask.textColorForTesting = .blue
            defer { PostHogInlineMask.textColorForTesting = nil }

            let bars = try expectFullyMasked(await capture(fixture))
            #expect(mask.textBarsForTesting == 1)
            #expect(mask.textCacheHitsForTesting == 0)
            // One solid bar across the label: far more coloured pixels than its `*` have.
            #expect(bars.count(in: label.frame, where: Self.isStar) > 1500)

            mask.waitForTextDrawsForTesting()
            #expect(mask.textDrawsForTesting == 1)
            #expect(mask.textDrawsOnMainForTesting == 0)

            let stars = try expectFullyMasked(await capture(fixture))
            #expect(mask.textBarsForTesting == 1)
            #expect(mask.textCacheHitsForTesting == 1)
            #expect((30 ..< 1500).contains(stars.count(in: label.frame, where: Self.isStar)))

            _ = try await capture(fixture)
            mask.waitForTextDrawsForTesting()
            #expect(mask.textDrawsForTesting == 1)
            #expect(mask.textCacheHitsForTesting == 2)
        }

        @Test("Text read past the main-thread budget keeps its bars and is read by a later capture")
        func overBudgetTextWaitsForALaterCapture() async throws {
            let fixture = try await makeFixture()
            defer { fixture.close() }
            fixture.window.addSubview(secretLabel(CGRect(x: 10, y: 40, width: 180, height: 40)))
            let mask = fixture.mirror.inlineMask
            mask.textBudget = 0
            PostHogInlineMask.textColorForTesting = .blue
            defer { PostHogInlineMask.textColorForTesting = nil }

            for _ in 0 ..< 2 {
                try expectFullyMasked(await capture(fixture))
                mask.waitForTextDrawsForTesting()
            }
            #expect(mask.textBarsForTesting == 2)
            #expect(mask.textDrawsForTesting == 0)

            mask.textBudget = 0.001
            try await expectFullyMasked(captureStars(fixture))
            #expect(mask.textDrawsForTesting == 1)
        }

        @Test("With GPU capture off, the default path collects the same rects and never builds a mirror or copy map")
        func defaultPathIsUnchanged() async throws {
            let mirror = try makeMirror()
            let (sut, integration, _) = try makeScreenshotReplaySut { $0.screenshotModeGPUCapture = false }
            integration.gpuMirror = mirror
            defer { sut.close() }
            let window = makeWindow()
            window.addSubview(secretLabel(CGRect(x: 10, y: 40, width: 180, height: 40)))
            window.addSubview(noCaptureView(CGRect(x: 10, y: 100, width: 100, height: 60)))
            window.layoutIfNeeded()

            #expect(integration.startScreenshotCapture(window: window, screenName: nil, postHog: sut))
            await waitUntil(timeout: 5) { !integration.isScreenshotRenderInFlightForTesting }
            #expect(mirror.copiesMadeForTesting == 0)
            #expect(!mirror.hasAttachedFrameForTesting)

            let result = try #require(integration.defaultPathCaptureForTesting(window: window))
            #expect(result.inlineRegionCount == 0)
            #expect(result.rectRegions == integration.collectMaskableRects(in: window))
            #expect(result.rectRegions.count == 2)
            #expect(mirror.copiesMadeForTesting == 0)
        }

        @Test("The upload's rect pass and encode give the same bytes as before they were shared with the capture hooks")
        func uploadEncodeIsUnchanged() throws {
            let screenshot = try image(CGSize(width: 200, height: 300)) { context in
                UIColor.magenta.setFill()
                context.fill(CGRect(x: 0, y: 0, width: 200, height: 300))
                UIColor.blue.setFill()
                context.fill(CGRect(x: 40, y: 40, width: 80, height: 120))
            }
            let rects = [CGRect(x: 10, y: 10, width: 60, height: 40), CGRect(x: 50, y: 200, width: 100, height: 50)]
            for (maskable, type, pixelScale) in [(rects, nil, 1), ([], nil, 1), (rects, "screenshot", 0.5), ([], "screenshot", 0.5)] as [([CGRect], String?, CGFloat)] {
                let wireframe = RRWireframe()
                wireframe.type = type
                wireframe.image = screenshot
                wireframe.maskableWidgets = maskable
                wireframe.screenshotPixelScale = pixelScale
                let unmasked = type == "screenshot" ? RRWireframe.unmaskedScreenshot(screenshot, pixelScale: pixelScale) : screenshot
                let expected = maskable.isEmpty ? unmasked.toBase64()
                    : RRWireframe.maskImage(screenshot, maskableWidgets: maskable, pixelScale: pixelScale)?.toBase64()
                let shared = wireframe.encodeImage()?.base64
                #expect(wireframe.toDict()["base64"] as? String == expected)
                #expect(shared == expected)
                #expect(!wireframe.maskRenderFailed)
            }
        }

        // MARK: - Cost

        @Test("Turn-1 cost on a text-heavy screen, with and without inline masking (prints, doesn't assert)")
        func turnOneCost() async throws {
            let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 402, height: 874))
            window.backgroundColor = .white
            window.isHidden = false
            let fixture = try await makeFixture(window: window)
            defer { fixture.close() }
            for row in 0 ..< 40 {
                let label = UILabel(frame: CGRect(x: 16, y: 60 + CGFloat(row) * 16, width: 370, height: 16))
                label.text = "Row \(row): Jane Doe paid $\(row * 7).50 for order #\(1000 + row)"
                label.font = .systemFont(ofSize: 13)
                window.addSubview(label)
            }
            let field = UITextField(frame: CGRect(x: 16, y: 720, width: 370, height: 36))
            field.text = "jane.doe@example.com"
            field.borderStyle = .roundedRect
            let textView = UITextView(frame: CGRect(x: 16, y: 760, width: 370, height: 100))
            textView.text = (1 ... 12).map { "Note line \($0) about the account" }.joined(separator: "\n")
            window.addSubview(field)
            window.addSubview(textView)

            let mask = fixture.mirror.inlineMask
            func median(_ values: [Double]) -> Double {
                values.sorted()[values.count / 2]
            }
            var off: [Double] = [], cold: [Double] = [], warm: [Double] = []
            for _ in 0 ..< 9 {
                mask.isEnabledForTesting = false
                off.append(try await capture(fixture).turn1Milliseconds)
                mask.isEnabledForTesting = true
                mask.clearCacheForTesting()
                cold.append(try await capture(fixture).turn1Milliseconds)
                // Texts past the budget are read by the captures that follow.
                for _ in 0 ..< 4 {
                    mask.waitForTextDrawsForTesting()
                    _ = try await capture(fixture)
                }
                mask.waitForTextDrawsForTesting()
                warm.append(try await capture(fixture).turn1Milliseconds)
            }
            print("INLINE-COST turn1 ms median: walk+freeze \(median(off)), walk+inline+freeze cold \(median(cold)), warm \(median(warm))")
            print("INLINE-COST turn1 ms min: walk+freeze \(off.min() ?? 0), walk+inline+freeze cold \(cold.min() ?? 0), warm \(warm.min() ?? 0)")
        }
    }
#endif
