//
//  PostHogMaskSnapshotTest.swift
//  PostHog
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
//        → on mismatch writes __MaskSnapshotFailures__/case_N.{actual,diff}.png and fails.
//    - Refresh after an intentional masking change:  make recordMaskSnapshots

#if os(iOS) && canImport(SwiftUI) && TEST_MASK_SNAPSHOTS
    import CoreGraphics
    import Foundation
    @testable import PostHog
    import SwiftUI
    import Testing
    import UIKit

    /// Fraction of pixels allowed to differ before a mismatch is reported — absorbs
    /// sub-pixel antialiasing jitter; a real masking change dwarfs it.
    private let diffTolerance = 0.02

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
        func recordGoldens() throws {
            let capture = Self.capture
            for scenario in scenarios {
                try write(capture.composite(for: scenario), to: Self.goldenURL(scenario.id))
            }
            print("Recorded \(scenarios.count) mask goldens to \(Self.snapshotDir.path) — review and commit.")
        }

        @Test("committed goldens match the rendered masking output")
        func verifyGoldens() throws {
            let capture = Self.capture
            var failures: [String] = []

            for scenario in scenarios {
                let composite = capture.composite(for: scenario)

                guard let goldenData = try? Data(contentsOf: Self.goldenURL(scenario.id)),
                      let golden = UIImage(data: goldenData)
                else {
                    failures.append("case \(scenario.id): no golden — run `make recordMaskSnapshots`")
                    continue
                }

                let fraction = pixelDiffFraction(golden, composite)
                if fraction > diffTolerance {
                    let pct = String(format: "%.1f", fraction * 100)
                    try? write(composite, to: Self.failureURL(scenario.id, "actual"))
                    if let diff = diffHeatmap(golden, composite) {
                        try? write(diff, to: Self.failureURL(scenario.id, "diff"))
                    }
                    failures.append("case \(scenario.id) (\(scenario.title)): \(pct)% of pixels changed")
                }
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
            let id: Int
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
            [
                // Explicit .postHogMask() — leaf vs container extent (heuristics off).
                Scenario(id: 1, title: "Mask a Text", option: ".postHogMask() on a Text",
                         expected: "secret masked; label above stays visible",
                         view: AnyView(VStack(spacing: 16) {
                             Text("Visible label")
                             Text(Self.secret).postHogMask()
                         }), configure: Self.explicitMasksOnly),
                Scenario(id: 2, title: "Mask an Image", option: ".postHogMask() on an Image",
                         expected: "image masked; label above stays visible",
                         view: AnyView(VStack(spacing: 16) {
                             Text("Visible label")
                             Image(systemName: "creditcard.fill").resizable().frame(width: 160, height: 100).postHogMask()
                         }), configure: Self.explicitMasksOnly),
                Scenario(id: 3, title: "Mask a container", option: ".postHogMask() on a container (full extent)",
                         expected: "one block over the whole container (title, secret, avatar)",
                         view: AnyView(VStack(spacing: 8) {
                             Text("Row title")
                             Text(Self.secret)
                             Image(systemName: "person.crop.circle").resizable().frame(width: 60, height: 60)
                         }.padding().background(Color.yellow.opacity(0.3)).postHogMask()), configure: Self.explicitMasksOnly),
                // Heuristic config defaults.
                Scenario(id: 4, title: "TextField", option: "maskAllTextInputs (default)",
                         expected: "field masked; label ALSO masked — maskAllTextInputs redacts all text, not just inputs",
                         view: AnyView(VStack(spacing: 16) {
                             Text("Visible label")
                             TextField("card number", text: .constant("4242 4242 4242 4242"))
                                 .textFieldStyle(.roundedBorder).padding(.horizontal, 40)
                         })),
                Scenario(id: 5, title: "Image", option: "maskAllImages (default)",
                         expected: "image masked; label ALSO masked (maskAllTextInputs default)",
                         view: AnyView(VStack(spacing: 16) {
                             Text("Visible label")
                             Image(uiImage: Self.sampleImage).resizable().frame(width: 160, height: 120)
                         })),
                // mask / noMask interaction (heuristics off).
                Scenario(id: 6, title: "noMask child in masked container",
                         option: ".postHogMask() container + child .postHogNoMask() (fail-closed)",
                         expected: "whole container masked — child noMask does NOT punch a hole",
                         view: AnyView(VStack(spacing: 8) {
                             Text("masked \(Self.secret)")
                             Text("EXEMPT should stay visible").postHogNoMask()
                         }.padding().background(Color.yellow.opacity(0.3)).postHogMask()), configure: Self.explicitMasksOnly),
                Scenario(id: 7, title: "mask child in noMask container",
                         option: ".postHogNoMask() container + child .postHogMask()",
                         expected: "only the secret masked; exempt text visible",
                         view: AnyView(VStack(spacing: 8) {
                             Text("exempt area visible")
                             Text(Self.secret).postHogMask()
                         }.padding().background(Color.green.opacity(0.2)).postHogNoMask()), configure: Self.explicitMasksOnly),
                // Per-row masking inside scrollable lists (leaf vs whole-row, and under scroll; heuristics off).
                Scenario(id: 8, title: "List, per-row leaf mask (top)", option: ".postHogMask() on each row's label",
                         expected: "each SSN masked hugging its label; row titles visible",
                         view: AnyView(MaskScrollList(rowLevelMask: false)), configure: Self.explicitMasksOnly),
                Scenario(id: 9, title: "List, per-row leaf mask (scrolled)",
                         option: ".postHogMask() on each row's label, scrolled",
                         expected: "masks track scrolled positions; row titles visible",
                         view: AnyView(MaskScrollList(rowLevelMask: false)), scrollOffset: 320,
                         configure: Self.explicitMasksOnly),
                Scenario(id: 10, title: "List, TextField rows (scrolled)", option: "maskAllTextInputs in a list, scrolled",
                         expected: "fields masked; row titles ALSO masked (maskAllTextInputs redacts all text)",
                         view: AnyView(MaskScrollList(useTextField: true)), scrollOffset: 320),
                Scenario(id: 11, title: "List, whole-row mask (top)", option: ".postHogMask() on the whole row",
                         expected: "each row masked full-width",
                         view: AnyView(MaskScrollList(rowLevelMask: true)), configure: Self.explicitMasksOnly),
                Scenario(id: 12, title: "List, whole-row mask (scrolled)", option: ".postHogMask() on the whole row, scrolled",
                         expected: "full-width row masks track scrolled positions",
                         view: AnyView(MaskScrollList(rowLevelMask: true)), scrollOffset: 320,
                         configure: Self.explicitMasksOnly),
                // Other text-input types under maskAllTextInputs.
                Scenario(id: 13, title: "SecureField", option: "maskAllTextInputs (SecureField)",
                         expected: "field masked; label ALSO masked (maskAllTextInputs redacts all text)",
                         view: AnyView(VStack(spacing: 16) {
                             Text("Visible label")
                             SecureField("password", text: .constant("hunter2-secret"))
                                 .textFieldStyle(.roundedBorder).padding(.horizontal, 40)
                         })),
                Scenario(id: 14, title: "Multiple text inputs", option: "maskAllTextInputs (form)",
                         expected: "both fields and the heading masked",
                         view: AnyView(VStack(spacing: 12) {
                             Text("Payment")
                             TextField("name", text: .constant("Jane Appleseed"))
                                 .textFieldStyle(.roundedBorder).padding(.horizontal, 40)
                             TextField("card", text: .constant("4242 4242 4242 4242"))
                                 .textFieldStyle(.roundedBorder).padding(.horizontal, 40)
                         })),
                // Config toggles OFF — the item is no longer redacted.
                Scenario(id: 15, title: "Text, text masking OFF", option: "maskAllTextInputs = false",
                         expected: "nothing masked",
                         view: AnyView(VStack(spacing: 16) {
                             Text("Visible label")
                             Text(Self.secret)
                         }), configure: { $0.sessionReplayConfig.maskAllTextInputs = false }),
                Scenario(id: 16, title: "Image, image masking OFF", option: "maskAllImages = false",
                         expected: "image visible (nothing masked)",
                         view: AnyView(VStack(spacing: 16) {
                             Image(uiImage: Self.sampleImage).resizable().frame(width: 160, height: 120)
                         }), configure: { $0.sessionReplayConfig.maskAllImages = false }),
                // .postHogNoMask() opting a view out of the config default.
                Scenario(id: 17, title: "noMask rescues text", option: "maskAllTextInputs + .postHogNoMask()",
                         expected: "secret masked; banner visible via noMask",
                         view: AnyView(VStack(spacing: 16) {
                             Text("masked \(Self.secret)")
                             Text("PUBLIC banner text").postHogNoMask()
                         })),
                Scenario(id: 18, title: "noMask rescues image", option: "maskAllImages + .postHogNoMask()",
                         expected: "top image masked; bottom image visible via noMask",
                         view: AnyView(VStack(spacing: 16) {
                             Image(uiImage: Self.sampleImage).resizable().frame(width: 120, height: 90)
                             Image(uiImage: Self.sampleImage).resizable().frame(width: 120, height: 90).postHogNoMask()
                         })),
                // Disabled explicit mask, with the config default also off.
                Scenario(id: 19, title: "Disabled explicit mask", option: "maskAllTextInputs = false + .postHogMask(false)",
                         expected: "nothing masked",
                         view: AnyView(VStack(spacing: 16) {
                             Text("Visible label")
                             Text(Self.secret).postHogMask(false)
                         }), configure: { $0.sessionReplayConfig.maskAllTextInputs = false }),
                // Two independent explicit masks in one view.
                Scenario(id: 20, title: "Sibling explicit masks", option: "two sibling .postHogMask()",
                         expected: "card and pin masked separately; middle label visible",
                         view: AnyView(VStack(spacing: 16) {
                             Text("card \(Self.secret)").postHogMask()
                             Text("Visible label")
                             Text("pin 4021").postHogMask()
                         }), configure: Self.explicitMasksOnly),
                // Controls: Button (UIButton) and Toggle (UISwitch) sensitivity.
                Scenario(id: 21, title: "Button + Toggle", option: "maskAllTextInputs (Button, Toggle)",
                         expected: "button title and toggle masked",
                         view: AnyView(VStack(spacing: 24) {
                             Button("Reveal \(Self.secret)") {}
                             Toggle("Biometric login", isOn: .constant(true)).padding(.horizontal, 40)
                         })),
            ]
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

                let original = render(controller.view)
                let masked = paintingBlack(integration.collectMaskableRects(in: window) ?? [],
                                           over: original, in: window.bounds)
                return compose(scenario, original: original, masked: masked)
            }

            private func settle(_ window: UIWindow) {
                for _ in 0 ..< 3 {
                    window.setNeedsLayout()
                    window.layoutIfNeeded()
                    RunLoop.main.run(until: Date().addingTimeInterval(0.05))
                }
            }

            private func firstScrollView(in view: UIView) -> UIScrollView? {
                if let scroll = view as? UIScrollView { return scroll }
                for sub in view.subviews {
                    if let found = firstScrollView(in: sub) { return found }
                }
                return nil
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

            private func paintingBlack(_ rects: [CGRect], over image: UIImage, in bounds: CGRect) -> UIImage {
                let format = UIGraphicsImageRendererFormat()
                format.scale = 1
                return UIGraphicsImageRenderer(bounds: bounds, format: format).image { ctx in
                    image.draw(in: bounds)
                    UIColor.black.setFill()
                    for rect in rects {
                        ctx.fill(rect)
                    }
                }
            }

            private func compose(_ scenario: Scenario, original: UIImage, masked: UIImage) -> UIImage {
                let header: CGFloat = 148
                let gap: CGFloat = 8
                let panelW = original.size.width
                let size = CGSize(width: panelW * 2 + gap,
                                  height: header + max(original.size.height, masked.size.height))
                let replay = sdk.config.sessionReplayConfig
                let configLine = "config: maskAllTextInputs=\(replay.maskAllTextInputs)  maskAllImages=\(replay.maskAllImages)"
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
                    draw("MASKED (redacted in replay)", at: CGPoint(x: panelW + gap + 16, y: 124),
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

        private static let snapshotDir = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().appendingPathComponent("__MaskSnapshots__")
        private static let failureDir = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().appendingPathComponent("__MaskSnapshotFailures__")

        private static func goldenURL(_ id: Int) -> URL {
            snapshotDir.appendingPathComponent("case_\(id).png")
        }

        private static func failureURL(_ id: Int, _ kind: String) -> URL {
            failureDir.appendingPathComponent("case_\(id).\(kind).png")
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
#endif
