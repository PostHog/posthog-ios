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

    // Keep runtime replacements local to this suite, even when another suite has an active recording.
    private final class LifecycleLayoutView: UIView {
        override dynamic func layoutSublayers(of _: CALayer) {}
    }

    @Suite("Application View Publisher Test", .serialized, .resetsGlobalState)
    final class ApplicationViewLayoutPublisherTest {
        var registrationToken: RegistrationToken?

        @Test("coalesces concurrent subscriber-count changes to the current count")
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
        @Test("concurrent subscriptions preserve installed and restored layout implementations")
        func lifecycleConcurrentSubscriptions() throws {
            let publisher = ApplicationViewLayoutPublisher(viewClass: LifecycleLayoutView.self)
            defer { withExtendedLifetime(publisher) {} }
            let callback = publisher.onViewLayout
            try #require(callback.subscriberCount == 0)
            let method = try #require(class_getInstanceMethod(LifecycleLayoutView.self, #selector(UIView.layoutSublayers(of:))))
            let original = method_getImplementation(method)
            var initialToken: RegistrationToken? = callback.subscribe(throttle: 0) {}
            let replacement = method_getImplementation(method)
            try #require(replacement != original)
            #expect(initialToken != nil)
            initialToken = nil
            try #require(method_getImplementation(method) == original)
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

        @Test("concurrent first access returns the same layout publisher callbacks")
        func concurrentFirstAccess() {
            let publisher = ApplicationViewLayoutPublisher()
            let lock = NSLock()
            var callbacks: [PostHogThrottledMulticastCallback<Void>] = []
            DispatchQueue.concurrentPerform(iterations: 32) { _ in
                let callback = publisher.onViewLayout
                lock.withLock { callbacks.append(callback) }
            }
            #expect(Set(callbacks.map(ObjectIdentifier.init)).count == 1)
        }

        @MainActor
        @Test("a captured layout implementation still forwards after unsubscribe", arguments: [false, true])
        func forwardsCapturedLayoutAfterUnsubscribe(background: Bool) throws {
            let publisher = ApplicationViewLayoutPublisher(viewClass: LifecycleLayoutView.self)
            defer { withExtendedLifetime(publisher) {} }
            try #require(publisher.onViewLayout.subscriberCount == 0)
            let view = LifecycleLayoutView()
            let layer = view.layer
            let selector = #selector(UIView.layoutSublayers(of:))
            let method = try #require(class_getInstanceMethod(LifecycleLayoutView.self, selector))
            var forwardedCalls = 0
            var forwardedOnMain = false
            let block: @convention(block) (UIView, CALayer) -> Void = { receivedView, receivedLayer in
                #expect(receivedView === view)
                #expect(receivedLayer === layer)
                forwardedCalls += 1
                forwardedOnMain = Thread.isMainThread
            }
            let stub = imp_implementationWithBlock(block)
            let original = method_setImplementation(method, stub)
            defer {
                method_setImplementation(method, original)
                imp_removeBlock(stub)
            }
            var token: RegistrationToken? = publisher.onViewLayout.subscribe(throttle: 0, trailing: true) {}
            #expect(token != nil)
            let captured = unsafeBitCast(method_getImplementation(method), to: LayoutImplementation.self)
            token = nil
            try #require(method_getImplementation(method) == stub)

            // objc_msgSend may have already selected an IMP when another thread uninstalls the hook.
            if background {
                let finished = DispatchSemaphore(value: 0)
                DispatchQueue.global().async {
                    captured(view, selector, layer)
                    finished.signal()
                }
                try #require(finished.wait(timeout: .now() + 5) == .success)
            } else {
                captured(view, selector, layer)
            }
            #expect(forwardedCalls == 1)
            #expect(forwardedOnMain == !background)
        }

        @MainActor
        @Test("unsubscribe preserves a newer swizzler and resubscribe does not wrap it again")
        func preservesNewerSwizzler() throws {
            let publisher = ApplicationViewLayoutPublisher(viewClass: LifecycleLayoutView.self)
            defer { withExtendedLifetime(publisher) {} }
            try #require(publisher.onViewLayout.subscriberCount == 0)
            let view = LifecycleLayoutView()
            let layer = view.layer
            let selector = #selector(UIView.layoutSublayers(of:))
            let method = try #require(class_getInstanceMethod(LifecycleLayoutView.self, selector))
            var originalCalls = 0
            var otherCalls = 0
            let originalBlock: @convention(block) (UIView, CALayer) -> Void = { _, _ in originalCalls += 1 }
            let stub = imp_implementationWithBlock(originalBlock)
            let original = method_setImplementation(method, stub)
            defer {
                method_setImplementation(method, original)
                imp_removeBlock(stub)
            }
            var token: RegistrationToken? = publisher.onViewLayout.subscribe(throttle: 0, trailing: true) {}
            defer { token = nil }
            #expect(token != nil)
            let installed = method_getImplementation(method)
            let forward = unsafeBitCast(installed, to: LayoutImplementation.self)
            let otherBlock: @convention(block) (UIView, CALayer) -> Void = { view, layer in
                otherCalls += 1
                forward(view, selector, layer)
            }
            let other = imp_implementationWithBlock(otherBlock)
            defer { imp_removeBlock(other) }
            method_setImplementation(method, other)
            token = nil
            try #require(method_getImplementation(method) == other)

            token = publisher.onViewLayout.subscribe(throttle: 0, trailing: true) {}
            #expect(method_getImplementation(method) == other)
            view.layoutSublayers(of: layer)
            #expect(originalCalls == 1)
            #expect(otherCalls == 1)
            token = nil
            #expect(method_getImplementation(method) == other)

            // The newer swizzler restores the implementation it originally replaced.
            method_setImplementation(method, installed)
            token = publisher.onViewLayout.subscribe(throttle: 0, trailing: true) {}
            token = nil
            #expect(method_getImplementation(method) == stub)
        }

        @MainActor
        @Test("a retired hook in a newer swizzler's chain does not duplicate notifications")
        func retiredHookDoesNotDuplicateNotifications() async throws {
            let publisher = ApplicationViewLayoutPublisher(viewClass: LifecycleLayoutView.self)
            defer { withExtendedLifetime(publisher) {} }
            try #require(publisher.onViewLayout.subscriberCount == 0)
            let view = LifecycleLayoutView()
            let layer = view.layer
            let selector = #selector(UIView.layoutSublayers(of:))
            let method = try #require(class_getInstanceMethod(LifecycleLayoutView.self, selector))
            var originalCalls = 0
            let originalBlock: @convention(block) (UIView, CALayer) -> Void = { _, _ in originalCalls += 1 }
            let stub = imp_implementationWithBlock(originalBlock)
            let original = method_setImplementation(method, stub)
            defer {
                method_setImplementation(method, original)
                imp_removeBlock(stub)
            }
            var token: RegistrationToken? = publisher.onViewLayout.subscribe(throttle: 0, trailing: true) {}
            #expect(token != nil)
            let retired = unsafeBitCast(method_getImplementation(method), to: LayoutImplementation.self)
            token = nil
            let otherBlock: @convention(block) (UIView, CALayer) -> Void = { view, layer in
                retired(view, selector, layer)
            }
            let other = imp_implementationWithBlock(otherBlock)
            defer { imp_removeBlock(other) }
            method_setImplementation(method, other)

            var notifications = 0
            token = publisher.onViewLayout.subscribe(throttle: 0, trailing: true) {
                #expect(Thread.isMainThread)
                notifications += 1
            }
            defer { token = nil }
            view.layoutSublayers(of: layer)
            await withCheckedContinuation { continuation in
                DispatchQueue.main.async { continuation.resume() }
            }
            #expect(originalCalls == 1)
            #expect(notifications == 1)
        }

        private typealias LayoutImplementation = @convention(c) (UIView, Selector, CALayer) -> Void

        // invoke() hops to a background throttle queue then back to main, so effects are async.
        @MainActor
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

            let sut = ApplicationViewLayoutPublisher(viewClass: LifecycleLayoutView.self)
            defer { withExtendedLifetime(sut) {} }
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
