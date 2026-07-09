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
#endif
