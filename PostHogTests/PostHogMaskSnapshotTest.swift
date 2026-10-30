//
//  Golden-image visual regression for session-replay masking. Each scenario renders
//  the original UI beside the same UI with the SDK's redaction rects painted black
//  (what replay bakes into the uploaded WebP), captioned with the masking option it
//  exercises. A human verifies the committed goldens once; CI re-renders and fails
//  if masking output drifts.
//
//  Compile-flag gated (xcodebuild doesn't forward host env into the sim):
//  TEST_MASK_SNAPSHOTS compiles the suite in — only the dedicated make targets pass it,
//  so normal test runs (Xcode ⌘U, testOniOSSimulator) don't contain it at all —
//  and RECORD_MASK_SNAPSHOTS additionally enables recording, so a verify run can
//  never silently rewrite the goldens.
//    - Verify (CI, required, pinned OS runtime):     make maskSnapshots
//        → on mismatch writes __MaskSnapshotFailures__/case_N.{expected,actual,diff}.png and fails.
//    - Refresh after an intentional masking change:  make recordMaskSnapshots
//
//  The GPU goldens run the same scenarios, plus GPU-only ones appended after them, through
//  the GPU mirror capture path (inline masks, then the rect backstop) into __GPUMaskSnapshots__/:
//  make gpuMaskSnapshots / make recordGPUMaskSnapshots.

#if os(iOS) && canImport(SwiftUI) && TEST_MASK_SNAPSHOTS
    import Charts
    import CoreGraphics
    import Foundation
    @testable import PostHog
    import SwiftUI
    import Testing
    import UIKit

    /// Fraction of pixels allowed to differ before a mismatch is reported. The downsample
    /// + per-channel threshold already absorbs antialiasing jitter, so keep this tight:
    /// even a single small leaf mask regressing flips ~0.4% of the composite's pixels.
    private let diffTolerance = 0.001

    @Suite("Replay masking snapshots (PR #728)", .serialized)
    @MainActor
    struct PostHogMaskSnapshotTest {
        private static let secret = "SSN 123-45-6789"

        /// A real raster image so heuristic masking goes through the image path
        /// (`maskAllImages`). SF Symbols render as shape/drawing layers governed by the
        /// text heuristic instead, so they can't demonstrate `maskAllImages`.
        private static let sampleImage: UIImage = {
            let size = CGSize(width: 160, height: 120)
            let format = UIGraphicsImageRendererFormat()
            format.scale = 1
            return UIGraphicsImageRenderer(size: size, format: format).image { ctx in
                UIColor.systemTeal.setFill()
                ctx.fill(CGRect(origin: .zero, size: size))
                UIColor.white.setFill()
                ctx.cgContext.fillEllipse(in: CGRect(x: 40, y: 25, width: 55, height: 55))
                UIColor.systemOrange.setFill()
                ctx.fill(CGRect(x: 0, y: 88, width: size.width, height: 32))
            }
        }()

        /// A Canvas drawing a filled background, a shape and text into one RenderBox surface.
        @ViewBuilder private static var sampleCanvas: some View {
            if #available(iOS 15.0, *) {
                Canvas { context, size in
                    context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.yellow.opacity(0.3)))
                    context.fill(Path(ellipseIn: CGRect(x: 12, y: 12, width: 36, height: 36)), with: .color(.orange))
                    context.draw(Text(secret), at: CGPoint(x: size.width / 2 + 20, y: size.height / 2))
                }
                .frame(width: 280, height: 60)
            }
        }

        /// A small bar chart; Swift Charts draws through the same RenderBox surface.
        @ViewBuilder private static var sampleChart: some View {
            if #available(iOS 16.0, *) {
                Chart {
                    BarMark(x: .value("Month", "Jan"), y: .value("Balance", 1200))
                    BarMark(x: .value("Month", "Feb"), y: .value("Balance", 1850))
                    BarMark(x: .value("Month", "Mar"), y: .value("Balance", 1430))
                }
                .frame(width: 280, height: 160)
            }
        }

        /// One shared, installed Capture. Replay install is guarded by a process-wide
        /// static, so a second install() would no-op and leave its integration without a
        /// bound config; sharing one instance keeps config-driven masking working even if
        /// both @Tests run in the same process.
        private static let capture = Capture()

        #if RECORD_MASK_SNAPSHOTS
            private static let recordingEnabled = true
        #else
            private static let recordingEnabled = false
        #endif

        @Test(
            "record goldens — run via `make recordMaskSnapshots`, then review + commit",
            .enabled(if: recordingEnabled, "compile-gated (RECORD_MASK_SNAPSHOTS) — use `make recordMaskSnapshots`")
        )
        func recordGoldens() async throws {
            let capture = Self.capture
            try await record(.cpu, scenarios) { capture.composite(for: $0) }
        }

        @Test("committed goldens match the rendered masking output")
        func verifyGoldens() async throws {
            let capture = Self.capture
            try await verify(.cpu, scenarios) { capture.composite(for: $0) }
        }

        @Test(
            "record GPU goldens — run via `make recordGPUMaskSnapshots`, then review + commit",
            .enabled(if: recordingEnabled, "compile-gated (RECORD_MASK_SNAPSHOTS) — use `make recordGPUMaskSnapshots`")
        )
        func recordGPUGoldens() async throws {
            let capture = Self.capture
            try await record(.gpu, gpuScenarios) { try await capture.gpuComposite(for: $0) }
        }

        @Test("committed GPU goldens match the GPU capture path's masking output")
        func verifyGPUGoldens() async throws {
            let capture = Self.capture
            try await verify(.gpu, gpuScenarios) { try await capture.gpuComposite(for: $0) }
        }

        private func record(_ set: GoldenSet, _ scenarios: [Scenario],
                            render: (Scenario) async throws -> UIImage) async throws
        {
            for stale in set.goldenFilenames() where !scenarios.contains(where: { stale == "case_\($0.id).png" }) {
                try? FileManager.default.removeItem(at: set.directory.appendingPathComponent(stale))
            }
            for scenario in scenarios {
                try await write(render(scenario), to: set.goldenURL(scenario.id))
            }
            print("Recorded \(scenarios.count) mask goldens to \(set.directory.path) — review and commit.")
        }

        private func verify(_ set: GoldenSet, _ scenarios: [Scenario],
                            render: (Scenario) async throws -> UIImage) async throws
        {
            var failures: [String] = []

            for scenario in scenarios {
                let composite = try await render(scenario)

                guard let goldenData = try? Data(contentsOf: set.goldenURL(scenario.id)),
                      let golden = UIImage(data: goldenData)
                else {
                    failures.append("case \(scenario.id): no golden — run `\(set.recordCommand)`")
                    continue
                }

                let fraction = pixelDiffFraction(golden, composite)
                if fraction > diffTolerance {
                    let pct = String(format: "%.1f", fraction * 100)
                    try? write(golden, to: set.failureURL(scenario.id, "expected"))
                    try? write(composite, to: set.failureURL(scenario.id, "actual"))
                    if let diff = diffHeatmap(golden, composite) {
                        try? write(diff, to: set.failureURL(scenario.id, "diff"))
                    }
                    failures.append("case \(scenario.id) (\(scenario.title)): \(pct)% of pixels changed")
                }
            }

            let expected = Set(scenarios.map { "case_\($0.id).png" })
            for orphan in set.goldenFilenames() where !expected.contains(orphan) {
                failures.append("\(orphan): orphaned golden (no matching scenario) — run `\(set.recordCommand)`")
            }

            let report = failures.joined(separator: "\n  ")
            #expect(failures.isEmpty, "MASK SNAPSHOT REGRESSION:\n  \(report)")
        }

        // MARK: - Scenarios

        /// The harness forces every device-shaped input (window size, traits, safe area,
        /// appearance, locale), so scenario views render identically on any device — no
        /// per-scenario care needed. Views must still be *content*-deterministic: no
        /// `Date()`, randomness, `TimelineView`, `AsyncImage`, or running animations.
        private struct Scenario {
            /// Assigned from array order (1-based) — appending scenarios keeps existing
            /// goldens stable; inserting mid-list renumbers and forces a re-record.
            var id = 0
            let title: String
            /// The masking option(s) this case exercises — captioned onto the golden.
            let option: String
            /// What the masked panel should show, captioned so a reviewer can judge the
            /// golden without reading the scenario code.
            let expected: String
            let view: AnyView
            var scrollOffset: CGFloat = 0
            /// Per-scenario config; nil means the defaults (mask all text inputs + images).
            var configure: ((PostHogConfig) -> Void)?
            /// The view presents something on appear, and the GPU capture waits until it has presented.
            var presents = false

            init(title: String, option: String, expected: String,
                 scrollOffset: CGFloat = 0, presents: Bool = false, configure: ((PostHogConfig) -> Void)? = nil,
                 @ViewBuilder view: () -> some View)
            {
                self.title = title
                self.option = option
                self.expected = expected
                self.scrollOffset = scrollOffset
                self.presents = presents
                self.configure = configure
                self.view = AnyView(view())
            }
        }

        /// Heuristics off — scenarios demonstrating only the explicit
        /// `.postHogMask()`/`.postHogNoMask()` modifiers. With the defaults on,
        /// `maskAllTextInputs` masks ALL text (not just inputs), which would redact the
        /// "visible" reference labels and muddy what the explicit modifier contributes.
        private static func explicitMasksOnly(_ config: PostHogConfig) {
            config.sessionReplayConfig.maskAllTextInputs = false
            config.sessionReplayConfig.maskAllImages = false
        }

        private var scenarios: [Scenario] {
            var entries: [Scenario] = [
                // Explicit .postHogMask() — leaf vs container extent (heuristics off).
                Scenario(title: "Mask a Text",
                         option: ".postHogMask() on a Text",
                         expected: "secret masked; label above stays visible",
                         configure: Self.explicitMasksOnly)
                {
                    VStack(spacing: 16) {
                        Text("Visible label")
                        Text(Self.secret).postHogMask()
                    }
                },
                Scenario(title: "Mask an Image",
                         option: ".postHogMask() on an Image",
                         expected: "image masked; label above stays visible",
                         configure: Self.explicitMasksOnly)
                {
                    VStack(spacing: 16) {
                        Text("Visible label")
                        Image(systemName: "creditcard.fill").resizable().frame(width: 160, height: 100).postHogMask()
                    }
                },
                Scenario(title: "Mask a container",
                         option: ".postHogMask() on a container (full extent)",
                         expected: "one block over the whole container (title, secret, avatar)",
                         configure: Self.explicitMasksOnly)
                {
                    VStack(spacing: 8) {
                        Text("Row title")
                        Text(Self.secret)
                        Image(systemName: "person.crop.circle").resizable().frame(width: 60, height: 60)
                    }.padding().background(Color.yellow.opacity(0.3)).postHogMask()
                },
                // Heuristic config defaults.
                Scenario(title: "TextField",
                         option: "maskAllTextInputs (default)",
                         expected: "field masked; label ALSO masked — maskAllTextInputs redacts all text, not just inputs")
                {
                    VStack(spacing: 16) {
                        Text("Visible label")
                        TextField("card number", text: .constant("4242 4242 4242 4242"))
                            .textFieldStyle(.roundedBorder).padding(.horizontal, 40)
                    }
                },
                Scenario(title: "Image",
                         option: "maskAllImages (default)",
                         expected: "image masked; label ALSO masked (maskAllTextInputs default)")
                {
                    VStack(spacing: 16) {
                        Text("Visible label")
                        Image(uiImage: Self.sampleImage).resizable().frame(width: 160, height: 120)
                    }
                },
                // mask / noMask interaction (heuristics off).
                Scenario(title: "noMask child in masked container",
                         option: ".postHogMask() container + child .postHogNoMask() (fail-closed)",
                         expected: "whole container masked — child noMask does NOT punch a hole",
                         configure: Self.explicitMasksOnly)
                {
                    VStack(spacing: 8) {
                        Text("masked \(Self.secret)")
                        Text("EXEMPT should stay visible").postHogNoMask()
                    }.padding().background(Color.yellow.opacity(0.3)).postHogMask()
                },
                Scenario(title: "mask child in noMask container",
                         option: ".postHogNoMask() container + child .postHogMask()",
                         expected: "only the secret masked; exempt text visible",
                         configure: Self.explicitMasksOnly)
                {
                    VStack(spacing: 8) {
                        Text("exempt area visible")
                        Text(Self.secret).postHogMask()
                    }.padding().background(Color.green.opacity(0.2)).postHogNoMask()
                },
                // Per-row masking inside scrollable lists (leaf vs whole-row, and under scroll; heuristics off).
                Scenario(title: "List, per-row leaf mask (top)",
                         option: ".postHogMask() on each row's label",
                         expected: "each SSN masked hugging its label; row titles visible",
                         configure: Self.explicitMasksOnly)
                {
                    MaskScrollList(rowLevelMask: false)
                },
                Scenario(title: "List, per-row leaf mask (scrolled)",
                         option: ".postHogMask() on each row's label, scrolled",
                         expected: "masks track scrolled positions; row titles visible",
                         scrollOffset: 320,
                         configure: Self.explicitMasksOnly)
                {
                    MaskScrollList(rowLevelMask: false)
                },
                Scenario(title: "List, TextField rows (scrolled)",
                         option: "maskAllTextInputs in a list, scrolled",
                         expected: "fields masked; row titles ALSO masked (maskAllTextInputs redacts all text)",
                         scrollOffset: 320)
                {
                    MaskScrollList(useTextField: true)
                },
                Scenario(title: "List, whole-row mask (top)",
                         option: ".postHogMask() on the whole row",
                         expected: "each row masked full-width",
                         configure: Self.explicitMasksOnly)
                {
                    MaskScrollList(rowLevelMask: true)
                },
                Scenario(title: "List, whole-row mask (scrolled)",
                         option: ".postHogMask() on the whole row, scrolled",
                         expected: "full-width row masks track scrolled positions",
                         scrollOffset: 320,
                         configure: Self.explicitMasksOnly)
                {
                    MaskScrollList(rowLevelMask: true)
                },
                // Other text-input types under maskAllTextInputs.
                Scenario(title: "SecureField",
                         option: "maskAllTextInputs (SecureField)",
                         expected: "field masked; label ALSO masked (maskAllTextInputs redacts all text)")
                {
                    VStack(spacing: 16) {
                        Text("Visible label")
                        SecureField("password", text: .constant("hunter2-secret"))
                            .textFieldStyle(.roundedBorder).padding(.horizontal, 40)
                    }
                },
                Scenario(title: "Multiple text inputs",
                         option: "maskAllTextInputs (form)",
                         expected: "both fields and the heading masked")
                {
                    VStack(spacing: 12) {
                        Text("Payment")
                        TextField("name", text: .constant("Jane Appleseed"))
                            .textFieldStyle(.roundedBorder).padding(.horizontal, 40)
                        TextField("card", text: .constant("4242 4242 4242 4242"))
                            .textFieldStyle(.roundedBorder).padding(.horizontal, 40)
                    }
                },
                // Config toggles OFF — the item is no longer redacted.
                Scenario(title: "Text, text masking OFF",
                         option: "maskAllTextInputs = false",
                         expected: "nothing masked",
                         configure: { $0.sessionReplayConfig.maskAllTextInputs = false })
                {
                    VStack(spacing: 16) {
                        Text("Visible label")
                        Text(Self.secret)
                    }
                },
                Scenario(title: "Image, image masking OFF",
                         option: "maskAllImages = false",
                         expected: "image visible (nothing masked)",
                         configure: { $0.sessionReplayConfig.maskAllImages = false })
                {
                    VStack(spacing: 16) {
                        Image(uiImage: Self.sampleImage).resizable().frame(width: 160, height: 120)
                    }
                },
                // .postHogNoMask() opting a view out of the config default.
                Scenario(title: "noMask rescues text",
                         option: "maskAllTextInputs + .postHogNoMask()",
                         expected: "secret masked; banner visible via noMask")
                {
                    VStack(spacing: 16) {
                        Text("masked \(Self.secret)")
                        Text("PUBLIC banner text").postHogNoMask()
                    }
                },
                Scenario(title: "noMask rescues image",
                         option: "maskAllImages + .postHogNoMask()",
                         expected: "top image masked; bottom image visible via noMask")
                {
                    VStack(spacing: 16) {
                        Image(uiImage: Self.sampleImage).resizable().frame(width: 120, height: 90)
                        Image(uiImage: Self.sampleImage).resizable().frame(width: 120, height: 90).postHogNoMask()
                    }
                },
                // Disabled explicit mask, with the config default also off.
                Scenario(title: "Disabled explicit mask",
                         option: "maskAllTextInputs = false + .postHogMask(false)",
                         expected: "nothing masked",
                         configure: { $0.sessionReplayConfig.maskAllTextInputs = false })
                {
                    VStack(spacing: 16) {
                        Text("Visible label")
                        Text(Self.secret).postHogMask(false)
                    }
                },
                // Two independent explicit masks in one view.
                Scenario(title: "Sibling explicit masks",
                         option: "two sibling .postHogMask()",
                         expected: "card and pin masked separately; middle label visible",
                         configure: Self.explicitMasksOnly)
                {
                    VStack(spacing: 16) {
                        Text("card \(Self.secret)").postHogMask()
                        Text("Visible label")
                        Text("pin 4021").postHogMask()
                    }
                },
                // Controls: Button (UIButton) and Toggle (UISwitch) sensitivity.
                Scenario(title: "Button + Toggle",
                         option: "maskAllTextInputs (Button, Toggle)",
                         expected: "button title and toggle masked")
                {
                    VStack(spacing: 24) {
                        Button("Reveal \(Self.secret)") {}
                        Toggle("Biometric login", isOn: .constant(true)).padding(.horizontal, 40)
                    }
                },
                // Fail-closed: secure entry stays masked even with text masking off.
                Scenario(title: "SecureField, text masking OFF",
                         option: "maskAllTextInputs = false (SecureField)",
                         expected: "password STILL masked (secure entry is always sensitive); label visible",
                         configure: { $0.sessionReplayConfig.maskAllTextInputs = false })
                {
                    VStack(spacing: 16) {
                        Text("Visible label")
                        SecureField("password", text: .constant("hunter2-secret"))
                            .textFieldStyle(.roundedBorder).padding(.horizontal, 40)
                    }
                },
                // SF Symbols render as shape layers under the TEXT heuristic, never
                // reaching the image path — maskAllImages alone doesn't touch them.
                Scenario(title: "SF Symbol under maskAllImages",
                         option: "maskAllImages (SF Symbol)",
                         expected: "symbol NOT masked (text heuristic, off here); raster image below IS masked",
                         configure: { $0.sessionReplayConfig.maskAllTextInputs = false })
                {
                    VStack(spacing: 16) {
                        Text("Visible label")
                        Image(systemName: "creditcard.fill").resizable().frame(width: 120, height: 80)
                        Image(uiImage: Self.sampleImage).resizable().frame(width: 160, height: 120)
                    }
                },
                // Empty field: placeholder alone makes it sensitive (hasText(placeholder)).
                Scenario(title: "TextField, placeholder only",
                         option: "maskAllTextInputs (empty field)",
                         expected: "empty field masked via its placeholder; label ALSO masked (maskAllTextInputs)")
                {
                    VStack(spacing: 16) {
                        Text("Visible label")
                        TextField("Card number", text: .constant(""))
                            .textFieldStyle(.roundedBorder).padding(.horizontal, 40)
                    }
                },
                // Flattened content: .drawingGroup(), Canvas and Swift Charts draw into one
                // RenderBox surface that can't be inspected, so it is masked as one block.
                Scenario(title: "Text in a drawing group",
                         option: "maskAllTextInputs (.drawingGroup())",
                         expected: "whole drawing group masked as one block; label ALSO masked (maskAllTextInputs)")
                {
                    VStack(spacing: 16) {
                        Text("Visible label")
                        VStack(spacing: 8) {
                            Text(Self.secret)
                            Text("Card 4242 4242 4242 4242")
                        }
                        .padding()
                        .background(Color.yellow.opacity(0.3))
                        .drawingGroup()
                    }
                },
                Scenario(title: "Canvas",
                         option: "maskAllTextInputs (Canvas)",
                         expected: "whole Canvas masked as one block; label ALSO masked (maskAllTextInputs)")
                {
                    VStack(spacing: 16) {
                        Text("Visible label")
                        Self.sampleCanvas
                    }
                },
                Scenario(title: "Swift Chart",
                         option: "maskAllTextInputs (Swift Charts)",
                         expected: "whole chart masked as one block, axis labels and values included")
                {
                    VStack(spacing: 16) {
                        Text("Visible label")
                        Self.sampleChart
                    }
                },
                Scenario(title: "Swift Chart with postHogNoMask",
                         option: ".postHogNoMask() on a Chart",
                         expected: "chart stays visible; label above still masked (maskAllTextInputs)")
                {
                    VStack(spacing: 16) {
                        Text("Visible label")
                        Self.sampleChart.postHogNoMask()
                    }
                },
            ]
            for i in entries.indices {
                entries[i].id = i + 1
            }
            return entries
        }

        /// Every CPU scenario, then GPU-only ones numbered after them, so CPU ids never move.
        /// The GPU-only ones check what only inline masking does (chrome, paint order, backdrops,
        /// portals); on the CPU path each is one black rect, which the CPU goldens already cover.
        private var gpuScenarios: [Scenario] {
            let shared = scenarios
            var entries: [Scenario] = [
                Scenario(title: "Masked card with chrome",
                         option: ".postHogMask() on a card (background, circle, photo, text)",
                         expected: "card black, photo included (SwiftUI text's * rows draw in black over it); label above visible",
                         configure: Self.explicitMasksOnly)
                {
                    VStack(spacing: 16) {
                        Text("Visible label")
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Circle().fill(Color.purple).frame(width: 40, height: 40)
                                Text("Jane Appleseed")
                            }
                            Text(Self.secret)
                            Image(uiImage: Self.sampleImage).resizable().frame(width: 160, height: 120)
                        }
                        .padding()
                        .background(RoundedRectangle(cornerRadius: 12).fill(Color.yellow))
                        .postHogMask()
                    }
                },
                Scenario(title: "Button over masked text",
                         option: "button painted after a .postHogMask() Text (paint order)",
                         expected: "secret masked; the button on top stays visible",
                         configure: Self.explicitMasksOnly)
                {
                    ZStack {
                        Text(Self.secret).font(.system(size: 40, weight: .bold)).postHogMask()
                        Button {} label: {
                            Text("Visible button").foregroundColor(.white)
                                .padding(.horizontal, 16).padding(.vertical, 10)
                                .background(RoundedRectangle(cornerRadius: 8).fill(Color.blue))
                        }
                    }
                },
                Scenario(title: "Sheet over a masked card",
                         option: "medium sheet presented over a .postHogMask() extent",
                         expected: "card masked behind the sheet; the sheet's own content visible",
                         presents: true,
                         configure: Self.explicitMasksOnly)
                {
                    if #available(iOS 16.0, *) {
                        SheetOverMaskedCard(secret: Self.secret)
                    }
                },
                Scenario(title: "UIKit ph-no-capture card",
                         option: "accessibilityIdentifier ph-no-capture (UIKit)",
                         expected: "card one black block over its bounds, no chrome; label above visible",
                         configure: Self.explicitMasksOnly)
                {
                    VStack(spacing: 16) {
                        Text("Visible label")
                        NoCaptureCard(secret: Self.secret, image: Self.sampleImage).frame(width: 300, height: 200)
                    }
                },
                Scenario(title: "Photos black, one under a blur panel",
                         option: "maskAllImages, with a system blur panel over the second photo",
                         expected: "both photos black; the blur panel samples the black, not the photo",
                         configure: { $0.sessionReplayConfig.maskAllTextInputs = false })
                {
                    VStack(spacing: 24) {
                        Image(uiImage: Self.sampleImage).resizable().frame(width: 160, height: 120)
                        ZStack(alignment: .bottomTrailing) {
                            Image(uiImage: Self.sampleImage).resizable().frame(width: 160, height: 120)
                            BlurPanel().frame(width: 100, height: 60).offset(x: 40, y: 20)
                        }
                    }
                },
                Scenario(title: "Portal of masked text",
                         option: "ph-no-capture label shown elsewhere through a portal layer",
                         expected: "the portal's copy masked; ORIGINAL can't draw portals, so it shows the label in place",
                         configure: Self.explicitMasksOnly)
                {
                    VStack(spacing: 16) {
                        Text("Visible label")
                        PortalOfMaskedLabel(secret: Self.secret).frame(width: 300, height: 200)
                    }
                },
                Scenario(title: "Mask over part of a panel",
                         option: ".postHogMask() Text on a larger coloured panel (partial cover)",
                         expected: "secret masked inside its extent only; the orange panel and label around it visible",
                         configure: Self.explicitMasksOnly)
                {
                    VStack(spacing: 16) {
                        Text("Visible label")
                        Text(Self.secret).postHogMask()
                    }
                    .padding(32)
                    .background(RoundedRectangle(cornerRadius: 16).fill(Color.orange))
                },
            ]
            for i in entries.indices {
                entries[i].id = shared.count + i + 1
            }
            return shared + entries
        }

        // MARK: - Capture

        /// Renders a scenario to its captioned `[ original | masked ]` composite.
        ///
        /// Config (maskAllTextInputs/maskAllImages) is read live via the integration's
        /// bound SDK, so heuristic masking needs a real installed integration. Install is
        /// guarded by a process-wide static, so we install ONE SDK once and mutate its
        /// `sessionReplayConfig` per scenario rather than spinning up one per config.
        @MainActor
        private final class Capture {
            private let sdk: PostHogSDK
            private let integration = PostHogReplayIntegration()

            init() {
                let config = PostHogConfig(apiKey: "phc_maskSnapshotTest")
                config.disableReachabilityForTesting = true
                sdk = PostHogSDK.with(config)
                _ = integration.install(sdk)
            }

            func composite(for scenario: Scenario) -> UIImage {
                let (window, controller) = host(scenario)
                let original = render(controller.view)
                // Redact through the exact production painter (RRWireframe.maskImage) so the golden
                // reflects real replay output (scale-1), not hand-drawn rects.
                let rects = integration.collectMaskableRects(in: window) ?? []
                let masked = RRWireframe.maskImage(original, maskableWidgets: rects) ?? original
                return compose(scenario, original: original, masked: masked)
            }

            /// The frame the GPU path uploads (inline masks baked in, then the rect backstop) beside the original.
            func gpuComposite(for scenario: Scenario) async throws -> UIImage {
                let (window, controller) = host(scenario)
                defer {
                    window.rootViewController = nil
                    window.isHidden = true
                }
                if scenario.presents {
                    await waitUntil { controller.presentedViewController.map { $0.transitionCoordinator == nil } ?? false }
                    try #require(controller.presentedViewController != nil, "case \(scenario.id) didn't present")
                }
                // Its own mirror per scenario, so no text or image cache carries over between scenarios.
                let mirror = try #require(PostHogGPUMirrorCapture(), "the simulator has no Metal device")
                await withCheckedContinuation { continuation in
                    mirror.prewarm(size: window.bounds.size, scale: 1) { continuation.resume() }
                }

                let original = render(window)
                // The first frame draws masked text as bars; the golden is the next one, with `*` drawn.
                _ = try await gpuCapture(window, mirror: mirror)
                mirror.inlineMask.waitForTextDrawsForTesting()
                let captured = try await gpuCapture(window, mirror: mirror)
                let masked = try UIImage(cgImage: #require(captured.cgImage), scale: 1, orientation: .up)
                return compose(scenario, original: original, masked: masked, path: "GPU")
            }

            private func gpuCapture(_ window: UIWindow, mirror: PostHogGPUMirrorCapture) async throws -> UIImage {
                // nil while a masked view hasn't laid out yet or a transition runs, as production skips those frames.
                for _ in 0 ..< 20 {
                    window.layoutIfNeeded()
                    CATransaction.flush()
                    let result = await withCheckedContinuation { continuation in
                        integration.gpuPathCaptureForTesting(window: window, mirror: mirror, scale: 1) {
                            continuation.resume(returning: $0)
                        }
                    }
                    if let result { return result.image }
                    try await Task.sleep(nanoseconds: 50_000_000)
                }
                throw NSError(domain: "MaskSnapshot", code: 2,
                              userInfo: [NSLocalizedDescriptionKey: "the GPU path captured no frame"])
            }

            private func host(_ scenario: Scenario) -> (UIWindow, UIHostingController<AnyView>) {
                // Reset to the SDK defaults, then apply the scenario's override (if any).
                sdk.config.sessionReplayConfig.maskAllTextInputs = true
                sdk.config.sessionReplayConfig.maskAllImages = true
                scenario.configure?(sdk.config)

                let controller = UIHostingController(
                    rootView: AnyView(scenario.view.environment(\.locale, Locale(identifier: "en_US")))
                )
                let window = UIWindow(frame: CGRect(origin: .zero, size: CGSize(width: 390, height: 844)))
                window.rootViewController = controller
                forceDeviceIndependentEnvironment(window: window, controller: controller)
                window.makeKeyAndVisible()
                controller.view.frame = window.bounds
                settle(window)

                if scenario.scrollOffset > 0, let scroll = firstScrollView(in: window) {
                    scroll.setContentOffset(CGPoint(x: 0, y: scenario.scrollOffset), animated: false)
                    settle(window)
                }
                return (window, controller)
            }

            private func render(_ view: UIView) -> UIImage {
                let format = UIGraphicsImageRendererFormat()
                format.scale = 1 // fixed scale → device-independent pixel dimensions
                // layer.render(in:) draws the layer tree on the calling thread, so it works in a
                // hostless test bundle; drawHierarchy() needs an active window scene and renders blank.
                return UIGraphicsImageRenderer(bounds: view.bounds, format: format).image { ctx in
                    view.layer.render(in: ctx.cgContext)
                }
            }

            /// `path` names a capture path other than the default one, in the caption.
            private func compose(_ scenario: Scenario, original: UIImage, masked: UIImage, path: String? = nil) -> UIImage {
                let header: CGFloat = 148
                let gap: CGFloat = 8
                let panelW = original.size.width
                let size = CGSize(width: panelW * 2 + gap,
                                  height: header + max(original.size.height, masked.size.height))
                let replay = sdk.config.sessionReplayConfig
                let configLine = "config: maskAllTextInputs=\(replay.maskAllTextInputs)  maskAllImages=\(replay.maskAllImages)"
                    + (path.map { "  path=\($0)" } ?? "")
                let format = UIGraphicsImageRendererFormat()
                format.scale = 1
                return UIGraphicsImageRenderer(size: size, format: format).image { ctx in
                    UIColor.white.setFill()
                    ctx.fill(CGRect(origin: .zero, size: size))

                    draw("\(scenario.id). \(scenario.title)", at: CGPoint(x: 16, y: 14),
                         font: .boldSystemFont(ofSize: 22), color: .black, maxWidth: size.width - 32)
                    draw(scenario.option, at: CGPoint(x: 16, y: 46),
                         font: .systemFont(ofSize: 16), color: .darkGray, maxWidth: size.width - 32)
                    draw(configLine, at: CGPoint(x: 16, y: 72),
                         font: .monospacedSystemFont(ofSize: 13, weight: .regular), color: .gray,
                         maxWidth: size.width - 32)
                    draw("expect: \(scenario.expected)", at: CGPoint(x: 16, y: 94),
                         font: .italicSystemFont(ofSize: 15), color: .systemBlue, maxWidth: size.width - 32)
                    draw("ORIGINAL", at: CGPoint(x: 16, y: 124), font: .systemFont(ofSize: 12), color: .gray, maxWidth: panelW)
                    draw(path.map { "MASKED (\($0) capture, as uploaded)" } ?? "MASKED (redacted in replay)", at: CGPoint(x: panelW + gap + 16, y: 124),
                         font: .systemFont(ofSize: 12), color: .gray, maxWidth: panelW)

                    original.draw(at: CGPoint(x: 0, y: header))
                    masked.draw(at: CGPoint(x: panelW + gap, y: header))
                    UIColor.systemGray4.setFill()
                    ctx.fill(CGRect(x: panelW, y: header, width: gap, height: size.height - header))
                }
            }

            private func draw(_ text: String, at point: CGPoint, font: UIFont, color: UIColor, maxWidth: CGFloat) {
                (text as NSString).draw(
                    in: CGRect(x: point.x, y: point.y, width: maxWidth, height: font.lineHeight + 4),
                    withAttributes: [.font: font, .foregroundColor: color]
                )
            }
        }

        // MARK: - Pixel comparison

        private func rgbaBytes(_ image: UIImage) -> (bytes: [UInt8], width: Int, height: Int)? {
            guard let cg = image.cgImage else { return nil }
            let width = cg.width, height = cg.height
            var bytes = [UInt8](repeating: 0, count: width * height * 4)
            // The buffer pointer is only valid inside withUnsafeMutableBytes, so the
            // context must be created AND drawn into within the closure.
            let drawn = bytes.withUnsafeMutableBytes { buffer -> Bool in
                guard let ctx = CGContext(
                    data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
                    bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                ) else { return false }
                ctx.draw(cg, in: CGRect(x: 0, y: 0, width: width, height: height))
                return true
            }
            return drawn ? (bytes, width, height) : nil
        }

        /// Whether the RGB channels at byte offset `o` differ beyond the antialiasing threshold.
        private func pixelChanged(_ a: [UInt8], _ b: [UInt8], at o: Int) -> Bool {
            let threshold: Int16 = 16
            return abs(Int16(a[o]) - Int16(b[o])) > threshold
                || abs(Int16(a[o + 1]) - Int16(b[o + 1])) > threshold
                || abs(Int16(a[o + 2]) - Int16(b[o + 2])) > threshold
        }

        private func pixelDiffFraction(_ a: UIImage, _ b: UIImage) -> Double {
            guard let pa = rgbaBytes(a), let pb = rgbaBytes(b) else { return 1 }
            guard pa.width == pb.width, pa.height == pb.height else { return 1 }
            // Compare 2x-downsampled: sub-pixel text antialiasing (the only cross-device
            // render difference) averages out, while a missing/moved mask block survives
            // at full strength — so the tolerance stays tight for real drift.
            let da = downsample2x(pa), db = downsample2x(pb)
            var differing = 0
            let pixelCount = da.width * da.height
            for i in 0 ..< pixelCount where pixelChanged(da.bytes, db.bytes, at: i * 4) {
                differing += 1
            }
            return pixelCount == 0 ? 1 : Double(differing) / Double(pixelCount)
        }

        private func downsample2x(
            _ p: (bytes: [UInt8], width: Int, height: Int)
        ) -> (bytes: [UInt8], width: Int, height: Int) {
            let w = p.width / 2, h = p.height / 2
            var out = [UInt8](repeating: 0, count: w * h * 4)
            for y in 0 ..< h {
                for x in 0 ..< w {
                    let o = (y * w + x) * 4
                    let i0 = (y * 2 * p.width + x * 2) * 4
                    let i1 = i0 + 4
                    let i2 = i0 + p.width * 4
                    let i3 = i2 + 4
                    for c in 0 ..< 4 {
                        let sum = Int(p.bytes[i0 + c]) + Int(p.bytes[i1 + c])
                            + Int(p.bytes[i2 + c]) + Int(p.bytes[i3 + c])
                        out[o + c] = UInt8(sum / 4)
                    }
                }
            }
            return (out, w, h)
        }

        private func diffHeatmap(_ a: UIImage, _ b: UIImage) -> UIImage? {
            guard let pa = rgbaBytes(a), let pb = rgbaBytes(b),
                  pa.width == pb.width, pa.height == pb.height else { return nil }
            var out = pa.bytes
            for i in 0 ..< (pa.width * pa.height) {
                let o = i * 4
                if pixelChanged(pa.bytes, pb.bytes, at: o) {
                    out[o] = 255
                    out[o + 1] = 0
                    out[o + 2] = 0
                    out[o + 3] = 255
                } else {
                    // Dim the unchanged background so changed pixels pop in the artifact.
                    out[o] /= 3
                    out[o + 1] /= 3
                    out[o + 2] /= 3
                }
            }
            // Data owns a copy of the pixels, so the CGImage can't outlive its backing
            // store (a bitmap context over `out` would reference the array's buffer
            // beyond its guaranteed lifetime).
            guard let provider = CGDataProvider(data: Data(out) as CFData),
                  let cg = CGImage(
                      width: pa.width, height: pa.height, bitsPerComponent: 8, bitsPerPixel: 32,
                      bytesPerRow: pa.width * 4, space: CGColorSpaceCreateDeviceRGB(),
                      bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                      provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent
                  ) else { return nil }
            return UIImage(cgImage: cg)
        }

        // MARK: - Paths & IO

        /// Where one capture path's goldens and failure artifacts live.
        private struct GoldenSet {
            static let cpu = GoldenSet("MaskSnapshot", recordCommand: "make recordMaskSnapshots")
            static let gpu = GoldenSet("GPUMaskSnapshot", recordCommand: "make recordGPUMaskSnapshots")

            let directory: URL
            let failureDirectory: URL
            let recordCommand: String

            private init(_ name: String, recordCommand: String) {
                let tests = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
                directory = tests.appendingPathComponent("__\(name)s__")
                failureDirectory = tests.appendingPathComponent("__\(name)Failures__")
                self.recordCommand = recordCommand
            }

            func goldenURL(_ id: Int) -> URL {
                directory.appendingPathComponent("case_\(id).png")
            }

            func goldenFilenames() -> [String] {
                let contents = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
                return contents.filter { $0.hasPrefix("case_") && $0.hasSuffix(".png") }
            }

            func failureURL(_ id: Int, _ kind: String) -> URL {
                failureDirectory.appendingPathComponent("case_\(id).\(kind).png")
            }
        }

        private func write(_ image: UIImage, to url: URL) throws {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true
            )
            guard let data = image.pngData() else {
                throw NSError(domain: "MaskSnapshot", code: 1,
                              userInfo: [NSLocalizedDescriptionKey: "pngData() failed for \(url.lastPathComponent)"])
            }
            try data.write(to: url)
        }
    }

    /// A masked card, with a medium sheet presented over its lower part on appear.
    @available(iOS 16.0, *)
    private struct SheetOverMaskedCard: View {
        let secret: String
        @State private var isPresented = false

        var body: some View {
            VStack(spacing: 16) {
                Text("Visible label")
                VStack(alignment: .leading, spacing: 8) {
                    Text("Card holder")
                    Text(secret)
                    Color.clear.frame(height: 400)
                }
                .padding()
                .background(RoundedRectangle(cornerRadius: 12).fill(Color.yellow))
                .postHogMask()
                Spacer()
            }
            .padding()
            .sheet(isPresented: $isPresented) {
                VStack(spacing: 16) {
                    Text("Sheet content").font(.headline)
                    Text("PUBLIC sheet text")
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

    /// A UIKit ph-no-capture card: coloured, bordered chrome around a label and a photo.
    private struct NoCaptureCard: UIViewRepresentable {
        let secret: String
        let image: UIImage

        func makeUIView(context _: Context) -> UIView {
            let card = UIView()
            card.accessibilityIdentifier = "ph-no-capture"
            card.backgroundColor = .systemYellow
            card.layer.cornerRadius = 12
            card.layer.borderWidth = 2
            card.layer.borderColor = UIColor.systemOrange.cgColor
            let label = UILabel(frame: CGRect(x: 16, y: 16, width: 268, height: 30))
            label.text = secret
            card.addSubview(label)
            let photo = UIImageView(frame: CGRect(x: 16, y: 60, width: 160, height: 120))
            photo.image = image
            card.addSubview(photo)
            return card
        }

        func updateUIView(_: UIView, context _: Context) {}
    }

    private struct BlurPanel: UIViewRepresentable {
        func makeUIView(context _: Context) -> UIVisualEffectView {
            UIVisualEffectView(effect: UIBlurEffect(style: .systemMaterial))
        }

        func updateUIView(_: UIVisualEffectView, context _: Context) {}
    }

    /// A ph-no-capture label, shown again below it through a portal layer.
    private struct PortalOfMaskedLabel: UIViewRepresentable {
        let secret: String

        func makeUIView(context _: Context) -> UIView {
            let root = UIView()
            let source = UIView(frame: CGRect(x: 0, y: 0, width: 300, height: 60))
            source.accessibilityIdentifier = "ph-no-capture"
            let label = UILabel(frame: CGRect(x: 10, y: 10, width: 280, height: 40))
            label.text = secret
            source.addSubview(label)
            root.addSubview(source)
            // A private class, as in the GPU capture suites: only the render server draws portals.
            if let portalClass = NSClassFromString("CAPortalLayer") as? CALayer.Type {
                let portal = portalClass.init()
                portal.frame = CGRect(x: 0, y: 120, width: 300, height: 60)
                portal.masksToBounds = true
                portal.setValue(source.layer, forKey: "sourceLayer")
                portal.setValue(false, forKey: "hidesSourceLayer")
                portal.setValue(false, forKey: "matchesPosition")
                portal.setValue(false, forKey: "matchesTransform")
                portal.setValue(0, forKey: "sourceContextId")
                root.layer.addSublayer(portal)
            }
            return root
        }

        func updateUIView(_: UIView, context _: Context) {}
    }
#endif
