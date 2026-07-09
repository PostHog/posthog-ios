#if os(iOS)
    import Foundation
    @testable import PostHog
    import Testing

    @Suite("Screenshot mode unchanged-frame dedup")
    class PostHogReplayScreenshotDedupTests {
        @Test("Skips an unchanged image when no other snapshot data is pending")
        func skipsUnchangedImage() {
            #expect(PostHogReplayIntegration.shouldSkipUnchangedScreenshot(
                imageHash: 42,
                lastImageHash: 42,
                hasPendingSnapshotData: false
            ))
        }

        @Test("Sends a changed image")
        func sendsChangedImage() {
            #expect(!PostHogReplayIntegration.shouldSkipUnchangedScreenshot(
                imageHash: 43,
                lastImageHash: 42,
                hasPendingSnapshotData: false
            ))
        }

        @Test("Never skips while a meta event (or other data) is pending")
        func sendsWhenSnapshotDataPending() {
            #expect(!PostHogReplayIntegration.shouldSkipUnchangedScreenshot(
                imageHash: 42,
                lastImageHash: 42,
                hasPendingSnapshotData: true
            ))
        }

        @Test("Never skips when there is no image hash (wireframe mode)")
        func sendsWhenNoImageHash() {
            #expect(!PostHogReplayIntegration.shouldSkipUnchangedScreenshot(
                imageHash: nil,
                lastImageHash: 42,
                hasPendingSnapshotData: false
            ))
        }

        @Test("Sends the first image, when there is no previous hash")
        func sendsFirstImage() {
            #expect(!PostHogReplayIntegration.shouldSkipUnchangedScreenshot(
                imageHash: 42,
                lastImageHash: nil,
                hasPendingSnapshotData: false
            ))
        }
    }
#endif
