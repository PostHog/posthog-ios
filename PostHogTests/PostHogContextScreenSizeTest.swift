//
//  PostHogContextScreenSizeTest.swift
//  PostHogTests
//
//  Created by Anna Garcia on 23/09/2026.
//

#if os(iOS)
    import Foundation
    @testable import PostHog
    import Testing
    import UIKit

    /// iPhone Duo, in points: the outer screen while folded, the inner one while unfolded.
    private enum DuoScreen {
        static let folded = CGSize(width: 466, height: 678)
        static let unfolded = CGSize(width: 669, height: 951)
    }

    /// A size the test can change under the context, standing in for the app's window. `nil` is a
    /// window that cannot be measured, as when the app is suspending.
    private final class ScreenSizeStub: @unchecked Sendable {
        private let lock = NSLock()
        private var size: CGSize?

        init(_ size: CGSize?) {
            self.size = size
        }

        var current: CGSize? {
            get { lock.withLock { size } }
            set { lock.withLock { size = newValue } }
        }
    }

    @Suite("Screen size follows a resized window", .serialized, .resetsGlobalState)
    @MainActor
    struct PostHogContextScreenSizeTest {
        private func getSut(_ stub: ScreenSizeStub) -> PostHogContext {
            let sut = PostHogContext(nil)
            sut.screenSizeOverride = { stub.current }
            return sut
        }

        private func reportedSize(_ context: PostHogContext) -> CGSize? {
            let properties = context.dynamicContext()
            guard let width = properties["$screen_width"] as? Float,
                  let height = properties["$screen_height"] as? Float
            else {
                return nil
            }
            return CGSize(width: CGFloat(width), height: CGFloat(height))
        }

        @Test("reports the window size a new key window brings")
        func reportsSizeOnKeyWindowChange() async {
            await withMockedClock { _ in
                let stub = ScreenSizeStub(DuoScreen.folded)
                let sut = getSut(stub)
                #expect(reportedSize(sut) == DuoScreen.folded)

                stub.current = DuoScreen.unfolded
                NotificationCenter.default.post(name: UIWindow.didBecomeKeyNotification, object: nil)

                #expect(reportedSize(sut) == DuoScreen.unfolded)
            }
        }

        /// Unfolding resizes the window without rotating the device or changing the key window.
        @Test("reports the new size on the first event after a resize that fires no notification")
        func reportsSizeAfterSilentResize() async {
            await withMockedClock { clock in
                let stub = ScreenSizeStub(DuoScreen.folded)
                let sut = getSut(stub)
                #expect(reportedSize(sut) == DuoScreen.folded)

                stub.current = DuoScreen.unfolded
                #expect(reportedSize(sut) == DuoScreen.folded)

                clock.date += 2
                #expect(reportedSize(sut) == DuoScreen.unfolded)
            }
        }

        @Test("reports the measured size on rotation, without reordering it to the device orientation")
        func reportsMeasuredSizeOnRotation() async {
            await withMockedClock { _ in
                let landscapeWindow = CGSize(width: 852, height: 393)
                let stub = ScreenSizeStub(landscapeWindow)
                let sut = getSut(stub)

                NotificationCenter.default.post(name: UIDevice.orientationDidChangeNotification, object: nil)

                #expect(reportedSize(sut) == landscapeWindow)
            }
        }

        @Test("reports the rotated size when the bounds flip after the rotation notification")
        func reportsRotatedSizeWhenBoundsFlipLate() async {
            await withMockedClock { _ in
                let portrait = CGSize(width: 393, height: 852)
                let landscape = CGSize(width: 852, height: 393)
                let stub = ScreenSizeStub(portrait)
                let sut = getSut(stub)
                #expect(reportedSize(sut) == portrait)

                NotificationCenter.default.post(name: UIDevice.orientationDidChangeNotification, object: nil)
                stub.current = landscape

                #expect(reportedSize(sut) == landscape)
            }
        }

        @Test("keeps the last known size when there is no window to measure")
        func keepsLastKnownSizeWhenMeasurementIsEmpty() async {
            await withMockedClock { clock in
                let stub = ScreenSizeStub(DuoScreen.folded)
                let sut = getSut(stub)
                #expect(reportedSize(sut) == DuoScreen.folded)

                stub.current = nil
                clock.date += 2
                #expect(reportedSize(sut) == DuoScreen.folded)

                NotificationCenter.default.post(name: UIWindow.didBecomeKeyNotification, object: nil)
                #expect(reportedSize(sut) == DuoScreen.folded)
            }
        }

        /// Folding a device twice in quick succession resizes the window twice inside one refresh
        /// interval. The next refresh has to report where the window ended up, not the size it passed
        /// through on the way.
        @Test("reports the latest size after several resizes inside one refresh interval")
        func reportsLatestSizeAfterRapidResizes() async {
            await withMockedClock { clock in
                let stub = ScreenSizeStub(DuoScreen.folded)
                let sut = getSut(stub)
                #expect(reportedSize(sut) == DuoScreen.folded)

                // Unfold, then land on a third size, both inside the interval: neither is measured yet.
                clock.date += 0.2
                stub.current = DuoScreen.unfolded
                #expect(reportedSize(sut) == DuoScreen.folded)

                let settled = CGSize(width: 852, height: 393)
                clock.date += 0.2
                stub.current = settled

                // Fails as `folded` if nothing re-measures, and as `unfolded` if the size the window
                // passed through gets latched.
                clock.date += 2
                #expect(reportedSize(sut) == settled)
            }
        }

        @Test("keeps refreshing after the wall clock moves backwards")
        func refreshesAfterClockMovesBackwards() async {
            await withMockedClock { clock in
                let stub = ScreenSizeStub(DuoScreen.folded)
                let sut = getSut(stub)
                #expect(reportedSize(sut) == DuoScreen.folded)

                clock.date -= 3600
                stub.current = DuoScreen.unfolded

                #expect(reportedSize(sut) == DuoScreen.unfolded)
            }
        }
    }
#endif
