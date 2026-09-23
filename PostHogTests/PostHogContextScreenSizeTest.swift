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

    @Suite("Screen size follows a resized window", .serialized)
    struct PostHogContextScreenSizeTest {
        private func getSut(_ stub: ScreenSizeStub) -> PostHogContext {
            PostHogContext(nil, screenSizeOverride: { stub.current })
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

        /// Refreshes hop to the main thread, so every assertion polls rather than reads once.
        private func waitForReportedSize(
            _ context: PostHogContext,
            toEqual expected: CGSize,
            timeoutNanoseconds: UInt64 = 2_000_000_000,
            pollNanoseconds: UInt64 = 10_000_000
        ) async -> CGSize? {
            let start = DispatchTime.now().uptimeNanoseconds
            var last = reportedSize(context)
            while last != expected, DispatchTime.now().uptimeNanoseconds - start < timeoutNanoseconds {
                try? await Task.sleep(nanoseconds: pollNanoseconds)
                last = reportedSize(context)
            }
            return last
        }

        @Test("reports the window size a new key window brings")
        func reportsSizeOnKeyWindowChange() async throws {
            let stub = ScreenSizeStub(DuoScreen.folded)
            let sut = getSut(stub)

            NotificationCenter.default.post(name: UIWindow.didBecomeKeyNotification, object: nil)

            #expect(await waitForReportedSize(sut, toEqual: DuoScreen.folded) == DuoScreen.folded)
        }

        /// Unfolding an iPhone Duo resizes the app's window without rotating the device and without
        /// making a different window key — the two signals the context refreshes on. Stage Manager and
        /// split-view resizes land in the same blind spot.
        @Test("reports the new size after a resize that fires neither refresh signal")
        func reportsSizeAfterSilentResize() async throws {
            let stub = ScreenSizeStub(DuoScreen.folded)
            let sut = getSut(stub)

            NotificationCenter.default.post(name: UIWindow.didBecomeKeyNotification, object: nil)
            #expect(await waitForReportedSize(sut, toEqual: DuoScreen.folded) == DuoScreen.folded)

            stub.current = DuoScreen.unfolded

            #expect(await waitForReportedSize(sut, toEqual: DuoScreen.unfolded) == DuoScreen.unfolded)
        }

        /// A portrait-locked app on a sideways device has a portrait window, and that is what the
        /// event should report. Reordering the measured size to match `UIDevice.orientation` — which
        /// is what the rotation handler used to do — reports a shape the window never had.
        @Test("reports the measured size on rotation, without reordering it to the device orientation")
        func reportsMeasuredSizeOnRotation() async throws {
            let landscapeWindow = CGSize(width: 852, height: 393)
            let stub = ScreenSizeStub(landscapeWindow)
            let sut = getSut(stub)

            NotificationCenter.default.post(name: UIDevice.orientationDidChangeNotification, object: nil)

            #expect(await waitForReportedSize(sut, toEqual: landscapeWindow) == landscapeWindow)
        }

        /// The refresh runs on every event, including while the app is suspending and there is no
        /// window left to measure. That must not drop `$screen_width`/`$screen_height` from events.
        @Test("keeps the last known size when there is no window to measure")
        func keepsLastKnownSizeWhenMeasurementIsEmpty() async throws {
            let stub = ScreenSizeStub(DuoScreen.folded)
            let sut = getSut(stub)

            NotificationCenter.default.post(name: UIWindow.didBecomeKeyNotification, object: nil)
            #expect(await waitForReportedSize(sut, toEqual: DuoScreen.folded) == DuoScreen.folded)

            stub.current = nil

            // Poll for a size that should never arrive, then assert the old one survived.
            _ = await waitForReportedSize(sut, toEqual: .zero, timeoutNanoseconds: 1_500_000_000)
            #expect(reportedSize(sut) == DuoScreen.folded)
        }
    }
#endif
