#if os(iOS)
    import Foundation
    @testable import PostHog
    import Testing
    import UIKit

    @Suite("Screenshot mode unchanged-frame dedup")
    class PostHogReplayScreenshotDedupTests {
        struct DedupCase: CustomTestStringConvertible {
            let name: String
            let imageHash: Int?
            let lastImageHash: Int?
            let hasPendingSnapshotData: Bool
            let expectedSkip: Bool

            var testDescription: String { name }
        }

        @Test("Screenshot dedup decision", arguments: [
            DedupCase(
                name: "skips an unchanged image when no other snapshot data is pending",
                imageHash: 42, lastImageHash: 42, hasPendingSnapshotData: false, expectedSkip: true
            ),
            DedupCase(
                name: "sends a changed image",
                imageHash: 43, lastImageHash: 42, hasPendingSnapshotData: false, expectedSkip: false
            ),
            DedupCase(
                name: "never skips while a meta event (or other data) is pending",
                imageHash: 42, lastImageHash: 42, hasPendingSnapshotData: true, expectedSkip: false
            ),
            DedupCase(
                name: "never skips when there is no image hash (wireframe mode)",
                imageHash: nil, lastImageHash: 42, hasPendingSnapshotData: false, expectedSkip: false
            ),
            DedupCase(
                name: "sends the first image, when there is no previous hash",
                imageHash: 42, lastImageHash: nil, hasPendingSnapshotData: false, expectedSkip: false
            ),
        ])
        func screenshotDedupDecision(_ testCase: DedupCase) {
            let skip = PostHogReplayIntegration.shouldSkipUnchangedScreenshot(
                imageHash: testCase.imageHash,
                lastImageHash: testCase.lastImageHash,
                hasPendingSnapshotData: testCase.hasPendingSnapshotData
            )
            #expect(skip == testCase.expectedSkip)
        }
    }
    /// Wireframe mode is the default (`screenshotMode == false`) and never populates `base64`, so the
    /// change verdict has to come from the serialised tree or the idle backoff can never engage.
    @Suite("Wireframe mode unchanged-frame dedup")
    class PostHogReplayWireframeDedupTests {
        /// A small two-node tree. `id` mimics `UIView.hash`, which is what the production walk assigns.
        private func tree(id: Int = 111, childId: Int = 222, text: String = "Balance", posX: Int = 0) -> RRWireframe {
            let child = RRWireframe()
            child.id = childId
            child.type = "text"
            child.text = text
            child.posX = posX
            child.width = 120
            child.height = 20

            let style = RRStyle()
            style.backgroundColor = "#ffffff"
            child.style = style

            let root = RRWireframe()
            root.id = id
            root.type = "div"
            root.width = 320
            root.height = 480
            root.childWireframes = [child]
            return root
        }

        private func hash(_ wireframe: RRWireframe) -> Int? {
            PostHogReplayIntegration.frameHash(for: wireframe.toDict())
        }

        /// The capture path's sequence: verdict, then the backoff note, then the remembered hash.
        /// Returns whether the frame would have been sent.
        private func render(
            _ wireframe: RRWireframe,
            lastHash: inout Int?,
            backoff: PostHogReplayCaptureBackoff
        ) -> Bool {
            let verdict = PostHogReplayIntegration.frameVerdict(
                wireframeDict: wireframe.toDict(),
                lastImageHash: lastHash,
                hasPendingSnapshotData: false
            )
            guard !verdict.unchanged else {
                backoff.noteFrame(unchanged: true)
                return false
            }
            lastHash = verdict.hash
            backoff.noteFrame(unchanged: false)
            return true
        }

        @Test("an unchanged wireframe tree engages the backoff after three unchanged frames")
        func unchangedTreeEngagesBackoff() {
            let backoff = PostHogReplayCaptureBackoff()
            backoff.setBaseInterval(10)
            var lastHash: Int?

            // No previous hash, so the opening frame is always sent.
            #expect(render(tree(), lastHash: &lastHash, backoff: backoff))

            for _ in 0 ..< 2 {
                #expect(render(tree(), lastHash: &lastHash, backoff: backoff) == false)
            }
            #expect(backoff.isInBackoffForTesting == false)

            #expect(render(tree(), lastHash: &lastHash, backoff: backoff) == false)
            #expect(backoff.isInBackoffForTesting)
            #expect(backoff.shouldCapture() == false)
        }

        @Test("a changed wireframe tree restores the full rate")
        func changedTreeResetsBackoff() {
            let backoff = PostHogReplayCaptureBackoff()
            backoff.setBaseInterval(10)
            var lastHash: Int?
            for _ in 0 ..< 4 {
                _ = render(tree(), lastHash: &lastHash, backoff: backoff)
            }
            #expect(backoff.isInBackoffForTesting)

            #expect(render(tree(text: "Balance: 12"), lastHash: &lastHash, backoff: backoff))
            #expect(backoff.isInBackoffForTesting == false)
            #expect(backoff.shouldCapture())
        }

        @Test("the hash ignores view identity, which changes without the screen changing")
        func hashIgnoresViewIdentity() {
            // Both ids differ: a recreated view or a rebuilt subtree draws the same pixels.
            #expect(hash(tree(id: 111, childId: 222)) == hash(tree(id: 999, childId: 888)))
        }

        @Test("the hash still sees content, geometry, style and child order")
        func hashSeesVisibleChanges() {
            let base = hash(tree())
            #expect(base != hash(tree(text: "Balance: 12")))
            #expect(base != hash(tree(posX: 40)))

            let restyled = tree()
            restyled.childWireframes?.first?.style?.backgroundColor = "#000000"
            #expect(base != hash(restyled))

            let reordered = tree()
            let second = RRWireframe()
            second.id = 333
            second.type = "text"
            second.text = "Total"
            reordered.childWireframes?.append(second)
            let forward = hash(reordered)
            reordered.childWireframes?.reverse()
            #expect(forward != hash(reordered))
        }

        @Test("the same tree hashes the same every time it is serialised")
        func hashIsStableAcrossCaptures() {
            let hashes = Set((0 ..< 20).map { _ in hash(tree()) })
            #expect(hashes.count == 1)
        }

        @Test("screenshot mode keeps hashing the encoded image")
        func screenshotModeHashesBase64() {
            let wireframe = tree()
            wireframe.base64 = "encoded-image"
            #expect(hash(wireframe) == "encoded-image".hashValue)
        }
    }

    @Suite("Replay capture interval")
    struct PostHogReplayCaptureIntervalTests {
        @Test("throttleDelay is clamped so trailing delivery cannot spin the run loop", arguments: [
            (0, PostHogReplayCaptureBackoff.minimumBaseInterval),
            (-1, PostHogReplayCaptureBackoff.minimumBaseInterval),
            (0.01, PostHogReplayCaptureBackoff.minimumBaseInterval),
            (.nan, 1),
            (.infinity, 1),
            (-.infinity, 1),
            (0.5, 0.5),
        ] as [(TimeInterval, TimeInterval)])
        func captureInterval(_ throttleDelay: TimeInterval, _ expected: TimeInterval) {
            #expect(PostHogReplayIntegration.captureInterval(throttleDelay: throttleDelay) == expected)
        }
    }

    @Suite("Backed-off structure change")
    struct PostHogReplayStructureChangeTests {
        private func engagedBackoff(base: TimeInterval = 1) -> PostHogReplayCaptureBackoff {
            let backoff = PostHogReplayCaptureBackoff()
            backoff.setBaseInterval(base)
            for _ in 0 ..< 3 {
                backoff.noteFrame(unchanged: true)
            }
            return backoff
        }

        /// The first walk inside the idle interval only records the baseline.
        private func backedOff(structure: Int) -> PostHogReplayCaptureBackoff {
            let backoff = engagedBackoff()
            #expect(backoff.shouldCapture(structure: { structure }) == false)
            return backoff
        }

        @Test("a changed structure captures at once, and the changed frame leaves backoff")
        func changedStructureCaptures() {
            let backoff = backedOff(structure: 1)

            #expect(backoff.shouldCapture(structure: { 2 }))
            backoff.noteFrame(unchanged: false)
            #expect(backoff.isInBackoffForTesting == false)
        }

        @Test("an unchanged structure keeps waiting for the idle interval")
        func sameStructureWaits() {
            let backoff = backedOff(structure: 1)

            #expect(backoff.shouldCapture(structure: { 1 }) == false)
            #expect(backoff.isInBackoffForTesting)
        }

        @Test("a structure change the render cannot see costs one frame and keeps backing off")
        func invisibleStructureChangeKeepsBackoff() {
            let backoff = backedOff(structure: 1)
            let interval = backoff.idleIntervalForTesting

            #expect(backoff.shouldCapture(structure: { 2 }))
            backoff.noteFrame(unchanged: true)
            #expect(backoff.isInBackoffForTesting)
            #expect(backoff.idleIntervalForTesting > interval)
            #expect(backoff.shouldCapture(structure: { 2 }) == false)
        }

        @Test("a toast appearing right after an idle render still captures")
        func changeAfterIdleRenderCaptures() {
            let backoff = engagedBackoff(base: PostHogReplayCaptureBackoff.minimumBaseInterval)
            #expect(backoff.shouldCapture(structure: { 1 }) == false)
            Thread.sleep(forTimeInterval: PostHogReplayCaptureBackoff.minimumBaseInterval * 2)

            #expect(backoff.shouldCapture(structure: { 1 }))
            #expect(backoff.shouldCapture(structure: { 2 }))
        }

        @Test("when not backed off the structure is never walked")
        func notBackedOffSkipsWalk() {
            let backoff = PostHogReplayCaptureBackoff()
            backoff.setBaseInterval(10)
            var walks = 0
            let walk: () -> Int? = {
                walks += 1
                return 1
            }

            #expect(backoff.shouldCapture(structure: walk))
            backoff.noteFrame(unchanged: true)
            #expect(backoff.shouldCapture(structure: walk))
            #expect(walks == 0)
        }
    }

    @Suite("Structure fingerprint")
    @MainActor
    struct PostHogReplayStructureFingerprintTests {
        private func screen() -> (root: UIView, label: UILabel) {
            let root = UIView(frame: CGRect(x: 0, y: 0, width: 320, height: 640))
            let label = UILabel(frame: CGRect(x: 16, y: 16, width: 200, height: 20))
            label.text = "Loading"
            root.addSubview(label)
            return (root, label)
        }

        private func fingerprint(_ view: UIView, nodeLimit: Int = PostHogReplayIntegration.structureFingerprintNodeLimit) -> Int {
            PostHogReplayIntegration.structureFingerprint(of: view, nodeLimit: nodeLimit)
        }

        @Test("a toast appearing and leaving changes the fingerprint each time")
        func toastChangesFingerprint() {
            let (root, _) = screen()
            let idle = fingerprint(root)

            let toast = UIView(frame: CGRect(x: 16, y: 560, width: 288, height: 48))
            root.addSubview(toast)
            let showing = fingerprint(root)
            #expect(showing != idle)

            toast.removeFromSuperview()
            #expect(fingerprint(root) == idle)
        }

        @Test("label text, visibility and geometry change the fingerprint")
        func visibleChangesChangeFingerprint() {
            let (root, label) = screen()
            let base = fingerprint(root)

            label.text = "Done"
            #expect(fingerprint(root) != base)
            label.text = "Loading"

            label.isHidden = true
            #expect(fingerprint(root) != base)
            label.isHidden = false

            label.frame.origin.y = 40
            #expect(fingerprint(root) != base)
        }

        @Test("churn inside a hidden subtree does not change the fingerprint")
        func hiddenSubtreeIgnored() {
            let (root, label) = screen()
            label.isHidden = true
            let base = fingerprint(root)

            label.text = "Done"
            label.addSubview(UIView())
            #expect(fingerprint(root) == base)
        }

        @Test("the walk stops at the node limit")
        func walkIsBounded() {
            let (root, label) = screen()
            let rootOnly = fingerprint(root, nodeLimit: 1)
            let withLabel = fingerprint(root, nodeLimit: 2)

            label.text = "Done"
            #expect(fingerprint(root, nodeLimit: 1) == rootOnly)
            #expect(fingerprint(root, nodeLimit: 2) != withLabel)
        }
    }
#endif
