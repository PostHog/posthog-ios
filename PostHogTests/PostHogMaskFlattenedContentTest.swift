//
//  PostHogMaskFlattenedContentTest.swift
//  PostHog
//
//  `.drawingGroup()` and `Canvas` flatten their content into a single RenderBox surface
//  (`SwiftUI.RBDrawingView` up to iOS 18, an `RBDrawingLayer` sublayer on iOS 26), so the
//  per-Text masking heuristics can't see the text inside. These tests host real SwiftUI and
//  check the collected mask rects geometrically.

#if os(iOS) && canImport(SwiftUI)
    import Foundation
    @testable import PostHog
    import SwiftUI
    import Testing
    import UIKit

    @Suite("Replay masking of flattened SwiftUI content", .serialized)
    @MainActor
    struct PostHogMaskFlattenedContentTest {
        @MainActor
        private final class Harness {
            let server = MockPostHogServer()
            let sdk: PostHogSDK
            let integration = PostHogReplayIntegration()

            init(maskAllTextInputs: Bool, maskAllImages: Bool) {
                server.start()
                let config = PostHogConfig(projectToken: "flattened_content", host: "http://localhost:9001")
                config.disableReachabilityForTesting = true
                config.disableQueueTimerForTesting = true
                config.disableFlushOnBackgroundForTesting = true
                config.disableRemoteConfigForTesting = true
                config.captureApplicationLifecycleEvents = false
                config.captureScreenViews = false
                config.sessionReplayConfig.maskAllTextInputs = maskAllTextInputs
                config.sessionReplayConfig.maskAllImages = maskAllImages
                config.sessionReplayConfig.screenshotMode = true
                sdk = PostHogSDK.with(config)
                _ = integration.install(sdk)
                integration.stop()
            }

            func close() {
                integration.uninstall(sdk)
                sdk.close()
                server.stop()
            }

            func maskRects(_ view: some View) -> [CGRect] {
                let hosted = host(view)
                defer { hosted.window.isHidden = true }
                return integration.collectMaskableRects(in: hosted.window) ?? []
            }
        }

        private static let canvasSize = CGSize(width: 200, height: 40)

        /// Two lines of text; laid out identically with or without `.drawingGroup()`.
        private struct TwoLines: View {
            var body: some View {
                VStack {
                    Text("Secret flattened")
                    Text("Public flattened")
                }
            }
        }

        /// A Canvas that paints its whole frame (so its drawing surface spans the frame) plus text.
        @available(iOS 15.0, *)
        private struct TextCanvas: View {
            var body: some View {
                Canvas { context, size in
                    context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.yellow))
                    context.draw(Text("Canvas secret"), at: CGPoint(x: size.width / 2, y: size.height / 2))
                }
                .frame(width: PostHogMaskFlattenedContentTest.canvasSize.width,
                       height: PostHogMaskFlattenedContentTest.canvasSize.height)
            }
        }

        /// Frame of the canvas, centered in the pinned test window.
        private var canvasFrame: CGRect {
            CGRect(x: (phMaskTestWindowSize.width - Self.canvasSize.width) / 2,
                   y: (phMaskTestWindowSize.height - Self.canvasSize.height) / 2,
                   width: Self.canvasSize.width, height: Self.canvasSize.height)
        }

        private func expectCovered(_ target: CGRect, by rects: [CGRect], _ context: String) {
            #expect(rects.contains { $0.insetBy(dx: -1, dy: -1).contains(target) },
                    "\(context) must be masked: target=\(target), masks=\(rects)")
        }

        @Test("text inside drawingGroup is masked where the unflattened text would be")
        func drawingGroupTextMasked() throws {
            let harness = Harness(maskAllTextInputs: true, maskAllImages: false)
            defer { harness.close() }

            // Same layout without the drawing group: the per-Text masks show where each line is.
            let textRects = harness.maskRects(TwoLines())
            try #require(textRects.count == 2)

            let flattenedRects = harness.maskRects(TwoLines().drawingGroup())
            for rect in textRects {
                expectCovered(rect, by: flattenedRects, "drawingGroup text")
            }
        }

        @Test("text drawn in a Canvas is masked")
        @available(iOS 15.0, *)
        func canvasTextMasked() {
            let harness = Harness(maskAllTextInputs: true, maskAllImages: false)
            defer { harness.close() }
            expectCovered(canvasFrame, by: harness.maskRects(TextCanvas()), "Canvas")
        }

        @Test("flattened content is masked when only image masking is on")
        @available(iOS 15.0, *)
        func flattenedContentMaskedForImages() {
            let harness = Harness(maskAllTextInputs: false, maskAllImages: true)
            defer { harness.close() }
            // A Canvas or drawing group can draw images too, and there's no way to tell them apart.
            expectCovered(canvasFrame, by: harness.maskRects(TextCanvas()), "Canvas")
        }

        @Test("flattened content is not masked when text and image masking are off")
        @available(iOS 15.0, *)
        func flattenedContentUnmaskedWithGlobalsOff() {
            let harness = Harness(maskAllTextInputs: false, maskAllImages: false)
            defer { harness.close() }
            #expect(harness.maskRects(TwoLines().drawingGroup()).isEmpty)
            #expect(harness.maskRects(TextCanvas()).isEmpty)
        }

        @Test("postHogNoMask on flattened content keeps it unmasked")
        @available(iOS 15.0, *)
        func noMaskOnFlattenedContent() {
            let harness = Harness(maskAllTextInputs: true, maskAllImages: true)
            defer { harness.close() }
            #expect(harness.maskRects(TwoLines().drawingGroup().postHogNoMask()).isEmpty)
            #expect(harness.maskRects(TextCanvas().postHogNoMask()).isEmpty)
        }

        @Test("postHogNoMask on a container around flattened content keeps it unmasked")
        @available(iOS 15.0, *)
        func noMaskContainerAroundFlattenedContent() {
            let harness = Harness(maskAllTextInputs: true, maskAllImages: true)
            defer { harness.close() }
            let rects = harness.maskRects(
                VStack(spacing: 16) {
                    TwoLines().drawingGroup()
                    TextCanvas()
                }
                .padding()
                .postHogNoMask()
            )
            #expect(rects.isEmpty, "masks=\(rects)")
        }

        @Test("postHogNoMask on a view inside a drawing group is ignored, so the group stays masked")
        func noMaskInsideDrawingGroupFailsClosed() throws {
            // Like postHogMask(), postHogNoMask() relies on platform views SwiftUI can't render
            // inside a drawing group, so it can't unmask part of the group.
            let harness = Harness(maskAllTextInputs: true, maskAllImages: false)
            defer { harness.close() }
            let textRects = harness.maskRects(TwoLines())
            try #require(textRects.count == 2)

            let rects = harness.maskRects(
                VStack {
                    Text("Secret flattened").postHogNoMask()
                    Text("Public flattened")
                }
                .drawingGroup()
            )
            for rect in textRects {
                expectCovered(rect, by: rects, "drawingGroup text with a postHogNoMask child")
            }
        }

        // Known limitation: inside a drawing group SwiftUI creates postHogMask()'s reporter view but
        // never attaches it to the screen, so it reports no region, and postHogNoMask() on the group
        // then unmasks everything in it.
        // Fixing it would mean reporting the mask some other way (e.g. through SwiftUI geometry
        // instead of a platform view), a redesign of postHogMask() out of scope for this fix.
        @Test("postHogMask inside a postHogNoMask drawing group is lost (known limitation)")
        func explicitMaskInsideNoMaskDrawingGroup() throws {
            let harness = Harness(maskAllTextInputs: true, maskAllImages: true)
            defer { harness.close() }
            let textRects = harness.maskRects(TwoLines())
            try #require(textRects.count == 2)

            let rects = harness.maskRects(
                VStack {
                    Text("Secret flattened").postHogMask()
                    Text("Public flattened")
                }
                .drawingGroup()
                .postHogNoMask()
            )
            withKnownIssue("postHogMask() inside a drawing group is ignored, so the group's postHogNoMask() unmasks it") {
                expectCovered(textRects[0], by: rects, "explicitly masked text inside a postHogNoMask drawing group")
            }
        }

        @Test("postHogMask around flattened content wins over its postHogNoMask")
        func explicitMaskWinsOverNoMaskOnFlattenedContent() throws {
            let masked = Harness(maskAllTextInputs: true, maskAllImages: false)
            let textRects = masked.maskRects(TwoLines())
            masked.close()
            try #require(textRects.count == 2)

            let unmasked = Harness(maskAllTextInputs: false, maskAllImages: false)
            defer { unmasked.close() }
            let rects = unmasked.maskRects(
                TwoLines().drawingGroup().postHogNoMask()
                    .padding()
                    .postHogMask()
            )
            for rect in textRects {
                expectCovered(rect, by: rects, "noMask drawingGroup inside an explicit mask")
            }
        }

        @Test("postHogMask applied outside a drawing group masks the whole group")
        func explicitMaskOutsideDrawingGroup() throws {
            // postHogMask() inside a drawing group can't work (its reporter is a platform view,
            // which SwiftUI can't render there); applying it to the group itself is the supported form.
            let masked = Harness(maskAllTextInputs: true, maskAllImages: false)
            let textRects = masked.maskRects(TwoLines())
            masked.close()
            try #require(textRects.count == 2)

            let unmasked = Harness(maskAllTextInputs: false, maskAllImages: false)
            defer { unmasked.close() }
            let rects = unmasked.maskRects(TwoLines().drawingGroup().postHogMask())
            for rect in textRects {
                expectCovered(rect, by: rects, "explicitly masked drawingGroup text")
            }
        }
    }
#endif
