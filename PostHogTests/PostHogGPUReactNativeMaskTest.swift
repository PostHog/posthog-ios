#if os(iOS) && canImport(Metal) && (!SWIFT_PACKAGE || SessionReplay)
    import Foundation
    @testable import PostHog
    import Testing
    import UIKit

    private final class FabricParagraphTextView: UIView {
        var text = ""

        override func draw(_: CGRect) {
            (text as NSString).draw(at: CGPoint(x: 4, y: 4), withAttributes: [.font: UIFont.boldSystemFont(ofSize: 22),
                                                                              .foregroundColor: UIColor.magenta])
        }
    }

    @Suite("Replay GPU inline masking for React Native (Fabric) text", .serialized)
    @MainActor
    struct PostHogGPUReactNativeMaskTest: GPUCaptureTesting {
        /// A stand-in for React Native's paragraph view, which draws nothing itself: a child view
        /// (`RCTParagraphTextView`) draws its text. With no text, the child has no `draw(_:)`, so no backing store.
        private func makeParagraph(_ frame: CGRect, text: String?) throws -> UIView {
            // Registered by PostHogReactNativeMaskingTest's stub.
            let paragraphClass = try #require(NSClassFromString("RCTParagraphComponentView") as? UIView.Type)
            let paragraph = paragraphClass.init(frame: frame)
            let textView = text.map { text -> UIView in
                let textView = FabricParagraphTextView(frame: paragraph.bounds)
                textView.text = text
                textView.isOpaque = false
                return textView
            } ?? UIView(frame: paragraph.bounds)
            paragraph.addSubview(textView)
            return paragraph
        }

        @Test("A Fabric paragraph, whose text a child view draws, is drawn as `*` rows")
        func fabricParagraphIsRows() async throws {
            let paragraph = try makeParagraph(CGRect(x: 10, y: 40, width: 180, height: 40), text: "Secret value 42")
            let fixture = try await makeFixture()
            defer { fixture.close() }
            fixture.window.addSubview(paragraph)

            fixture.config.maskAllTextInputs = false
            #expect(try await Pixels(capture(fixture).image).count(where: Self.isMagenta) > 50)
            fixture.config.maskAllTextInputs = true

            let result = try await captureStars(fixture)
            let pixels = try expectFullyMasked(result)
            #expect(fixture.mask.textBarsForTesting > 0)
            #expect(pixels.count(in: paragraph.frame, where: Self.isStar) > 30)
        }

        @Test("An empty Fabric paragraph, whose child draws nothing, draws no rows")
        func emptyFabricParagraphDrawsNothing() async throws {
            let paragraph = try makeParagraph(CGRect(x: 10, y: 40, width: 180, height: 40), text: nil)
            let fixture = try await makeFixture()
            defer { fixture.close() }
            fixture.window.addSubview(paragraph)
            fixture.config.maskAllTextInputs = true

            let result = try await captureStars(fixture)
            let pixels = try expectFullyMasked(result)
            #expect(fixture.mask.textBarsForTesting == 0)
            #expect(pixels.count(where: Self.isStar) == 0)
            #expect(pixels.count(in: paragraph.frame, where: Self.isBlack) == 0)
        }

        @Test("An empty Fabric paragraph with a border bitmap, a layer no view owns, draws no rows")
        func emptyFabricParagraphBorderDrawsNothing() async throws {
            let paragraph = try makeParagraph(CGRect(x: 10, y: 40, width: 180, height: 40), text: nil)
            // As RCTViewComponentView draws a non-uniform border.
            let border = CALayer()
            border.frame = paragraph.bounds
            border.contents = try magentaContents(CGSize(width: 4, height: 4))
            paragraph.layer.addSublayer(border)
            let fixture = try await makeFixture()
            defer { fixture.close() }
            fixture.window.addSubview(paragraph)
            fixture.config.maskAllTextInputs = true

            let result = try await captureStars(fixture)
            let pixels = try expectFullyMasked(result)
            #expect(fixture.mask.textBarsForTesting == 0)
            #expect(pixels.count(where: Self.isStar) == 0)
        }
    }
#endif
