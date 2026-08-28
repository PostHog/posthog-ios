//
//  End-to-end masking-coverage tests. Each scenario hosts a SwiftUI view, collects
//  the redaction rects the replay snapshot path would produce via
//  `collectMaskableRects(in:)`, and asserts the privacy property geometrically
//  ("a masked region covers X") — robust to font jitter and OS rendering engines.
//
//  The integration is built bare (no config), so the heuristic
//  maskAllTextInputs/maskAllImages layer scan stays off and the collected rects are
//  exactly the explicit `postHogMask()`/`postHogNoMask()` reporters. The iOS-26
//  layer-scan logic is covered separately in PostHogMaskingCharacterizationTest;
//  rendered-pixel coverage lives in PostHogMaskSnapshotTest.

#if os(iOS) && canImport(SwiftUI)
    import Foundation
    @testable import PostHog
    import SwiftUI
    import Testing
    import UIKit

    @Suite("Replay masking scenarios (PR #728)", .serialized)
    @MainActor
    struct PostHogMaskScenarioTest {
        private static let windowSize = CGSize(width: 390, height: 844)
        private static let secret = "SSN 123-45-6789"

        // MARK: - Harness

        /// Hosts `view`, forces a layout/render pass, and returns the live window.
        /// Caller retains the returned `Host` for the duration of the test so the
        /// reporter views stay registered and attached to a window.
        private func host(_ view: some View) -> Host {
            let controller = UIHostingController(
                rootView: AnyView(view.environment(\.locale, Locale(identifier: "en_US")))
            )
            let window = UIWindow(frame: CGRect(origin: .zero, size: Self.windowSize))
            window.rootViewController = controller
            forceDeviceIndependentEnvironment(window: window, controller: controller)
            window.makeKeyAndVisible()
            controller.view.frame = window.bounds
            settle(window)
            return Host(window: window, controller: controller)
        }

        /// The rects the replay snapshot path would redact for `window` right now.
        /// `collectMaskableRects` returns nil only when a reporter hasn't been laid out
        /// yet (fail-closed skip); after `settle` that shouldn't happen, and a stray nil
        /// collapses to `[]`, which every scenario's "covers X" assertion then flags.
        private func maskRects(_ host: Host) -> [CGRect] {
            PostHogReplayIntegration().collectMaskableRects(in: host.window) ?? []
        }

        // MARK: - Explicit-mask leaf vs container extent

        @Test("case 1: postHogMask on a Text hugs the label (not the whole screen)")
        func maskOnText() throws {
            let host = host(VStack(spacing: 16) {
                Text("Visible label")
                Text(Self.secret).postHogMask()
            })
            let rects = maskRects(host)

            #expect(rects.count == 1)
            let rect = try #require(rects.first)
            // Leaf mask: single line, well short of full screen width (no over-collection).
            #expect(rect.height < 60)
            #expect(rect.width < Self.windowSize.width * 0.9)
            #expect(!rect.isEmpty)
        }

        @Test("case 2: postHogMask on an Image covers the image frame")
        func maskOnImage() throws {
            let host = host(VStack(spacing: 16) {
                Text("Visible label")
                Image(systemName: "creditcard.fill")
                    .resizable().frame(width: 160, height: 100)
                    .postHogMask()
            })
            let rects = maskRects(host)

            #expect(rects.count == 1)
            let rect = try #require(rects.first)
            // Reporter overlays the 160x100 image frame.
            #expect(abs(rect.width - 160) < 40)
            #expect(abs(rect.height - 100) < 40)
        }

        @Test("case 3: postHogMask on a container covers its full extent")
        func maskOnContainer() throws {
            let host = host(
                VStack(spacing: 8) {
                    Text("Row title")
                    Text(Self.secret)
                    Image(systemName: "person.crop.circle").resizable().frame(width: 60, height: 60)
                }
                .padding()
                .background(Color.yellow.opacity(0.3))
                .postHogMask()
            )
            let rects = maskRects(host)

            #expect(rects.count == 1)
            // Full-extent: spans the stacked title + secret + 60pt image + padding,
            // far taller than any single leaf line.
            #expect(try #require(rects.first).height > 90)
        }

        // MARK: - mask / noMask interaction (fail-closed)

        @Test("case 6: noMask child inside a masked container stays masked (fail-closed)")
        func noMaskChildInsideMaskedContainer() throws {
            let host = host(
                VStack(spacing: 8) {
                    Text("masked \(Self.secret)")
                    Text("EXEMPT should stay visible").postHogNoMask()
                }
                .padding()
                .background(Color.yellow.opacity(0.3))
                .postHogMask()
            )
            let rects = maskRects(host)

            // The container mask is not cleared by the child's postHogNoMask:
            // one rect covering the whole container.
            #expect(rects.count == 1)
            #expect(try #require(rects.first).height > 40)
        }

        @Test("case 7: masked child inside a noMask container stays masked")
        func maskChildInsideNoMaskContainer() throws {
            let host = host(
                VStack(spacing: 8) {
                    Text("exempt area visible")
                    Text(Self.secret).postHogMask()
                }
                .padding()
                .background(Color.green.opacity(0.2))
                .postHogNoMask()
            )
            let rects = maskRects(host)

            // The explicit mask on the secret wins over the surrounding noMask.
            #expect(rects.count == 1)
            let rect = try #require(rects.first)
            #expect(rect.height < 60)
            #expect(rect.width < Self.windowSize.width * 0.9)
        }

        // MARK: - Lists: leaf per-row vs whole-row extent

        @Test("case 8: per-row leaf masks hug each SSN label")
        func perRowLeafMasks() {
            let host = host(MaskScrollList(rowLevelMask: false))
            let rects = maskRects(host)

            #expect(rects.count >= 6, "several visible rows masked")
            // Leaf masks hug the trailing SSN label — never the full row width.
            for rect in rects {
                #expect(rect.width < Self.windowSize.width * 0.5)
            }
        }

        @Test("case 11: whole-row masks span the full row width")
        func wholeRowMasks() {
            let host = host(MaskScrollList(rowLevelMask: true))
            let rects = maskRects(host)

            #expect(rects.count >= 6, "several visible rows masked")
            // Whole-row masks cover the full-width HStack (documented full-extent change).
            for rect in rects {
                #expect(rect.width > Self.windowSize.width * 0.7)
            }
        }

        // MARK: - Live-rect tracking under scroll

        @Test("case 9: per-row masks track new positions after scrolling")
        func perRowMasksTrackScroll() {
            assertMasksTrackScroll(rowLevelMask: false)
        }

        @Test("case 12: whole-row masks track new positions after scrolling")
        func wholeRowMasksTrackScroll() {
            assertMasksTrackScroll(rowLevelMask: true)
        }

        private func assertMasksTrackScroll(rowLevelMask: Bool) {
            let host = host(MaskScrollList(rowLevelMask: rowLevelMask))
            let before = maskRects(host)
            #expect(!before.isEmpty)

            guard let scroll = firstScrollView(in: host.window) else {
                Issue.record("no UIScrollView in hosted list")
                return
            }
            scroll.setContentOffset(CGPoint(x: 0, y: 320), animated: false)
            settle(host.window)
            let after = maskRects(host)

            #expect(!after.isEmpty)
            // Registry reads live geometry at capture time, so scrolling moves the
            // redaction rects — the set of positions must differ from before.
            #expect(Set(before.map(\.minY)) != Set(after.map(\.minY)))
        }
    }

    /// Spin layout + main run loop so SwiftUI commits its UIKit representation
    /// (reporter overlays are realized and register on `didMoveToWindow`).
    /// Shared with PostHogMaskSnapshotTest.
    @MainActor
    func settle(_ window: UIWindow) {
        for _ in 0 ..< 3 {
            window.setNeedsLayout()
            window.layoutIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        }
    }

    /// Shared with PostHogMaskSnapshotTest.
    func firstScrollView(in view: UIView) -> UIScrollView? {
        if let scroll = view as? UIScrollView { return scroll }
        for sub in view.subviews {
            if let found = firstScrollView(in: sub) { return found }
        }
        return nil
    }

    /// Pin every device-model-dependent render input (appearance, safe area, traits) so
    /// the pixel and geometric harnesses match on any device running the pinned OS (see
    /// Makefile mask-snapshot notes). safeAreaRegions (16.4) and traitOverrides (17)
    /// always apply on the iOS-26 sim; the guards exist only for the iOS-13 deployment target.
    @MainActor
    func forceDeviceIndependentEnvironment(window: UIWindow, controller: UIHostingController<AnyView>) {
        window.overrideUserInterfaceStyle = .light
        if #available(iOS 16.4, *) {
            controller.safeAreaRegions = []
        }
        if #available(iOS 17.0, *) {
            controller.traitOverrides.displayScale = 3
            controller.traitOverrides.preferredContentSizeCategory = .large
            controller.traitOverrides.layoutDirection = .leftToRight
            controller.traitOverrides.userInterfaceIdiom = .phone
            controller.traitOverrides.displayGamut = .SRGB
        }
    }

    @MainActor
    private struct Host {
        let window: UIWindow
        let controller: UIHostingController<AnyView>
    }

    // Ported from the PR #728 verification harness (resources/MaskTestScenarios.swift),
    // trimmed to what the CI assertions need: async ScrollViewReader scroll is driven
    // deterministically from the test via UIScrollView.contentOffset instead.
    struct MaskScrollList: View {
        var rowLevelMask: Bool = false
        var useTextField: Bool = false
        private let rows = Array(1 ... 20)

        private func row(_ k: Int) -> some View {
            HStack {
                Text("Row \(k)")
                Spacer()
                if useTextField {
                    TextField("", text: .constant("SSN 000-00-\(String(format: "%04d", k))"))
                        .multilineTextAlignment(.trailing).frame(width: 150)
                } else {
                    Text("SSN 000-00-\(String(format: "%04d", k))")
                        .postHogMask(!rowLevelMask)
                }
            }
            .padding(.horizontal, 20).padding(.vertical, 10)
            .background(k % 2 == 0 ? Color.gray.opacity(0.12) : Color.clear)
        }

        var body: some View {
            ScrollView {
                VStack(spacing: 6) {
                    ForEach(rows, id: \.self) { k in
                        if rowLevelMask {
                            row(k).postHogMask()
                        } else {
                            row(k)
                        }
                    }
                }
            }
        }
    }

    @Suite("settleVerdict identity pairing")
    struct PostHogSettleVerdictTest {
        private typealias MaskedRegion = PostHogReplayIntegration.MaskedRegion

        private func region(_ owner: AnyObject, _ rect: CGRect) -> MaskedRegion {
            MaskedRegion(owner, rect: rect)
        }

        @Test("displacement exactly at tolerance settles")
        func exactlyAtTolerance() {
            let a = NSObject()
            let before = [region(a, CGRect(x: 0, y: 0, width: 100, height: 20))]
            let after = [region(a, CGRect(x: 2, y: 0, width: 100, height: 20))]
            let verdict = PostHogReplayIntegration.settleVerdict(before: before, after: after)
            #expect(verdict.band == .still)
            #expect(verdict.inflatedRects == nil)
        }

        @Test("just over tolerance drifts")
        func justOverTolerance() {
            let a = NSObject()
            let before = [region(a, CGRect(x: 0, y: 0, width: 100, height: 20))]
            let after = [region(a, CGRect(x: 2.1, y: 0, width: 100, height: 20))]
            let verdict = PostHogReplayIntegration.settleVerdict(before: before, after: after)
            #expect(verdict.band == .drift)
        }

        @Test("displacement exactly at drift budget drifts")
        func exactlyAtDriftBudget() {
            let a = NSObject()
            let before = [region(a, CGRect(x: 0, y: 0, width: 100, height: 20))]
            let after = [region(a, CGRect(x: 100, y: 0, width: 100, height: 20))]
            let verdict = PostHogReplayIntegration.settleVerdict(before: before, after: after)
            #expect(verdict.band == .drift)
        }

        @Test("just over drift budget is motion")
        func justOverDriftBudget() {
            let a = NSObject()
            let before = [region(a, CGRect(x: 0, y: 0, width: 100, height: 20))]
            let after = [region(a, CGRect(x: 100.1, y: 0, width: 100, height: 20))]
            let verdict = PostHogReplayIntegration.settleVerdict(before: before, after: after)
            #expect(verdict.band == .motion)
            #expect(verdict.inflatedRects == nil)
        }

        @Test("nil before is motion")
        func nilBefore() {
            let a = NSObject()
            let after = [region(a, CGRect(x: 0, y: 0, width: 100, height: 20))]
            let verdict = PostHogReplayIntegration.settleVerdict(before: nil, after: after)
            #expect(verdict.band == .motion)
        }

        @Test("nil after is motion")
        func nilAfter() {
            let a = NSObject()
            let before = [region(a, CGRect(x: 0, y: 0, width: 100, height: 20))]
            let verdict = PostHogReplayIntegration.settleVerdict(before: before, after: nil)
            #expect(verdict.band == .motion)
        }

        @Test("count mismatch is motion")
        func countMismatch() {
            let a = NSObject()
            let b = NSObject()
            let before = [region(a, CGRect(x: 0, y: 0, width: 100, height: 20))]
            let after = [
                region(a, CGRect(x: 0, y: 0, width: 100, height: 20)),
                region(b, CGRect(x: 0, y: 100, width: 100, height: 20)),
            ]
            let verdict = PostHogReplayIntegration.settleVerdict(before: before, after: after)
            #expect(verdict.band == .motion)
        }

        @Test("same count but a different owner set is motion (index-pairing regression)")
        func differentOwnerSet() {
            let a = NSObject()
            let b = NSObject()
            let before = [region(a, CGRect(x: 0, y: 0, width: 100, height: 20))]
            let after = [region(b, CGRect(x: 0, y: 0, width: 100, height: 20))]
            let verdict = PostHogReplayIntegration.settleVerdict(before: before, after: after)
            #expect(verdict.band == .motion)
        }

        @Test("permuted order with identical per-owner geometry settles")
        func permutedOrderIdenticalGeometry() {
            let a = NSObject()
            let b = NSObject()
            let before = [
                region(a, CGRect(x: 0, y: 0, width: 100, height: 20)),
                region(b, CGRect(x: 0, y: 100, width: 100, height: 20)),
            ]
            // Same owners, same rects, but traversal order swapped (e.g. cell recycling).
            let after = [
                region(b, CGRect(x: 0, y: 100, width: 100, height: 20)),
                region(a, CGRect(x: 0, y: 0, width: 100, height: 20)),
            ]
            let verdict = PostHogReplayIntegration.settleVerdict(before: before, after: after)
            #expect(verdict.band == .still)
        }

        @Test("duplicate owner in a sample is motion, not a trap")
        func duplicateOwnerFailsClosed() {
            let a = NSObject()
            let b = NSObject()
            // One object can match two maskable heuristics and be collected twice.
            let before = [
                region(a, CGRect(x: 0, y: 0, width: 100, height: 20)),
                region(a, CGRect(x: 0, y: 0, width: 100, height: 20)),
            ]
            let after = [
                region(a, CGRect(x: 0, y: 0, width: 100, height: 20)),
                region(b, CGRect(x: 0, y: 100, width: 100, height: 20)),
            ]
            let verdict = PostHogReplayIntegration.settleVerdict(before: before, after: after)
            #expect(verdict.band == .motion)
        }

        @Test("duplicate owner in the after sample is motion, not a trap")
        func duplicateOwnerInAfterFailsClosed() {
            let a = NSObject()
            let b = NSObject()
            // Counts match and every `after` entry resolves to a known owner, but `a`
            // appears twice — b's disappearance would go unnoticed if this weren't caught.
            let before = [
                region(a, CGRect(x: 0, y: 0, width: 100, height: 20)),
                region(b, CGRect(x: 0, y: 100, width: 100, height: 20)),
            ]
            let after = [
                region(a, CGRect(x: 0, y: 0, width: 100, height: 20)),
                region(a, CGRect(x: 0, y: 0, width: 100, height: 20)),
            ]
            let verdict = PostHogReplayIntegration.settleVerdict(before: before, after: after)
            #expect(verdict.band == .motion)
        }

        /// Ordering the two thresholds wrong makes `.drift` unreachable, which silently drops the
        /// swept-region inflation with nothing else failing.
        @Test("the still tolerance stays below the drift budget")
        func thresholdsAreOrdered() {
            let a = NSObject()
            let before = [region(a, CGRect(x: 0, y: 0, width: 100, height: 20))]
            let justOverTolerance = [region(a, CGRect(x: 3, y: 0, width: 100, height: 20))]
            #expect(PostHogReplayIntegration.settleVerdict(before: before, after: justOverTolerance).band == .drift)
        }

        @Test("only motion drops to the presentation-tree renderer")
        func bandsPickRenderer() {
            #expect(PostHogReplayIntegration.SettleBand.still.usesFidelity)
            #expect(PostHogReplayIntegration.SettleBand.drift.usesFidelity)
            #expect(!PostHogReplayIntegration.SettleBand.motion.usesFidelity)
        }

        @Test("empty arrays settle as still")
        func emptyArraysStill() {
            let verdict = PostHogReplayIntegration.settleVerdict(before: [], after: [])
            #expect(verdict.band == .still)
            #expect(verdict.inflatedRects == nil)
        }

        @Test("drift inflation covers the swept region and is ordered like after")
        func driftInflationCoversSweepInAfterOrder() throws {
            let a = NSObject()
            let b = NSObject()
            let before = [
                region(a, CGRect(x: 0, y: 0, width: 100, height: 20)),
                region(b, CGRect(x: 0, y: 100, width: 100, height: 20)),
            ]
            // b drifts by 5pt; a is stationary. after is in swapped order vs before, so
            // ordering must be recovered from `owner`, not index.
            let after = [
                region(b, CGRect(x: 0, y: 105, width: 100, height: 20)),
                region(a, CGRect(x: 0, y: 0, width: 100, height: 20)),
            ]
            let verdict = PostHogReplayIntegration.settleVerdict(before: before, after: after)
            #expect(verdict.band == .drift)
            let inflated = try #require(verdict.inflatedRects)
            #expect(inflated.count == 2)

            // inflated[0] pairs with after[0] (b): swept from y=100 through y=105, plus a
            // sixteenth of the 5pt displacement as lead.
            let bInflated = inflated[0]
            #expect(bInflated.minY <= 100)
            #expect(bInflated.maxY >= 125.31)

            // inflated[1] pairs with after[1] (a): stationary, so it collapses to a's rect.
            #expect(inflated[1] == CGRect(x: 0, y: 0, width: 100, height: 20))
        }

        @Test("drift inflation also covers a full settle window behind the older sample")
        func driftInflationCoversTrailBehindBefore() throws {
            let a = NSObject()
            let before = [region(a, CGRect(x: 0, y: 100, width: 100, height: 20))]
            // a drifts by 5pt.
            let after = [region(a, CGRect(x: 0, y: 105, width: 100, height: 20))]
            let verdict = PostHogReplayIntegration.settleVerdict(before: before, after: after)
            #expect(verdict.band == .drift)
            let inflated = try #require(verdict.inflatedRects)

            // The displayed pixels can lag `before` by a full settle window if the render
            // pipeline is deeper than one window — the trail pads a position never sampled.
            #expect(inflated[0].minY <= 95)
            #expect(inflated[0].maxY >= 125.31)
        }

        @Test("swept union covers both sample positions, in after order")
        func sweptRectsCoversBothSamplesInAfterOrder() throws {
            let a = NSObject()
            let b = NSObject()
            let before = [
                region(a, CGRect(x: 0, y: 0, width: 100, height: 20)),
                region(b, CGRect(x: 0, y: 100, width: 100, height: 20)),
            ]
            // b moves; a is stationary. after is in swapped order vs before, so
            // ordering must be recovered from `owner`, not index.
            let after = [
                region(b, CGRect(x: 0, y: 130, width: 100, height: 20)),
                region(a, CGRect(x: 0, y: 0, width: 100, height: 20)),
            ]
            let swept = try #require(PostHogReplayIntegration.sweptRects(before: before, after: after))
            #expect(swept.count == 2)

            // swept[0] pairs with after[0] (b): union of y=100..120 and y=130..150.
            #expect(swept[0] == CGRect(x: 0, y: 100, width: 100, height: 50))

            // swept[1] pairs with after[1] (a): stationary, so it collapses to a's rect.
            #expect(swept[1] == CGRect(x: 0, y: 0, width: 100, height: 20))
        }

        @Test("nil before makes sweptRects nil")
        func sweptRectsNilBefore() {
            let a = NSObject()
            let after = [region(a, CGRect(x: 0, y: 0, width: 100, height: 20))]
            #expect(PostHogReplayIntegration.sweptRects(before: nil, after: after) == nil)
        }

        @Test("nil after makes sweptRects nil")
        func sweptRectsNilAfter() {
            let a = NSObject()
            let before = [region(a, CGRect(x: 0, y: 0, width: 100, height: 20))]
            #expect(PostHogReplayIntegration.sweptRects(before: before, after: nil) == nil)
        }

        @Test("an owner that appears mid-render is covered, not dropped")
        func sweptRectsCountMismatch() throws {
            let a = NSObject()
            let b = NSObject()
            let before = [region(a, CGRect(x: 0, y: 0, width: 100, height: 20))]
            let after = [
                region(a, CGRect(x: 0, y: 0, width: 100, height: 20)),
                region(b, CGRect(x: 0, y: 100, width: 100, height: 20)),
            ]
            // b appeared mid-render, so it was displayed for part of the window and is covered
            // rather than costing the whole frame.
            let swept = try #require(PostHogReplayIntegration.sweptRects(before: before, after: after))
            #expect(swept == [
                CGRect(x: 0, y: 0, width: 100, height: 20),
                CGRect(x: 0, y: 100, width: 100, height: 20),
            ])
        }

        @Test("duplicate owner in before makes sweptRects nil")
        func sweptRectsDuplicateOwnerInBefore() {
            let a = NSObject()
            let b = NSObject()
            let before = [
                region(a, CGRect(x: 0, y: 0, width: 100, height: 20)),
                region(a, CGRect(x: 0, y: 0, width: 100, height: 20)),
            ]
            let after = [
                region(a, CGRect(x: 0, y: 0, width: 100, height: 20)),
                region(b, CGRect(x: 0, y: 100, width: 100, height: 20)),
            ]
            #expect(PostHogReplayIntegration.sweptRects(before: before, after: after) == nil)
        }

        @Test("duplicate owner in after makes sweptRects nil")
        func sweptRectsDuplicateOwnerInAfter() {
            let a = NSObject()
            let b = NSObject()
            let before = [
                region(a, CGRect(x: 0, y: 0, width: 100, height: 20)),
                region(b, CGRect(x: 0, y: 100, width: 100, height: 20)),
            ]
            let after = [
                region(a, CGRect(x: 0, y: 0, width: 100, height: 20)),
                region(a, CGRect(x: 0, y: 0, width: 100, height: 20)),
            ]
            #expect(PostHogReplayIntegration.sweptRects(before: before, after: after) == nil)
        }

        @Test("a fully recycled owner set covers both samples, not nil")
        func sweptRectsDisjointOwnerSet() throws {
            let a = NSObject()
            let b = NSObject()
            let before = [region(a, CGRect(x: 0, y: 0, width: 100, height: 20))]
            let after = [region(b, CGRect(x: 0, y: 200, width: 100, height: 20))]
            // Neither owner can be paired, but both were on screen during the render window:
            // `after` entries come first, then the ones that went away.
            let swept = try #require(PostHogReplayIntegration.sweptRects(before: before, after: after))
            #expect(swept == [
                CGRect(x: 0, y: 200, width: 100, height: 20),
                CGRect(x: 0, y: 0, width: 100, height: 20),
            ])
        }

        @Test("a stationary owner's swept rect equals its rect unchanged")
        func sweptRectsStationaryOwnerUnchanged() throws {
            let a = NSObject()
            let rect = CGRect(x: 10, y: 20, width: 100, height: 20)
            let before = [region(a, rect)]
            let after = [region(a, rect)]
            let swept = try #require(PostHogReplayIntegration.sweptRects(before: before, after: after))
            #expect(swept == [rect])
        }
    }
#endif
