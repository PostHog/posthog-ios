#if os(iOS)
    import Foundation
    @testable import PostHog
    import Testing

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
#endif
