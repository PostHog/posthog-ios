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

        @Test("Ruby annotations, which draw their own text, are dropped from masked text")
        func rubyAnnotationsAreDropped() {
            let ruby = NSAttributedString.Key(kCTRubyAnnotationAttributeName as String)
            let annotation = CTRubyAnnotationCreateWithAttributes(.auto, .auto, .before, "ひみつ" as CFString, [:] as CFDictionary)
            let text = NSMutableAttributedString(string: "秘密 code")
            text.addAttribute(ruby, value: annotation, range: NSRange(location: 0, length: 2))
            text.addAttribute(.foregroundColor, value: UIColor.red, range: NSRange(location: 0, length: 2))

            let masked = PostHogInlineMask.masked(text, keepingWhitespace: true, lineBreakMode: .byWordWrapping)
            #expect(masked.string == "** ****")
            var rubyRuns = 0
            masked.enumerateAttribute(ruby, in: NSRange(location: 0, length: masked.length)) { value, _, _ in
                if value != nil { rubyRuns += 1 }
            }
            #expect(rubyRuns == 0)
            #expect(masked.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? UIColor == .red)
        }

        // MARK: - Images

        @Test("A masked image is filled black over its bounds")
        func imageIsBlack() async throws {
            let fixture = try await makeFixture()
            defer { fixture.close() }
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
            #expect(pixels.count(in: checker.frame, where: Self.isBlack) == 160 * 100)
            #expect(pixels.count(in: text.frame, where: Self.isBlack) == 160 * 100)
            #expect(pixels[100, 140] == .white)
        }

        /// A photo-like image: a red-to-blue gradient with white text over it.
        private func photo(_ size: CGSize) throws -> UIImage {
            try image(size) { context in
                let colors = [UIColor.red.cgColor, UIColor.blue.cgColor] as CFArray
                if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: nil) {
                    context.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: size.width, y: 0), options: [])
                }
                ("ID 4242 Jane Doe" as NSString).draw(at: CGPoint(x: 6, y: size.height / 2 - 12),
                                                      withAttributes: [.font: UIFont.boldSystemFont(ofSize: 18), .foregroundColor: UIColor.white])
            }
        }

        @Test("A masked photo is filled black, keeping none of its colours")
        func photoIsBlack() async throws {
            let fixture = try await makeFixture()
            defer { fixture.close() }
            let view = try UIImageView(image: photo(CGSize(width: 160, height: 100)))
            view.frame = CGRect(x: 20, y: 40, width: 160, height: 100)
            fixture.window.addSubview(view)

            fixture.config.maskAllImages = false
            let control = try await Pixels(capture(fixture).image)
            fixture.config.maskAllImages = true
            try #require(control.maxNeighbourStep(in: view.frame.insetBy(dx: 2, dy: 2)) > 100, "the photo didn't render sharp")

            let pixels = try await expectFullyMasked(capture(fixture))
            #expect(pixels.count(in: view.frame, where: Self.isBlack) == 160 * 100)
            // Nothing outside it changes.
            #expect(pixels[100, 150] == .white)
        }

        @Test("Masked images off a fractional origin at 3x, and rotated, are black over every pixel they reach")
        func fractionalAndRotatedImagesKeepNoDetail() async throws {
            let fixture = try await makeFixture()
            defer { fixture.close() }
            let fractional = try UIImageView(image: checkerboard(CGSize(width: 100, height: 60)))
            fractional.frame = CGRect(x: 20.33, y: 30.67, width: 100, height: 60)
            let rotated = try UIImageView(image: checkerboard(CGSize(width: 100, height: 60)))
            rotated.frame = CGRect(x: 40, y: 170, width: 100, height: 60)
            rotated.transform = CGAffineTransform(rotationAngle: 0.3)
            fixture.window.addSubview(fractional)
            fixture.window.addSubview(rotated)

            let pixels = try await expectFullyMasked(capture(fixture, scale: 3))
            let scaled = { (rect: CGRect) in rect.applying(CGAffineTransform(scaleX: 3, y: 3)) }
            let inner = scaled(fractional.frame).insetBy(dx: 2, dy: 2).integral
            #expect(pixels.count(in: inner, where: Self.isBlack) == Int(inner.width * inner.height))
            let rotatedInner = scaled(CGRect(x: rotated.center.x - 25, y: rotated.center.y - 12, width: 50, height: 24))
            #expect(pixels.count(in: rotatedInner, where: Self.isBlack) == Int(rotatedInner.width * rotatedInner.height))
            #expect(pixels.count(where: Self.isMagentaHue) == 0)
        }

        @Test("A masked image through a portal or under a 3D transform is black")
        func unplaceableImagesAreBlack() async throws {
            let fixture = try await makeFixture()
            defer { fixture.close() }
            let source = UIView(frame: CGRect(x: 10, y: 20, width: 100, height: 60))
            let image = try UIImageView(image: checkerboard(CGSize(width: 100, height: 60)))
            image.frame = source.bounds
            source.addSubview(image)
            fixture.window.addSubview(source)
            let portalRect = CGRect(x: 10, y: 110, width: 100, height: 60)
            fixture.window.layer.addSublayer(try makePortal(showing: source.layer, frame: portalRect, matchesPosition: false, matchesTransform: false))
            let tilted = try UIImageView(image: checkerboard(CGSize(width: 100, height: 60)))
            tilted.frame = CGRect(x: 50, y: 200, width: 100, height: 60)
            var perspective = CATransform3DIdentity
            perspective.m34 = -1 / 300
            tilted.layer.transform = CATransform3DRotate(perspective, 0.5, 0, 1, 0)
            fixture.window.addSubview(tilted)

            let pixels = try await expectFullyMasked(capture(fixture))
            #expect(pixels.count(where: Self.isMagentaHue) == 0)
            #expect(pixels.count(in: portalRect.insetBy(dx: 2, dy: 2), where: Self.isBlack) == 96 * 56)
            #expect(pixels.count(in: CGRect(x: 90, y: 215, width: 20, height: 30), where: Self.isBlack) == 20 * 30)
        }

        @Test("A masked image's shadow, shaped by its contents, doesn't survive outside its bounds")
        func imageShadowIsDropped() async throws {
            let fixture = try await makeFixture()
            defer { fixture.close() }
            let cutout = try image(CGSize(width: 100, height: 60)) { context in
                context.clear(CGRect(x: 0, y: 0, width: 100, height: 60))
                UIColor.black.setFill()
                for x in stride(from: 0, to: 100, by: 20) {
                    context.fill(CGRect(x: x, y: 0, width: 10, height: 60))
                }
            }
            let view = UIImageView(image: cutout)
            view.frame = CGRect(x: 20, y: 40, width: 100, height: 60)
            view.layer.shadowColor = UIColor.magenta.cgColor
            view.layer.shadowOpacity = 1
            view.layer.shadowRadius = 0
            view.layer.shadowOffset = CGSize(width: 0, height: 80)
            fixture.window.addSubview(view)

            try await expectFullyMasked(capture(fixture))
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

        @Test("A ph-no-capture view is a black block over its bounds: no chrome, nothing inside it drawn")
        func noCaptureViewIsBlackWhole() async throws {
            let fixture = try await makeFixture()
            defer { fixture.close() }
            let container = noCaptureView(CGRect(x: 10, y: 20, width: 180, height: 260), color: .green)
            container.layer.cornerRadius = 12
            container.layer.borderWidth = 4
            container.layer.borderColor = UIColor.orange.cgColor
            container.alpha = 0.8
            let label = secretLabel(CGRect(x: 10, y: 10, width: 160, height: 40))
            let image = try UIImageView(image: checkerboard(CGSize(width: 80, height: 60)))
            image.frame = CGRect(x: 10, y: 60, width: 80, height: 60)
            let child = UIView(frame: CGRect(x: 100, y: 140, width: 60, height: 60))
            child.backgroundColor = .blue
            for view in [label, image, child] {
                container.addSubview(view)
            }
            fixture.window.addSubview(container)

            let pixels = try await expectFullyMasked(captureStars(fixture))
            #expect(pixels.count(in: container.frame, where: Self.isBlack) == 180 * 260)
            #expect(pixels[11, 21] == RGBA(red: 0, green: 0, blue: 0, alpha: 255))
            #expect(pixels[100, 290] == .white)
        }

        @Test("An auto-masked view keeps its chrome; the same view under ph-no-capture doesn't")
        func autoMaskedViewKeepsChrome() async throws {
            let fixture = try await makeFixture()
            defer { fixture.close() }
            func framedImage(_ frame: CGRect) throws -> UIImageView {
                let view = try UIImageView(image: checkerboard(frame.size))
                view.frame = frame
                view.layer.borderWidth = 6
                view.layer.borderColor = UIColor.orange.cgColor
                return view
            }
            let auto = try framedImage(CGRect(x: 20, y: 20, width: 160, height: 100))
            let tagged = try framedImage(CGRect(x: 20, y: 160, width: 160, height: 100))
            tagged.accessibilityIdentifier = "ph-no-capture"
            fixture.window.addSubview(auto)
            fixture.window.addSubview(tagged)

            let pixels = try await expectFullyMasked(capture(fixture))
            let isOrange = { (pixel: RGBA) in pixel.red > 240 && (110 ... 150).contains(pixel.green) && pixel.blue < 20 }
            #expect(pixels.count(in: auto.frame, where: isOrange) > 1000)
            #expect(pixels.count(in: auto.frame.insetBy(dx: 6, dy: 6), where: Self.isBlack) == 148 * 88)
            #expect(pixels.count(in: tagged.frame, where: Self.isBlack) == 160 * 100)
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

        @Test("ph-no-mask stays visible, and a postHogMask reporter's extent is masked in the mirror instead of as a rect")
        func noMaskStaysVisibleAndReportersMaskInline() async throws {
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
            #expect(result.inlineRegionCount == 1)
            #expect(result.rectRegions.isEmpty)
            let pixels = try Pixels(result.image)
            #expect(pixels.count(in: visible.frame, where: Self.isMagenta) > 50)
            // The window's white background under the extent.
            #expect(pixels.count(in: reporter.frame, where: Self.isBlack) == 100 * 60)
        }

        @Test("A shape drawn past its zero-size bounds under a postHogMask extent is masked, with no rect for the reporter")
        func shapePastBoundsUnderExtentIsMasked() async throws {
            let fixture = try await makeFixture()
            defer { fixture.close() }
            // Its bounds sit outside the extent; its path draws inside it.
            let shape = CAShapeLayer()
            shape.frame = CGRect(x: 5, y: 5, width: 0, height: 0)
            shape.path = UIBezierPath(rect: CGRect(x: 35, y: 55, width: 100, height: 50)).cgPath
            shape.fillColor = UIColor.magenta.cgColor
            shape.strokeColor = UIColor.magenta.cgColor
            shape.lineWidth = 6
            fixture.window.layer.addSublayer(shape)
            #expect(try await Pixels(capture(fixture).image).count(where: Self.isMagenta) > 4000)

            let reporter = PostHogMaskReporterUIView(frame: CGRect(x: 20, y: 40, width: 150, height: 100))
            fixture.window.addSubview(reporter)
            defer { reporter.removeFromSuperview() }
            fixture.window.layoutIfNeeded()

            try await expectFullyMasked(capture(fixture))
            #expect(fixture.mask.extentStatsForTesting.count == 1)
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

        @Test("An image under a postHogMask overlay is black, and so is the copy a portal shows elsewhere")
        func portalOfImageUnderExtentIsBlack() async throws {
            let fixture = try await makeFixture()
            defer { fixture.close() }
            let source = try UIImageView(image: checkerboard(CGSize(width: 180, height: 60)))
            source.frame = CGRect(x: 10, y: 20, width: 180, height: 60)
            // ph-no-mask so only the overlay masks it.
            source.accessibilityIdentifier = "ph-no-mask"
            let reporter = PostHogMaskReporterUIView(frame: source.frame)
            fixture.window.addSubview(source)
            fixture.window.addSubview(reporter)
            let portalRect = CGRect(x: 10, y: 180, width: 180, height: 60)
            fixture.window.layer.addSublayer(try makePortal(showing: source.layer, frame: portalRect, matchesPosition: false, matchesTransform: false))
            fixture.window.layoutIfNeeded()

            let result = try await capture(fixture)
            let pixels = try Pixels(result.image)
            #expect(result.rectRegions.isEmpty)
            #expect(pixels.count(where: Self.isMagentaHue) == 0)
            #expect(pixels.count(in: portalRect.insetBy(dx: 2, dy: 2)) { !Self.isBlack($0) } == 0)
        }

        @Test("A postHogMask overlay beside a portal's source, not inside it, masks the copy the portal shows elsewhere",
              arguments: [true, false])
        func siblingReporterMasksPortalShownElsewhere(extentInline: Bool) async throws {
            let fixture = try await makeFixture()
            defer { fixture.close() }
            fixture.mask.isExtentEnabledForTesting = extentInline
            let source = UIView(frame: CGRect(x: 10, y: 20, width: 180, height: 60))
            source.layer.contents = try magentaContents(source.bounds.size)
            // ph-no-mask so only the overlay masks it.
            source.accessibilityIdentifier = "ph-no-mask"
            let reporter = PostHogMaskReporterUIView(frame: source.frame)
            fixture.window.addSubview(source)
            fixture.window.addSubview(reporter)
            let portalRect = CGRect(x: 10, y: 180, width: 180, height: 60)
            fixture.window.layer.addSublayer(try makePortal(showing: source.layer, frame: portalRect, matchesPosition: false, matchesTransform: false))
            fixture.window.layoutIfNeeded()

            let result = try await capture(fixture)
            let pixels = try Pixels(result.image)
            #expect(pixels.count(where: Self.isMagenta) == 0, "\(pixels.count(in: portalRect, where: Self.isMagenta)) in the portal")
            if extentInline {
                // Masked in the portal's own copy, with no whole-portal rect.
                #expect(result.rectRegions.isEmpty)
            } else {
                #expect(result.rectRegions.contains(portalRect))
            }
        }

        @Test("A postHogMask overlay inside a portal's source masks the copy the portal shows elsewhere")
        func reporterInsideSourceMasksPortalShownElsewhere() async throws {
            let fixture = try await makeFixture()
            defer { fixture.close() }
            let source = UIView(frame: CGRect(x: 10, y: 20, width: 180, height: 60))
            source.layer.contents = try magentaContents(source.bounds.size)
            source.accessibilityIdentifier = "ph-no-mask"
            let reporter = PostHogMaskReporterUIView(frame: source.bounds)
            source.addSubview(reporter)
            fixture.window.addSubview(source)
            let portalRect = CGRect(x: 10, y: 180, width: 180, height: 60)
            fixture.window.layer.addSublayer(try makePortal(showing: source.layer, frame: portalRect, matchesPosition: false, matchesTransform: false))
            fixture.window.layoutIfNeeded()

            let pixels = try await Pixels(capture(fixture).image)
            #expect(pixels.count(where: Self.isMagenta) == 0, "\(pixels.count(in: portalRect, where: Self.isMagenta)) in the portal")
        }

        // MARK: - iOS 26 SwiftUI layers

        @available(iOS 26.0, *)
        @Test("iOS 26 SwiftUI text and image layers are masked as `*` rows and black")
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

        @Test("Cost of masking a photo grid at 2x: turn 1 and the whole capture (prints, doesn't assert)")
        func photoGridCost() async throws {
            let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 402, height: 874))
            window.backgroundColor = .white
            window.isHidden = false
            let fixture = try await makeFixture(window: window)
            defer { fixture.close() }
            await prewarm(fixture.mirror, for: window, scale: 2)
            let image = try photo(CGSize(width: 120, height: 120))
            for index in 0 ..< 18 {
                let view = UIImageView(image: image)
                view.frame = CGRect(x: 8 + CGFloat(index % 3) * 130, y: 60 + CGFloat(index / 3) * 130, width: 120, height: 120)
                window.addSubview(view)
            }
            func median(_ values: [Double]) -> Double {
                values.sorted()[values.count / 2]
            }
            var turn1: [Double] = [], total: [Double] = []
            for _ in 0 ..< 9 {
                let start = CACurrentMediaTime()
                let result = try await capture(fixture, scale: 2)
                total.append((CACurrentMediaTime() - start) * 1000)
                turn1.append(result.turn1Milliseconds)
            }
            print("PHOTO-COST median ms: turn1 \(median(turn1)), capture through encode \(median(total))")
        }

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
