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
        private var reads = 0

        init(_ size: CGSize?) {
            self.size = size
        }

        var current: CGSize? {
            get { lock.withLock { reads += 1
                return size
            } }
            set { lock.withLock { size = newValue } }
        }

        /// How many times the context actually measured, as opposed to reading its cache.
        var measurements: Int { lock.withLock { reads } }
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

        @Test("reports the rotated size when an event is captured before the bounds flip")
        func reportsRotatedSizeWhenCapturedBeforeBoundsFlip() async {
            await withMockedClock { clock in
                let portrait = CGSize(width: 393, height: 852)
                let landscape = CGSize(width: 852, height: 393)
                let stub = ScreenSizeStub(portrait)
                let sut = getSut(stub)
                #expect(reportedSize(sut) == portrait)

                NotificationCenter.default.post(name: UIDevice.orientationDidChangeNotification, object: nil)

                // An event captured while the window is still portrait...
                clock.date += 0.1
                #expect(reportedSize(sut) == portrait)

                // ...must not stop the next one from seeing the flip, still inside the refresh interval.
                clock.date += 0.1
                stub.current = landscape
                #expect(reportedSize(sut) == landscape)
            }
        }

        /// The window is bounded, so a transition costs at most one interval of per-event measuring.
        @Test("stops re-measuring on every event once the transition window is over")
        func throttlesAgainAfterTransitionWindow() async {
            await withMockedClock { clock in
                let stub = ScreenSizeStub(DuoScreen.folded)
                let sut = getSut(stub)

                NotificationCenter.default.post(name: UIDevice.orientationDidChangeNotification, object: nil)
                #expect(reportedSize(sut) == DuoScreen.folded)

                // Past the window: this capture re-measures on the ordinary interval, restarting the throttle.
                clock.date += 2
                #expect(reportedSize(sut) == DuoScreen.folded)

                stub.current = DuoScreen.unfolded
                clock.date += 0.2
                #expect(reportedSize(sut) == DuoScreen.folded)
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

                // The empty measurement must not leave a refresh permanently in flight.
                stub.current = DuoScreen.unfolded
                clock.date += 2
                #expect(reportedSize(sut) == DuoScreen.unfolded)
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

        /// `capture()` builds properties on the caller's thread, so measuring hops to main. A burst of
        /// background captures must queue one measurement, not one each.
        ///
        /// Deliberately not on the mocked clock: it has to suspend to drain the main queue, and
        /// suspending while the global `now` is frozen leaks it to suites running concurrently.
        @Test("coalesces the refresh when events are captured off the main thread")
        func coalescesRefreshesCapturedOffMain() async {
            let stub = ScreenSizeStub(DuoScreen.folded)
            let sut = getSut(stub)
            #expect(reportedSize(sut) == DuoScreen.folded)

            NotificationCenter.default.post(name: UIDevice.orientationDidChangeNotification, object: nil)
            let before = stub.measurements

            let done = DispatchSemaphore(value: 0)
            DispatchQueue.global().async {
                for _ in 0 ..< 5 {
                    _ = sut.dynamicContext()
                }
                done.signal()
            }
            done.wait()

            // Main is still busy in this test body, so nothing has measured off it yet.
            #expect(stub.measurements == before)

            await withCheckedContinuation { c in DispatchQueue.main.async { c.resume() } }
            #expect(stub.measurements == before + 1)
        }

        /// The settle window is bounded by a start instant, so a backwards clock must close it rather
        /// than hold it open and make every event measure.
        @Test("closes the transition window when the wall clock moves backwards")
        func closesTransitionWindowAfterClockMovesBackwards() async {
            await withMockedClock { clock in
                let stub = ScreenSizeStub(DuoScreen.folded)
                let sut = getSut(stub)
                #expect(reportedSize(sut) == DuoScreen.folded)

                NotificationCenter.default.post(name: UIDevice.orientationDidChangeNotification, object: nil)
                clock.date -= 3600
                // A negative throttle interval counts as elapsed, so this read re-measures and restarts it.
                #expect(reportedSize(sut) == DuoScreen.folded)

                stub.current = DuoScreen.unfolded
                clock.date += 0.2
                #expect(reportedSize(sut) == DuoScreen.folded)
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
