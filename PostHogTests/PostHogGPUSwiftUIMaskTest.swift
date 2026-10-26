#if os(iOS) && canImport(Metal)
    import Foundation
    @testable import PostHog
    import QuartzCore
    import SwiftUI
    import Testing
    import UIKit

    /// Window frames of tagged SwiftUI views, read once they've laid out.
    @MainActor
    private final class FrameStore {
        var frames: [String: CGRect] = [:]
    }

    @available(iOS 14.0, *)
    private struct FrameTag: ViewModifier {
        let name: String
        let store: FrameStore

        func body(content: Content) -> some View {
            content.background(GeometryReader { proxy in
                Color.clear
                    .onAppear { store.frames[name] = proxy.frame(in: .global) }
                    .onChange(of: proxy.frame(in: .global)) { store.frames[name] = $0 }
            })
        }
    }

    @available(iOS 14.0, *)
    private extension View {
        func frameTag(_ name: String, _ store: FrameStore) -> some View {
            modifier(FrameTag(name: name, store: store))
        }
    }

    /// A magenta UIKit view with a magenta layer border: colour with no content.
    /// A masked card with a medium sheet over its lower part, the sheet's content green.
    @available(iOS 16.0, *)
    private struct SheetOverMaskedCard: View {
        @State var isPresented = false

        var body: some View {
            VStack {
                card {
                    Circle().fill(magenta).frame(width: 50, height: 50)
                    boldText("Visa ending 4242", color: magenta)
                    Color.clear.frame(height: 160)
                }.postHogMask()
                Spacer()
            }
            .padding()
            .sheet(isPresented: $isPresented) {
                VStack(spacing: 16) {
                    boldText("Sheet content", color: green)
                    green.frame(height: 40)
                    Spacer()
                }
                .padding()
                .presentationDetents([.medium])
            }
            .onAppear {
                // A window outside a scene never finishes a presentation's animation.
                var transaction = Transaction()
                transaction.disablesAnimations = true
                withTransaction(transaction) { isPresented = true }
            }
        }
    }

    private struct ColorBox: UIViewRepresentable {
        func makeUIView(context _: Context) -> UIView {
            let view = UIView()
            view.backgroundColor = .magenta
            view.layer.borderWidth = 4
            view.layer.borderColor = UIColor.magenta.cgColor
            view.layer.cornerRadius = 6
            return view
        }

        func updateUIView(_: UIView, context _: Context) {}
    }

    private struct ImageViewRepresentable: UIViewRepresentable {
        let image: UIImage

        func makeUIView(context _: Context) -> UIImageView {
            UIImageView(image: image)
        }

        func updateUIView(_: UIImageView, context _: Context) {}
    }

    private let magenta = Color(red: 1, green: 0, blue: 1)
    private let green = Color(red: 0, green: 1, blue: 0)
    private let yellow = Color(red: 1, green: 1, blue: 0)

    private func boldText(_ string: String, size: CGFloat = 22, color: Color) -> some View {
        Text(string).font(.system(size: size, weight: .bold)).foregroundColor(color)
    }

    /// A yellow rounded card around `content`.
    private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8, content: content)
            .padding()
            .background(RoundedRectangle(cornerRadius: 12).fill(yellow))
    }

    /// `postHogMask()` on the GPU path: everything painted under a reporter's extent before it is masked in the mirror,
    /// chrome included. Magenta pixel tests, rect pass included.
    @Suite("Replay GPU SwiftUI masking", .serialized)
    @MainActor
    struct PostHogGPUSwiftUIMaskTest: GPUCaptureTesting {
        /// Masking by `postHogMask()` alone: the walk's own text and image masking is off unless a test turns it on.
        private func makeSwiftUIFixture(gpu: Bool = true) async throws -> GPUCaptureFixture {
            let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 300, height: 500))
            window.backgroundColor = .white
            window.overrideUserInterfaceStyle = .light
            window.isHidden = false
            let fixture = try await makeFixture(window: window, gpu: gpu)
            fixture.config.maskAllTextInputs = false
            fixture.config.maskAllImages = false
            return fixture
        }

        private func show(_ content: some View, in fixture: GPUCaptureFixture, background: UIColor = .white) async {
            let controller = UIHostingController(rootView: content)
            controller.view.backgroundColor = background
            fixture.window.rootViewController = controller
            fixture.window.layoutIfNeeded()
            // SwiftUI lays out and draws over the next few turns, and reporters must finish their first layout.
            try? await Task.sleep(nanoseconds: 500_000_000)
            fixture.window.layoutIfNeeded()
        }

        /// The masked frame once `*` are drawn, and the first reporter's extent. Both that frame and the first (text as
        /// bars) leave nothing to the rect pass, replace no copy whole, and show no magenta: anywhere, or only inside the
        /// extent when `insideExtentOnly`.
        private func captureMasked(_ fixture: GPUCaptureFixture, insideExtentOnly: Bool = false,
                                   sourceLocation: SourceLocation = #_sourceLocation) async throws -> (pixels: Pixels, extent: CGRect)
        {
            let extent = try #require(reporterRects(in: fixture.window).first, sourceLocation: sourceLocation)
            PostHogInlineMask.textColorForTesting = .blue
            defer { PostHogInlineMask.textColorForTesting = nil }
            var pixels: Pixels?
            for drawn in [false, true] {
                if drawn { fixture.mask.waitForTextDrawsForTesting() }
                let result = try await capture(fixture)
                let frame = try Pixels(result.image)
                #expect(result.rectRegions.isEmpty, "regions left to the rect pass", sourceLocation: sourceLocation)
                #expect(fixture.mask.extentStatsForTesting.replaced == 0, "copies replaced whole", sourceLocation: sourceLocation)
                #expect(frame.count(in: insideExtentOnly ? extent : nil, where: Self.isMagenta) == 0, "source pixels left",
                        sourceLocation: sourceLocation)
                pixels = frame
            }
            return (try #require(pixels), extent)
        }

        private func reporters(in window: UIWindow) -> [PostHogMaskReporterUIView] {
            var reporters: [PostHogMaskReporterUIView] = []
            func visit(_ view: UIView) {
                if let reporter = view as? PostHogMaskReporterUIView { reporters.append(reporter) }
                view.subviews.forEach(visit)
            }
            visit(window)
            return reporters
        }

        private func reporterRects(in window: UIWindow) -> [CGRect] {
            reporters(in: window).map { $0.toPresentationRect(window) }
        }

        private static func near(_ target: RGBA, within tolerance: Int) -> (RGBA) -> Bool {
            { pixel in
                abs(Int(pixel.red) - Int(target.red)) <= tolerance && abs(Int(pixel.green) - Int(target.green)) <= tolerance
                    && abs(Int(pixel.blue) - Int(target.blue)) <= tolerance
            }
        }

        private static let isGreen = near(.green, within: 75)
        private static let isYellow = near(RGBA(red: 255, green: 255, blue: 0, alpha: 255), within: 25)
        private static let isWhite = near(.white, within: 25)
        private static let isGroupedBackground = near(RGBA(red: 242, green: 242, blue: 247, alpha: 255), within: 4)

        /// Control frame with reporters off: proves the masked content rendered, so the masking tests can't pass on
        /// nothing.
        @discardableResult
        private func expectVisibleUnmasked(_ fixture: GPUCaptureFixture, minimum: Int = 50,
                                           sourceLocation: SourceLocation = #_sourceLocation) async throws -> Pixels
        {
            let reporters = reporters(in: fixture.window)
            try #require(!reporters.isEmpty, "no reporter", sourceLocation: sourceLocation)
            reporters.forEach { $0.isMaskingEnabled = false }
            defer { reporters.forEach { $0.isMaskingEnabled = true } }
            fixture.mask.isEnabledForTesting = false
            defer { fixture.mask.isEnabledForTesting = true }
            let result = try await capture(fixture)
            try #require(result.rectRegions.isEmpty, sourceLocation: sourceLocation)
            let pixels = try Pixels(result.image)
            try #require(pixels.count(where: Self.isMagenta) >= minimum, "the masked content didn't render", sourceLocation: sourceLocation)
            return pixels
        }

        /// Every placed copy's recorded bounds-to-window map gives the frame Core Animation's own conversion does.
        @discardableResult
        private func expectPlacementsAgree(_ fixture: GPUCaptureFixture, sourceLocation: SourceLocation = #_sourceLocation) throws
            -> PostHogInlineMask.CopyIndex
        {
            let frame = try #require(fixture.mirror.build(window: fixture.window, scale: 1), sourceLocation: sourceLocation)
            defer { frame.release() }
            let root = try #require(frame.rootCopy, sourceLocation: sourceLocation)
            let copies = frame.copies.index()
            var placed = 0
            func visit(_ layer: CALayer) {
                if let placement = copies.placement(of: layer) {
                    placed += 1
                    let stored = layer.bounds.applying(placement.toWindow), converted = layer.convert(layer.bounds, to: root)
                    let agrees = abs(stored.minX - converted.minX) < 0.01 && abs(stored.minY - converted.minY) < 0.01
                        && abs(stored.width - converted.width) < 0.01 && abs(stored.height - converted.height) < 0.01
                    #expect(agrees, "\(layer): \(stored) vs \(converted)", sourceLocation: sourceLocation)
                }
                layer.sublayers?.forEach(visit)
            }
            visit(root)
            #expect(placed > 3, sourceLocation: sourceLocation)
            return copies
        }

        // MARK: - S1-S5

        @Test("S1: masked Text is drawn as `*` rows in place, its neighbour untouched, with no rect left")
        func maskedTextIsRows() async throws {
            let fixture = try await makeSwiftUIFixture()
            defer { fixture.close() }
            await show(VStack(spacing: 16) {
                boldText("Secret name", size: 28, color: magenta).postHogMask()
                boldText("Public", size: 28, color: green)
            }, in: fixture)
            try await expectVisibleUnmasked(fixture)

            let (pixels, extent) = try await captureMasked(fixture)
            #expect(fixture.mask.extentStatsForTesting.count == 1)
            #expect(fixture.mask.extentStatsForTesting.replaced == 0)
            #expect(pixels.count(in: extent, where: Self.isStar) > 30)
            #expect(pixels.count(where: Self.isGreen) > 50)
            // The host's white background under the extent is masked too.
            #expect(pixels.count(in: extent, where: Self.isWhite) == 0)
        }

        @available(iOS 14.0, *)
        @Test("S2: a masked card's background is black, its text `*` and its photo blurred")
        func maskedCardMasksChrome() async throws {
            let fixture = try await makeSwiftUIFixture()
            defer { fixture.close() }
            let frames = FrameStore()
            // A UIKit image: SwiftUI draws symbols as text, and its own image layers' contents aren't mirrored.
            let photo = try checkerboard(CGSize(width: 48, height: 48))
            await show(card {
                ImageViewRepresentable(image: photo).frame(width: 48, height: 48).frameTag("icon", frames)
                boldText("Card holder", color: magenta)
                boldText("1234 5678", color: magenta)
            }.postHogMask(), in: fixture)
            let icon = try #require(frames.frames["icon"]).insetBy(dx: 2, dy: 2)
            let control = try await expectVisibleUnmasked(fixture)
            try #require(control.maxNeighbourStep(in: icon) > 150, "the photo didn't render sharp")

            let (pixels, extent) = try await captureMasked(fixture)
            // Blurred to colour blobs: no detail at the checkerboard's scale, and not blacked out.
            #expect(pixels.maxNeighbourStep(in: icon) <= Self.blurredMaxStep)
            let middle = pixels[Int(icon.midX), Int(icon.midY)]
            #expect(middle.red > 60 && middle.green < 40 && middle.blue > 60, "\(middle)")
            #expect(pixels.count(in: extent, where: Self.isYellow) == 0)
            #expect(pixels.count(in: extent, where: Self.isStar) > 30)
        }

        @Test("S2 with the walk's own masking on: the card is masked, background included, nothing left to the rect pass")
        func maskedCardWithAutoMasking() async throws {
            let fixture = try await makeSwiftUIFixture()
            defer { fixture.close() }
            fixture.config.maskAllTextInputs = true
            fixture.config.maskAllImages = true
            let checker = try checkerboard(CGSize(width: 40, height: 40))
            await show(card {
                Image(uiImage: checker)
                boldText("Card holder", color: magenta)
            }.postHogMask(), in: fixture)

            let (pixels, extent) = try await captureMasked(fixture)
            #expect(pixels.count(in: extent, where: Self.isYellow) == 0)
        }

        @Test("S3: a masked List row is masked with its row background, and the list outside it is untouched")
        func maskedListRow() async throws {
            let fixture = try await makeSwiftUIFixture()
            defer { fixture.close() }
            let checker = try checkerboard(CGSize(width: 32, height: 32))
            await show(List {
                ForEach(0 ..< 5) { row in
                    if row == 2 {
                        HStack {
                            Image(uiImage: checker)
                            boldText("Row \(row)", color: magenta)
                        }
                        .postHogMask()
                        .listRowBackground(yellow)
                    } else {
                        boldText("Row \(row)", color: green)
                    }
                }
            }, in: fixture)
            try await expectVisibleUnmasked(fixture)
            try expectPlacementsAgree(fixture)

            let (pixels, extent) = try await captureMasked(fixture)
            #expect(pixels.count(in: extent, where: Self.isYellow) == 0)
            #expect(pixels.count(where: Self.isYellow) > 100, "the row background outside the extent")
            #expect(pixels.count(where: Self.isGreen) > 100)
            #expect(pixels.count(where: Self.isGroupedBackground) > 1000, "the list background")
        }

        @Test("A copy whose geometry has an uncommitted change keeps no recorded placement: the copy sits where it was committed")
        func uncommittedGeometryForgetsPlacement() async throws {
            let fixture = try await makeSwiftUIFixture()
            defer { fixture.close() }
            await show(card { boldText("Card holder", color: magenta) }.postHogMask(), in: fixture)
            try expectPlacementsAgree(fixture)

            let moved = try #require(fixture.window.rootViewController?.view.layer.sublayers?.first)
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            moved.position.x += 10
            defer { CATransaction.commit() }
            let copies = try expectPlacementsAgree(fixture)
            let copy = try #require(copies.copies(of: moved).first)
            #expect(copies.placement(of: copy) == nil)
        }

        @Test("Colour without content inside an extent is black: a filled Circle, a rounded background and a bordered view")
        func colorOnlyLayersInsideAreBlack() async throws {
            let fixture = try await makeSwiftUIFixture()
            defer { fixture.close() }
            await show(VStack(spacing: 12) {
                Circle().fill(magenta).frame(width: 40, height: 40)
                Color.clear.frame(width: 80, height: 30).background(magenta).cornerRadius(8)
                ColorBox().frame(width: 60, height: 30)
            }.padding().postHogMask(), in: fixture)
            try await expectVisibleUnmasked(fixture, minimum: 1000)

            let (pixels, extent) = try await captureMasked(fixture)
            #expect(pixels.count(in: extent, where: Self.isBlack) > Int(extent.width * extent.height) / 2)
        }

        @available(iOS 14.0, *)
        @Test("A coloured, bordered view partly under an extent is covered over it, border included, and keeps its colour outside it")
        func colorLayerPartlyInsideIsCovered() async throws {
            let fixture = try await makeSwiftUIFixture()
            defer { fixture.close() }
            let frames = FrameStore()
            await show(ZStack {
                ColorBox().frame(width: 160, height: 100).frameTag("box", frames)
                Color.clear.frame(width: 80, height: 60).postHogMask().offset(x: 80)
            }, in: fixture)
            let box = try #require(frames.frames["box"])
            let extent = try #require(reporterRects(in: fixture.window).first)
            // Over the box's right border and past it.
            try #require(extent.minX < box.maxX - 4 && extent.maxX > box.maxX, "\(extent) vs \(box)")
            try await expectVisibleUnmasked(fixture, minimum: 1000)

            let (pixels, _) = try await captureMasked(fixture, insideExtentOnly: true)
            #expect(pixels.count(where: Self.isMagenta) > 4000, "covered, not replaced whole")
        }

        @Test("UIKit views painted after the reporter stay visible over its extent, those painted before it are masked")
        func otherViewsFollowPaintOrder() async throws {
            let fixture = try await makeSwiftUIFixture()
            defer { fixture.close() }
            await show(boldText("Secret name", size: 28, color: green).postHogMask(), in: fixture, background: .clear)
            let extent = try #require(reporterRects(in: fixture.window).first)
            // Under the hosting view's container, so painted before the reporter, and wider than the extent.
            let below = UIView(frame: extent.insetBy(dx: -30, dy: -10))
            below.backgroundColor = .magenta
            fixture.window.insertSubview(below, at: 0)
            // Over it: a UIKit view, and a second SwiftUI host.
            let above = UIView(frame: CGRect(x: extent.minX + 4, y: extent.minY + 4, width: 30, height: extent.height - 8))
            above.backgroundColor = .blue
            let sibling = UIHostingController(rootView: Color(red: 1, green: 1, blue: 0))
            sibling.view.frame = CGRect(x: extent.maxX - 34, y: extent.minY + 4, width: 30, height: extent.height - 8)
            fixture.window.addSubview(above)
            fixture.window.addSubview(sibling.view)
            try await expectVisibleUnmasked(fixture, minimum: 500)

            let (pixels, _) = try await captureMasked(fixture, insideExtentOnly: true)
            #expect(fixture.mask.extentStatsForTesting.unordered == 0)
            #expect(pixels.count(where: Self.isMagenta) > 500, "covered over the extent, not replaced whole")
            for (view, isColor) in [(above, Self.near(.blue, within: 25)), (sibling.view!, Self.isYellow)] {
                let area = view.frame.insetBy(dx: 1, dy: 1).integral
                #expect(pixels.count(in: area, where: isColor) > Int(area.width * area.height * 0.9))
            }
        }

        @available(iOS 14.0, *)
        @Test("A masked SwiftUI Image is blurred in the frame's pixels, keeping its colours rather than going black")
        func swiftUIImageIsBlurredNotBlack() async throws {
            let fixture = try await makeSwiftUIFixture()
            defer { fixture.close() }
            let frames = FrameStore()
            let checker = try checkerboard(CGSize(width: 120, height: 80))
            await show(Image(uiImage: checker).frameTag("image", frames), in: fixture)
            let area = try #require(frames.frames["image"]).insetBy(dx: 2, dy: 2)
            let control = try await Pixels(capture(fixture).image)
            try #require(control.maxNeighbourStep(in: area) > 150, "the image didn't render sharp")

            fixture.config.maskAllImages = true
            let pixels = try await expectFullyMasked(capture(fixture))
            #expect(pixels.maxNeighbourStep(in: area) <= Self.blurredMaxStep)
            // Magenta and black cells average to a dark magenta, not black.
            let middle = pixels[Int(area.midX), Int(area.midY)]
            #expect(Self.isMagentaHue(middle), "\(middle)")
        }

        @Test("S4: a masked TextField's text is `*`, with no rect left")
        func maskedTextField() async throws {
            let fixture = try await makeSwiftUIFixture()
            defer { fixture.close() }
            await show(VStack(spacing: 20) {
                TextField("Email", text: .constant("secret@example.com"))
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(magenta)
                    .textFieldStyle(.roundedBorder)
                    .postHogMask()
                TextField("Name", text: .constant("Plain Name"))
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(green)
                    .textFieldStyle(.roundedBorder)
            }.padding(), in: fixture)
            try await expectVisibleUnmasked(fixture)

            let (pixels, extent) = try await captureMasked(fixture)
            #expect(pixels.count(in: extent, where: Self.isStar) > 30)
            #expect(pixels.count(where: Self.isGreen) > 50)
        }

        @available(iOS 15.0, *)
        private func buttonOverMaskedText(_ frames: FrameStore) -> some View {
            ZStack {
                boldText("Under the button", size: 34, color: magenta).postHogMask()
                Button("Over") {}.font(.system(size: 22, weight: .bold)).buttonStyle(.borderedProminent).tint(green).frameTag("over", frames)
            }
        }

        /// The middle of the capsule, where only its title is white.
        private func titleArea(of button: CGRect) -> CGRect {
            CGRect(x: button.midX - 20, y: button.midY - 8, width: 40, height: 16)
        }

        @available(iOS 15.0, *)
        @Test("S5: a button painted over masked text is still visible, the text under it masked")
        func buttonOverMaskedTextStaysVisible() async throws {
            let fixture = try await makeSwiftUIFixture()
            defer { fixture.close() }
            let frames = FrameStore()
            await show(buttonOverMaskedText(frames), in: fixture)
            try await expectVisibleUnmasked(fixture)

            let (pixels, _) = try await captureMasked(fixture)
            let button = try #require(frames.frames["over"])
            #expect(fixture.mask.extentStatsForTesting.unordered == 0)
            #expect(pixels.count(in: button, where: Self.isGreen) > 200)
            // The button's white title, painted after the reporter.
            #expect(pixels.count(in: titleArea(of: button), where: Self.isWhite) > 20)
        }

        @available(iOS 15.0, *)
        @Test("S5 with a zPosition in the host over the extent: the paint order is dropped and the button's title is masked too")
        func zPositionDropsPaintOrder() async throws {
            let fixture = try await makeSwiftUIFixture()
            defer { fixture.close() }
            let frames = FrameStore()
            await show(buttonOverMaskedText(frames), in: fixture)
            let button = try #require(frames.frames["over"])
            let host = try #require(fixture.window.rootViewController?.view)
            let raised = try #require((host.layer.sublayers ?? []).last {
                $0.convert($0.bounds, to: fixture.window.layer).intersects(button)
            })
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            raised.zPosition = 1
            CATransaction.commit()

            let (pixels, _) = try await captureMasked(fixture)
            #expect(fixture.mask.extentStatsForTesting.unordered == 1)
            #expect(pixels.count(in: titleArea(of: button), where: Self.isWhite) == 0)
        }

        // MARK: - S6, S7

        @Test("S6: postHogNoMask text stays unmasked on the GPU path while its auto-masked neighbour is `*`")
        func noMaskStaysUnmasked() async throws {
            let fixture = try await makeSwiftUIFixture()
            defer { fixture.close() }
            fixture.config.maskAllTextInputs = true
            await show(VStack(spacing: 16) {
                boldText("Unmasked", size: 28, color: magenta).postHogNoMask()
                boldText("Default masked", size: 28, color: green)
            }, in: fixture)

            let result = try await captureStars(fixture, checkingFirstFrame: false)
            let pixels = try Pixels(result.image)
            #expect(result.rectRegions.isEmpty)
            #expect(pixels.count(where: Self.isMagenta) > 50)
            #expect(pixels.count(where: Self.isGreen) == 0)
            #expect(pixels.count(where: Self.isStar) > 30)
        }

        @available(iOS 26.0, *)
        @Test("S7: glass labels, drawn through a portal from a zero-size source layer, are masked inside their extents")
        func glassThroughZeroSizePortalSource() async throws {
            let fixture = try await makeSwiftUIFixture()
            defer { fixture.close() }
            await show(VStack(spacing: 40) {
                Button {} label: {
                    Text("Glass label").font(.system(size: 22, weight: .bold)).foregroundStyle(magenta)
                }
                .buttonStyle(.glass)
                .postHogMask()
                Text("Glass text").font(.system(size: 22, weight: .bold)).foregroundStyle(magenta).padding().glassEffect().postHogMask()
                boldText("Plain neighbour", color: green)
            }, in: fixture)
            try await expectVisibleUnmasked(fixture, minimum: 20)

            let (pixels, _) = try await captureMasked(fixture)
            #expect(fixture.mask.extentStatsForTesting.count == 2)
            #expect(pixels.count(where: Self.isGreen) > 50)
        }

        // MARK: - Fallbacks and the default path

        @available(iOS 16.0, *)
        @Test("A sheet presented over a masked card keeps its content: the sheet is painted after the reporter")
        func sheetOverExtentStaysVisible() async throws {
            let fixture = try await makeSwiftUIFixture()
            defer { fixture.close() }
            fixture.window.makeKey()
            await show(SheetOverMaskedCard(), in: fixture)
            // Captures skip a frame while the sheet's presentation animates in.
            let root = try #require(fixture.window.rootViewController)
            await waitUntil(timeout: 5) { root.presentedViewController.map { $0.transitionCoordinator == nil } ?? false }
            try #require(root.presentedViewController != nil, "the sheet didn't present")

            let (pixels, _) = try await captureMasked(fixture, insideExtentOnly: true)
            #expect(fixture.mask.extentStatsForTesting.unordered == 0)
            #expect(pixels.count(where: Self.isGreen) > 3000, "the sheet's content")
        }

        @Test("A backdrop under an extent is covered over it, not hidden: its sublayers outside the extent stay")
        func backdropUnderExtentKeepsItsSublayers() async throws {
            let fixture = try await makeSwiftUIFixture()
            defer { fixture.close() }
            await show(boldText("Secret name", size: 28, color: magenta).postHogMask(), in: fixture, background: .clear)
            let extent = try #require(reporterRects(in: fixture.window).first)
            let backdropClass = try #require(NSClassFromString("CABackdropLayer") as? CALayer.Type)
            // Under the host, so painted before the reporter, and reaching well past the extent.
            let backdrop = backdropClass.init()
            backdrop.frame = extent.insetBy(dx: -10, dy: -60)
            let content = CALayer()
            content.frame = backdrop.bounds
            content.backgroundColor = UIColor.green.cgColor
            backdrop.addSublayer(content)
            fixture.window.layer.insertSublayer(backdrop, at: 0)
            try await expectVisibleUnmasked(fixture)

            let (pixels, _) = try await captureMasked(fixture)
            #expect(pixels.count(in: extent, where: Self.isGreen) == 0)
            #expect(pixels.count(where: Self.isGreen) > 4000, "the backdrop's sublayer outside the extent")
        }

        @Test("A reporter with no copy in the mirror (left out as far off screen) keeps its rect")
        func uncopiedReporterStaysRect() async throws {
            let fixture = try await makeSwiftUIFixture()
            defer { fixture.close() }
            let reporter = PostHogMaskReporterUIView(frame: CGRect(x: 1200, y: 50, width: 100, height: 60))
            fixture.window.addSubview(reporter)
            fixture.window.layoutIfNeeded()

            let result = try await capture(fixture)
            #expect(result.rectRegions == [reporter.frame])
            #expect(fixture.mask.extentStatsForTesting.count == 0)
        }

        @Test("With GPU capture off, a masked card is still one black rect and no mirror is built")
        func defaultPathKeepsReporterRects() async throws {
            let fixture = try await makeSwiftUIFixture(gpu: false)
            defer { fixture.close() }
            await show(card { boldText("Card holder", color: magenta) }.postHogMask(), in: fixture)

            let result = try #require(fixture.integration.defaultPathCaptureForTesting(window: fixture.window))
            let extent = try #require(reporterRects(in: fixture.window).first)
            #expect(result.rectRegions == [extent])
            #expect(result.inlineRegionCount == 0)
            #expect(fixture.mirror.copiesMadeForTesting == 0)
            let pixels = try Pixels(result.image)
            // The rect pass rounds its corners by 10 points.
            let filled = extent.insetBy(dx: 10, dy: 10).integral
            #expect(pixels.count(in: filled, where: Self.isBlack) == Int(filled.width * filled.height))
            #expect(pixels.count(in: extent, where: Self.isYellow) == 0)
        }

        // MARK: - Cost

        @Test("Turn-1 cost on a screen of masked rows, with and without reporter extents masked inline (prints, doesn't assert)")
        func turnOneExtentCost() async throws {
            let fixture = try await makeSwiftUIFixture()
            defer { fixture.close() }
            fixture.config.maskAllTextInputs = true
            fixture.config.maskAllImages = true
            await show(VStack(alignment: .leading, spacing: 2) {
                ForEach(0 ..< 30) { row in
                    HStack {
                        Text("Row \(row)").font(.system(size: 11))
                        Text("Jane Doe paid $\(row * 7).50").font(.system(size: 11))
                    }
                    .padding(.horizontal, 4)
                    .background(RoundedRectangle(cornerRadius: 3).fill(yellow))
                    .postHogMask()
                }
            }, in: fixture)

            func median(_ values: [Double]) -> Double {
                values.sorted()[values.count / 2]
            }
            var rects: [Double] = [], inline: [Double] = [], extent: [Double] = []
            for _ in 0 ..< 9 {
                fixture.mask.isExtentEnabledForTesting = false
                rects.append(try await capture(fixture).turn1Milliseconds)
                fixture.mask.isExtentEnabledForTesting = true
                fixture.mask.waitForTextDrawsForTesting()
                let result = try await capture(fixture)
                #expect(result.rectRegions.isEmpty)
                inline.append(result.turn1Milliseconds)
                extent.append(fixture.mask.extentStatsForTesting.milliseconds)
            }
            print("EXTENT-COST turn1 ms median: reporters as rects \(median(rects)), reporters inline \(median(inline))")
            print("EXTENT-COST turn1 ms min: reporters as rects \(rects.min() ?? 0), reporters inline \(inline.min() ?? 0)")
            print("EXTENT-COST extent pass ms median \(median(extent)), min \(extent.min() ?? 0)")
        }
    }
#endif
