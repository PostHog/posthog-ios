#if os(iOS)
    @testable import PostHog
    import Testing
    import UIKit

    @Suite("Replay screenshot failed draws")
    @MainActor
    struct PostHogScreenshotFailedDrawTest {
        @Test("a drawHierarchy render that reports no image data yields no screenshot")
        func failedDrawHierarchyIsDropped() {
            // Never shown, so there is no committed frame for drawHierarchy to copy and it reports false.
            let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 50, height: 50))
            window.backgroundColor = .green

            #expect(window.toImage(preferFidelityRenderer: true) == nil)
            #expect(window.toImage(afterScreenUpdates: true) == nil)
            #expect(window.toImage(preferFidelityRenderer: false) != nil)
        }
    }
#endif
