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

    // Only used off-main while this view's original layout forwarding is replaced by a test stub.
    private struct StubbedLayoutCall: @unchecked Sendable {
        let view: UIView
        let layer: CALayer
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
        @Test("restarts preserve newer forwarding, notify once, and reuse a bounded hook chain")
        func preservesNewerSwizzler() async throws {
            let publisher = ApplicationViewLayoutPublisher(viewClass: LifecycleLayoutView.self)
            defer { withExtendedLifetime(publisher) {} }
            try #require(publisher.onViewLayout.subscriberCount == 0)
            let view = LifecycleLayoutView()
            let layer = view.layer
            let selector = #selector(UIView.layoutSublayers(of:))
            let method = try #require(class_getInstanceMethod(LifecycleLayoutView.self, selector))
            var originalCalls = 0
            var otherCalls = 0
            var notifications = 0
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

            var resumed: IMP?
            for restart in 1 ... 100 {
                token = publisher.onViewLayout.subscribe(throttle: 0, trailing: true) {
                    #expect(Thread.isMainThread)
                    notifications += 1
                }
                let current = method_getImplementation(method)
                if let resumed {
                    #expect(current == resumed)
                } else {
                    resumed = current
                }
                view.layoutSublayers(of: layer)
                await withCheckedContinuation { continuation in
                    DispatchQueue.main.async { continuation.resume() }
                }
                #expect(originalCalls == restart)
                #expect(otherCalls == restart)
                #expect(notifications == restart)
                token = nil
                #expect(method_getImplementation(method) == other)
            }

            // The newer swizzler restores the implementation it originally replaced.
            method_setImplementation(method, installed)
            token = publisher.onViewLayout.subscribe(throttle: 0, trailing: true) {
                notifications += 1
            }
            #expect(method_getImplementation(method) == installed)
            view.layoutSublayers(of: layer)
            await withCheckedContinuation { continuation in
                DispatchQueue.main.async { continuation.resume() }
            }
            #expect(originalCalls == 101)
            #expect(otherCalls == 100)
            #expect(notifications == 101)
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

        @MainActor
        @Test("resubscription recovers after another swizzler detaches the PostHog hook", arguments: [false, true], [false, true])
        func externallyDetachedHook(removeEarlierSwizzler: Bool, retainOtherSubscriber: Bool) async throws {
            let publisher = ApplicationViewLayoutPublisher(viewClass: LifecycleLayoutView.self)
            defer { withExtendedLifetime(publisher) {} }
            let view = LifecycleLayoutView()
            let layer = view.layer
            let selector = #selector(UIView.layoutSublayers(of:))
            let method = try #require(class_getInstanceMethod(LifecycleLayoutView.self, selector))
            var originalCalls = 0
            var otherCalls = 0
            var notifications = 0
            let originalBlock: @convention(block) (UIView, CALayer) -> Void = { _, _ in originalCalls += 1 }
            let stub = imp_implementationWithBlock(originalBlock)
            let original = method_setImplementation(method, stub)
            let forward = unsafeBitCast(stub, to: LayoutImplementation.self)
            let otherBlock: @convention(block) (UIView, CALayer) -> Void = { view, layer in
                otherCalls += 1
                forward(view, selector, layer)
            }
            let other = imp_implementationWithBlock(otherBlock)
            defer {
                method_setImplementation(method, original)
                imp_removeBlock(other)
                imp_removeBlock(stub)
            }
            if removeEarlierSwizzler {
                method_setImplementation(method, other)
            }
            // Surveys may keep observing layout while replay stops and restarts.
            var retainedToken = retainOtherSubscriber ? publisher.onViewLayout.subscribe(throttle: 0, trailing: true) {} : nil
            #expect((retainedToken != nil) == retainOtherSubscriber)
            var token: RegistrationToken? = publisher.onViewLayout.subscribe(throttle: 0, trailing: true) {
                notifications += 1
            }
            defer {
                token = nil
                retainedToken = nil
            }
            #expect(token != nil)
            view.layoutSublayers(of: layer)
            await withCheckedContinuation { continuation in
                DispatchQueue.main.async { continuation.resume() }
            }
            try #require(originalCalls == 1)
            try #require(notifications == 1)
            originalCalls = 0
            otherCalls = 0
            notifications = 0

            // Either an older swizzler restores UIKit directly, or a newer one bypasses our IMP.
            let detached = removeEarlierSwizzler ? stub : other
            method_setImplementation(method, detached)
            token = nil
            try #require(publisher.onViewLayout.subscriberCount == (retainOtherSubscriber ? 1 : 0))
            token = publisher.onViewLayout.subscribe(throttle: 0, trailing: true) {
                notifications += 1
            }
            view.layoutSublayers(of: layer)
            await withCheckedContinuation { continuation in
                DispatchQueue.main.async { continuation.resume() }
            }
            #expect(publisher.onViewLayout.subscriberCount == (retainOtherSubscriber ? 2 : 1))
            #expect(originalCalls == 1)
            #expect(otherCalls == (removeEarlierSwizzler ? 0 : 1))
            print("HOOK_DETACH olderUninstall=\(removeEarlierSwizzler), retainedSubscriber=\(retainOtherSubscriber), rootUnchanged=\(method_getImplementation(method) == detached), originalCalls=\(originalCalls), notifications=\(notifications)")
            #expect(notifications == 1)
        }

        private typealias LayoutImplementation = @convention(c) (UIView, Selector, CALayer) -> Void

        @MainActor
        private func withOriginalLayoutStub(
            _ original: @escaping (UIView, CALayer) -> Void,
            perform body: (ApplicationViewLayoutPublisher, UIView, CALayer) async throws -> Void
        ) async throws {
            let publisher = ApplicationViewLayoutPublisher(viewClass: LifecycleLayoutView.self)
            defer { withExtendedLifetime(publisher) {} }
            let view = LifecycleLayoutView()
            let layer = view.layer
            let method = try #require(class_getInstanceMethod(LifecycleLayoutView.self, #selector(UIView.layoutSublayers(of:))))
            let block: @convention(block) (UIView, CALayer) -> Void = original
            let stub = imp_implementationWithBlock(block)
            let implementation = method_setImplementation(method, stub)
            defer {
                registrationToken = nil
                method_setImplementation(method, implementation)
                imp_removeBlock(stub)
            }
            try await body(publisher, view, layer)
            // Drain off-main layout notifications before the next test.
            await withCheckedContinuation { continuation in
                DispatchQueue.main.async { continuation.resume() }
            }
        }

        private func runOffMain(_ body: @escaping () -> Void) throws {
            let finished = DispatchSemaphore(value: 0)
            DispatchQueue.global().async {
                body()
                finished.signal()
            }
            try #require(finished.wait(timeout: .now() + 5) == .success)
        }

        private func captureStdout(_ body: () throws -> Void) throws -> String {
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            FileManager.default.createFile(atPath: url.path, contents: nil)
            defer { try? FileManager.default.removeItem(at: url) }
            let file = try FileHandle(forWritingTo: url)
            defer { file.closeFile() }
            fflush(stdout)
            let saved = dup(STDOUT_FILENO)
            try #require(saved >= 0)
            defer { close(saved) }
            try #require(dup2(file.fileDescriptor, STDOUT_FILENO) >= 0)
            defer {
                fflush(stdout)
                dup2(saved, STDOUT_FILENO)
            }
            try body()
            fflush(stdout)
            return try String(contentsOf: url, encoding: .utf8)
        }

        @MainActor
        @Test("forwards layout synchronously on the calling thread and notifies on main", arguments: [false, true])
        func forwardsLayout(background: Bool) async throws {
            let wasLogging = hedgeLogEnabled
            hedgeLogEnabled = false
            defer { hedgeLogEnabled = wasLogging }
            var originalCalls: [(UIView, CALayer, Bool)] = []
            var notifications = 0
            try await withOriginalLayoutStub({ view, layer in
                originalCalls.append((view, layer, Thread.isMainThread))
            }) { publisher, view, layer in
                registrationToken = publisher.onViewLayout.subscribe(throttle: 0, trailing: true) {
                    #expect(Thread.isMainThread)
                    #expect(originalCalls.count == 1)
                    notifications += 1
                }
                if background {
                    try runOffMain { view.layoutSublayers(of: layer) }
                } else {
                    view.layoutSublayers(of: layer)
                }
                try #require(originalCalls.count == 1)
                #expect(originalCalls[0].0 === view)
                #expect(originalCalls[0].1 === layer)
                #expect(originalCalls[0].2 == !background)
                await waitUntil { notifications == 1 }
                #expect(notifications == 1)
            }
        }

        @MainActor
        @Test("warns before forwarding off-main layout only once while debug logging is enabled", arguments: [1, 32])
        func warnsAboutBackgroundLayout(calls: Int) async throws {
            let wasLogging = hedgeLogEnabled
            defer { hedgeLogEnabled = wasLogging }
            let warning = "UIView.layoutSublayers(of:) was called off the main thread"
            let marker = "original-layout-called"
            try await withOriginalLayoutStub({ _, _ in print(marker) }) { publisher, view, layer in
                publisher.resetBackgroundLayoutWarning()
                defer { publisher.resetBackgroundLayoutWarning() }
                registrationToken = publisher.onViewLayout.subscribe(throttle: 0, trailing: true) {}

                hedgeLogEnabled = false
                let disabled = try captureStdout {
                    try runOffMain { view.layoutSublayers(of: layer) }
                }
                #expect(!disabled.contains(warning))
                #expect(disabled.contains(marker))

                hedgeLogEnabled = true
                let main = try captureStdout { view.layoutSublayers(of: layer) }
                #expect(!main.contains(warning))
                #expect(main.contains(marker))

                let call = StubbedLayoutCall(view: view, layer: layer)
                let concurrent = try captureStdout {
                    try runOffMain {
                        DispatchQueue.concurrentPerform(iterations: calls) { _ in
                            call.view.layoutSublayers(of: call.layer)
                        }
                    }
                }
                #expect(concurrent.components(separatedBy: warning).count - 1 == 1)
                #expect(concurrent.components(separatedBy: marker).count - 1 == calls)
                if calls == 1 {
                    let warningRange = try #require(concurrent.range(of: warning))
                    let originalRange = try #require(concurrent.range(of: marker))
                    #expect(warningRange.lowerBound < originalRange.lowerBound)
                }

                registrationToken = nil
                registrationToken = publisher.onViewLayout.subscribe(throttle: 0, trailing: true) {}
                let restarted = try captureStdout {
                    try runOffMain { view.layoutSublayers(of: layer) }
                }
                #expect(!restarted.contains(warning))
                #expect(restarted.contains(marker))
            }
        }

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
