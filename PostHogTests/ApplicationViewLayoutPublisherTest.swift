//
//  ApplicationViewLayoutPublisherTest.swift
//  PostHog
//
//  Created by Ioannis Josephides on 26/03/2025.
//

#if os(iOS)
    import Foundation
    @testable import PostHog
    import Testing
    import UIKit

    @Suite("Application View Publisher Test", .serialized, .resetsGlobalState)
    final class ApplicationViewLayoutPublisherTest {
        var registrationToken: RegistrationToken?

        // invoke() hops to a background throttle queue then back to main, so effects are async.
        private func waitUntil(timeoutNanoseconds: UInt64 = 1_000_000_000,
                               pollNanoseconds: UInt64 = 5_000_000,
                               _ condition: () -> Bool) async
        {
            let start = DispatchTime.now().uptimeNanoseconds
            while !condition(), DispatchTime.now().uptimeNanoseconds - start < timeoutNanoseconds {
                try? await Task.sleep(nanoseconds: pollNanoseconds)
            }
        }

        @MainActor
        @Test("throttles layout views correctly")
        func throttleLayoutViews() async throws {
            let mockNow = MockDate()
            now = { mockNow.date }
            defer { now = { Date() } }

            var timesCalled = 0
            var lastCallTime: Date?

            let sut = ApplicationViewLayoutPublisher.shared
            registrationToken = sut.onViewLayout.subscribe(throttle: 2) {
                timesCalled += 1
                lastCallTime = mockNow.date
            }

            sut.simulateLayoutSubviews()
            await waitUntil { timesCalled == 1 }

            let firstCallDate = mockNow.date
            #expect(timesCalled == 1)
            #expect(lastCallTime == firstCallDate)

            // Within the 2s throttle window, so each must be ignored. invokeIfReady reads the
            // mocked clock when its async block runs, so let it settle before advancing the clock.
            for _ in 0 ..< 3 {
                mockNow.date.addTimeInterval(0.6)
                sut.simulateLayoutSubviews()
                try? await Task.sleep(nanoseconds: 20 * NSEC_PER_MSEC)
            }

            #expect(timesCalled == 1, "Calls within throttle interval should be ignored")
            #expect(lastCallTime == firstCallDate)

            // >2s since last trigger, so this one fires.
            mockNow.date.addTimeInterval(0.4) // Total: 2.2s
            sut.simulateLayoutSubviews()
            await waitUntil { timesCalled == 2 }

            #expect(timesCalled == 2)
            #expect(lastCallTime == mockNow.date)

            registrationToken = nil
        }

        @MainActor
        @Test("does not run UIKit layout off the main thread")
        func layoutStaysOnMainThread() async throws {
            let sut = ApplicationViewLayoutPublisher.shared
            // Subscribing installs the swizzle on `UIView.layoutSublayers(of:)`.
            registrationToken = sut.onViewLayout.subscribe(throttle: 0) {}

            let view = ThreadRecordingView()
            let layer = view.layer

            await withCheckedContinuation { continuation in
                let thread = Thread {
                    view.layoutSublayers(of: layer)
                    continuation.resume()
                }
                thread.start()
            }

            #expect(view.laidOutOffMainThread == false, "UIKit layout must never run on a background thread")

            registrationToken = nil
        }
    }

    @Suite("View layout capture opt-out", .serialized, .resetsGlobalState)
    struct ViewLayoutCaptureOptOutTest {
        // Surveys are the second subscriber of the shared publisher, and the publisher installs the
        // swizzle for any subscriber. The opt-out only removes the hook if surveys honour it too.
        @Test("surveys skip the layout publisher when captureViewLayoutChanges is false", arguments: [true, false])
        func surveysHonourOptOut(captureViewLayoutChanges: Bool) throws {
            let server = MockPostHogServer()
            server.start()
            let mockPublisher = MockViewLayoutPublisher()
            DI.main.viewLayoutPublisher = mockPublisher
            defer {
                DI.main.viewLayoutPublisher = ApplicationViewLayoutPublisher.shared
                server.stop()
            }

            let config = PostHogConfig(projectToken: testProjectToken, host: "http://localhost:9090")
            config._surveys = true
            config.captureViewLayoutChanges = captureViewLayoutChanges
            config.disableReachabilityForTesting = true
            config.disableQueueTimerForTesting = true
            config.captureApplicationLifecycleEvents = false
            PostHogStorage(config).reset()

            let postHog = PostHogSDK.with(config)
            PostHogSurveyIntegration.clearInstalls()
            let integration = PostHogSurveyIntegration()
            try #require(integration.install(postHog) == .installed)
            defer {
                integration.uninstall(postHog)
                postHog.close()
                postHog.reset()
            }

            if captureViewLayoutChanges {
                #expect(mockPublisher.onViewLayout.subscriberCount > 0)
            } else {
                #expect(mockPublisher.onViewLayout.subscriberCount == 0)
            }
        }
    }

    private final class MockViewLayoutPublisher: ViewLayoutPublishing {
        let onViewLayout = PostHogThrottledMulticastCallback<Void>()
    }

    private final class ThreadRecordingView: UIView {
        private(set) var laidOutOffMainThread = false

        override func layoutSubviews() {
            if !Thread.isMainThread {
                laidOutOffMainThread = true
            }
            super.layoutSubviews()
        }
    }
#endif
