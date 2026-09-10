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

        @Test("lifecycle reproduction: subscriber-count callbacks can arrive out of order")
        func lifecycleStaleCount() throws {
            let zeroPending = DispatchSemaphore(value: 0)
            let releaseZero = DispatchSemaphore(value: 0)
            let finished = DispatchSemaphore(value: 0)
            let lock = NSLock()
            var blockFirstZero = true
            var observedCounts: [Int] = []
            let callback = PostHogThrottledMulticastCallback<Void> { count in
                let shouldBlock = lock.withLock { () -> Bool in
                    guard count == 0, blockFirstZero else { return false }
                    blockFirstZero = false
                    return true
                }
                if shouldBlock {
                    zeroPending.signal()
                    _ = releaseZero.wait(timeout: .now() + 5)
                }
                lock.withLock { observedCounts.append(count) }
            }
            var first: RegistrationToken? = callback.subscribe(throttle: 0) {}
            #expect(first != nil)
            DispatchQueue.global().async {
                first = nil
                finished.signal()
            }
            defer { releaseZero.signal() }
            try #require(zeroPending.wait(timeout: .now() + 5) == .success)
            let second = callback.subscribe(throttle: 0) {}
            defer { withExtendedLifetime(second) {} }
            releaseZero.signal()
            try #require(finished.wait(timeout: .now() + 5) == .success)
            let counts = lock.withLock { observedCounts }
            print("LIFECYCLE observed counts=\(counts), actual subscribers=\(callback.subscriberCount)")
            #expect(counts.last == callback.subscriberCount)
        }

        @MainActor
        @Test("lifecycle reproduction: concurrent subscriptions preserve the real swizzle state")
        func lifecycleConcurrentSubscriptions() throws {
            let publisher = ApplicationViewLayoutPublisher.shared
            let callback = publisher.onViewLayout
            try #require(callback.subscriberCount == 0)
            let method = try #require(class_getInstanceMethod(UIView.self, #selector(UIView.layoutSublayers(of:))))
            let alias = try #require(class_getInstanceMethod(UIView.self, #selector(UIView.ph_swizzled_layoutSublayers(of:))))
            let original = method_getImplementation(method)
            let replacement = method_getImplementation(alias)
            defer {
                method_setImplementation(method, original)
                method_setImplementation(alias, replacement)
            }
            for attempt in 0 ..< 5000 {
                let lock = NSLock()
                var tokens: [RegistrationToken] = []
                DispatchQueue.concurrentPerform(iterations: 8) { _ in
                    let token = callback.subscribe(throttle: 0) {}
                    lock.withLock { tokens.append(token) }
                }
                let subscribed = callback.subscriberCount
                let installed = method_getImplementation(method) == replacement
                tokens.removeAll()
                let removed = method_getImplementation(method) == original
                if !installed || !removed {
                    print("LIFECYCLE attempt=\(attempt), subscribed=\(subscribed), installed=\(installed), removed=\(removed), remaining=\(callback.subscriberCount)")
                    #expect(installed)
                    #expect(removed)
                    return
                }
            }
            print("LIFECYCLE no method-state mismatch observed in 5000 rounds")
        }

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
    }
#endif
