#if os(iOS) && canImport(Metal)
    import Foundation
    @testable import PostHog
    import Testing
    import UIKit

    /// React Native's New Architecture paragraph view, registered under its runtime name. Like the real one it draws
    /// nothing itself: a child view (`RCTParagraphTextView`) draws its text. The integration resolves the class when
    /// created, so tests build their paragraph before their fixture.
    private func fabricParagraphViewClass() -> UIView.Type {
        let name = "RCTParagraphComponentView"
        if let existing = NSClassFromString(name) as? UIView.Type {
            return existing
        }
        let cls: AnyClass = objc_allocateClassPair(UIView.self, name, 0)!
        objc_registerClassPair(cls)
        return cls as! UIView.Type
    }

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
        /// With no text, the child has no `draw(_:)`, so it has no backing store.
        private func makeParagraph(_ frame: CGRect, text: String?) -> UIView {
            let paragraph = fabricParagraphViewClass().init(frame: frame)
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
            let paragraph = makeParagraph(CGRect(x: 10, y: 40, width: 180, height: 40), text: "Secret value 42")
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
            let paragraph = makeParagraph(CGRect(x: 10, y: 40, width: 180, height: 40), text: nil)
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
    }
#endif
