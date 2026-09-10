import Foundation
@testable import PostHog
import Testing

@Suite("PostHogMulticastCallback Tests", .resetsGlobalState)
class PostHogMulticastCallbackTests {
    @Test("Single subscriber receives value")
    func singleSubscriber() {
        let callback = PostHogMulticastCallback<Int>()
        var receivedValue: Int?

        let token = callback.subscribe { value in
            receivedValue = value
        }

        callback.invoke(42)

        #expect(receivedValue == 42)
        _ = token // silence read warnings
    }

    @Test("Multiple subscribers all receive value")
    func multipleSubscribers() {
        let callback = PostHogMulticastCallback<String>()
        var values: [String] = []

        let token1 = callback.subscribe { value in
            values.append("sub1: \(value)")
        }
        let token2 = callback.subscribe { value in
            values.append("sub2: \(value)")
        }

        callback.invoke("hello")

        #expect(values.count == 2)
        #expect(values.contains("sub1: hello"))
        #expect(values.contains("sub2: hello"))
        _ = (token1, token2)
    }

    @Test("Subscriber count is correct")
    func subscriberCount() {
        let callback = PostHogMulticastCallback<Int>()

        #expect(callback.subscriberCount == 0)

        let token1 = callback.subscribe { _ in }
        #expect(callback.subscriberCount == 1)

        let token2 = callback.subscribe { _ in }
        #expect(callback.subscriberCount == 2)

        _ = (token1, token2)
    }

    @Test("Token deallocation removes subscriber")
    func tokenDeallocationRemovesSubscriber() {
        let callback = PostHogMulticastCallback<Int>()
        var receivedCount = 0

        var token: RegistrationToken? = callback.subscribe { _ in
            receivedCount += 1
        }

        callback.invoke(1)
        #expect(receivedCount == 1)
        #expect(callback.subscriberCount == 1)

        // Deallocate token
        token = nil

        callback.invoke(2)
        #expect(receivedCount == 1) // Should not have received second invoke
        #expect(callback.subscriberCount == 0)

        _ = token // silence read warnings
    }

    @Test("Optional value can be invoked")
    func optionalValue() {
        let callback = PostHogMulticastCallback<String?>()
        var receivedValues: [String?] = []

        let token = callback.subscribe { value in
            receivedValues.append(value)
        }

        callback.invoke("value")
        callback.invoke(nil)

        #expect(receivedValues.count == 2)
        #expect(receivedValues[0] == "value")
        #expect(receivedValues[1] == nil)

        _ = token // silence read warnings
    }
}

@Suite("PostHogThrottledMulticastCallback Tests", .resetsGlobalState)
class PostHogThrottledMulticastCallbackTests {
    @Test("Subscriber-count callbacks can reenter without overlapping or reporting stale state")
    func reentrantSubscriberCountChanges() {
        weak var callback: PostHogThrottledMulticastCallback<Void>?
        var nestedToken: RegistrationToken?
        var addedNested = false
        var depth = 0
        var counts: [Int] = []
        let publisher = PostHogThrottledMulticastCallback<Void> { count in
            depth += 1
            defer { depth -= 1 }
            #expect(depth == 1)
            #expect(callback?.subscriberCount == count)
            counts.append(count)
            if count == 1, !addedNested {
                addedNested = true
                nestedToken = callback?.subscribe(throttle: 0) {}
            }
        }
        callback = publisher
        var token: RegistrationToken? = publisher.subscribe(throttle: 0) {}
        #expect(token != nil)
        #expect(nestedToken != nil)
        #expect(counts == [1, 2])
        nestedToken = nil
        token = nil
        #expect(counts == [1, 2, 1, 0])
        #expect(publisher.subscriberCount == 0)
    }

    @Test("Single subscriber receives value with throttle")
    func singleSubscriber() async {
        let callback = PostHogThrottledMulticastCallback<Int>()
        var receivedValue: Int?

        let token = callback.subscribe(throttle: 0) { value in
            receivedValue = value
        }

        callback.invoke(42)

        // Wait for async dispatch
        try? await Task.sleep(nanoseconds: 50 * NSEC_PER_MSEC)

        #expect(receivedValue == 42)
        _ = token
    }

    @Test("Multiple subscribers all receive value")
    func multipleSubscribers() async {
        let callback = PostHogThrottledMulticastCallback<String>()
        var values: [String] = []
        let lock = NSLock()

        let token1 = callback.subscribe(throttle: 0) { value in
            lock.withLock { values.append("sub1: \(value)") }
        }
        let token2 = callback.subscribe(throttle: 0) { value in
            lock.withLock { values.append("sub2: \(value)") }
        }

        callback.invoke("hello")

        try? await Task.sleep(nanoseconds: 50 * NSEC_PER_MSEC)

        #expect(values.count == 2)
        #expect(values.contains("sub1: hello"))
        #expect(values.contains("sub2: hello"))
        _ = (token1, token2)
    }

    @Test("Subscriber count is correct")
    func subscriberCount() {
        let callback = PostHogThrottledMulticastCallback<Int>()

        #expect(callback.subscriberCount == 0)

        let token1 = callback.subscribe(throttle: 0) { _ in }
        #expect(callback.subscriberCount == 1)

        let token2 = callback.subscribe(throttle: 0) { _ in }
        #expect(callback.subscriberCount == 2)

        _ = (token1, token2)
    }

    @Test("Token deallocation removes subscriber")
    func tokenDeallocationRemovesSubscriber() async {
        let callback = PostHogThrottledMulticastCallback<Int>()
        var receivedCount = 0

        var token: RegistrationToken? = callback.subscribe(throttle: 0) { _ in
            receivedCount += 1
        }

        callback.invoke(1)
        try? await Task.sleep(nanoseconds: 50 * NSEC_PER_MSEC)
        #expect(receivedCount == 1)
        #expect(callback.subscriberCount == 1)

        // Deallocate token
        token = nil

        callback.invoke(2)
        try? await Task.sleep(nanoseconds: 50 * NSEC_PER_MSEC)
        #expect(receivedCount == 1) // Should not have received second invoke
        #expect(callback.subscriberCount == 0)

        _ = token
    }

    @Test("Throttle prevents rapid invocations")
    func throttlePreventsRapidInvocations() async {
        let mockNow = MockDate()
        now = { mockNow.date }
        defer { now = { Date() } }

        let callback = PostHogThrottledMulticastCallback<Int>()
        var receivedValues: [Int] = []
        let lock = NSLock()

        let token = callback.subscribe(throttle: 1.0) { value in
            lock.withLock { receivedValues.append(value) }
        }

        // First invoke should go through
        callback.invoke(1)
        try? await Task.sleep(nanoseconds: 50 * NSEC_PER_MSEC)
        #expect(lock.withLock { receivedValues } == [1])

        // Second invoke within throttle window should be ignored
        mockNow.date.addTimeInterval(0.5)
        callback.invoke(2)
        try? await Task.sleep(nanoseconds: 50 * NSEC_PER_MSEC)
        #expect(lock.withLock { receivedValues } == [1])

        // Third invoke after throttle window should go through
        mockNow.date.addTimeInterval(0.6) // Total: 1.1s
        callback.invoke(3)
        try? await Task.sleep(nanoseconds: 50 * NSEC_PER_MSEC)
        #expect(lock.withLock { receivedValues } == [1, 3])

        _ = token
    }

    @Test("Different subscribers can have different throttle intervals")
    func differentThrottleIntervals() async {
        let mockNow = MockDate()
        now = { mockNow.date }
        defer { now = { Date() } }

        let callback = PostHogThrottledMulticastCallback<Int>()
        var fastValues: [Int] = []
        var slowValues: [Int] = []
        let lock = NSLock()

        let fastToken = callback.subscribe(throttle: 0.5) { value in
            lock.withLock { fastValues.append(value) }
        }
        let slowToken = callback.subscribe(throttle: 2.0) { value in
            lock.withLock { slowValues.append(value) }
        }

        // First invoke - both receive
        callback.invoke(1)
        try? await Task.sleep(nanoseconds: 50 * NSEC_PER_MSEC)
        #expect(lock.withLock { fastValues } == [1])
        #expect(lock.withLock { slowValues } == [1])

        // After 0.6s - only fast subscriber receives
        mockNow.date.addTimeInterval(0.6)
        callback.invoke(2)
        try? await Task.sleep(nanoseconds: 50 * NSEC_PER_MSEC)
        #expect(lock.withLock { fastValues } == [1, 2])
        #expect(lock.withLock { slowValues } == [1])

        // After another 1.5s (total 2.1s) - both receive
        mockNow.date.addTimeInterval(1.5)
        callback.invoke(3)
        try? await Task.sleep(nanoseconds: 50 * NSEC_PER_MSEC)
        #expect(lock.withLock { fastValues } == [1, 2, 3])
        #expect(lock.withLock { slowValues } == [1, 3])

        _ = (fastToken, slowToken)
    }

    @Test("onSubscriberCountChanged is called")
    func onSubscriberCountChanged() {
        var counts: [Int] = []

        let callback = PostHogThrottledMulticastCallback<Int> { count in
            counts.append(count)
        }

        let token1 = callback.subscribe(throttle: 0) { _ in }
        #expect(counts == [1])

        let token2 = callback.subscribe(throttle: 0) { _ in }
        #expect(counts == [1, 2])

        _ = token1
        _ = token2
    }

    @Test("Void type works correctly")
    func voidType() async {
        let callback = PostHogThrottledMulticastCallback<Void>()
        var callCount = 0

        let token = callback.subscribe(throttle: 0) {
            callCount += 1
        }

        callback.invoke(())
        try? await Task.sleep(nanoseconds: 50 * NSEC_PER_MSEC)

        #expect(callCount == 1)
        _ = token
    }

    @Test("Invoke without subscribers is a safe no-op")
    func invokeWithoutSubscribers() async {
        let callback = PostHogThrottledMulticastCallback<Int>()

        callback.invoke(1)
        try? await Task.sleep(nanoseconds: 50 * NSEC_PER_MSEC)

        #expect(callback.subscriberCount == 0)
    }

    @Test("Subscriber added during another subscriber's throttle window fires immediately")
    func lateSubscriberFiresImmediately() async {
        let mockNow = MockDate()
        now = { mockNow.date }
        defer { now = { Date() } }

        let callback = PostHogThrottledMulticastCallback<Int>()
        var slowValues: [Int] = []
        var lateValues: [Int] = []
        let lock = NSLock()

        let slowToken = callback.subscribe(throttle: 10.0) { value in
            lock.withLock { slowValues.append(value) }
        }

        callback.invoke(1)
        try? await Task.sleep(nanoseconds: 50 * NSEC_PER_MSEC)
        #expect(lock.withLock { slowValues } == [1])

        // Deep inside the slow subscriber's throttle window, a new subscriber
        // appears. It must receive the very next invoke — the eligibility gate
        // may not suppress it based on the slow subscriber's window.
        mockNow.date.addTimeInterval(1.0)
        let lateToken = callback.subscribe(throttle: 1.0) { value in
            lock.withLock { lateValues.append(value) }
        }

        callback.invoke(2)
        try? await Task.sleep(nanoseconds: 50 * NSEC_PER_MSEC)
        #expect(lock.withLock { lateValues } == [2])
        #expect(lock.withLock { slowValues } == [1], "still inside its 10s window")

        _ = (slowToken, lateToken)
    }

    @Test("Resubscribing after all tokens deallocated fires again")
    func resubscribeAfterEmpty() async {
        let callback = PostHogThrottledMulticastCallback<Int>()
        var firstValues: [Int] = []
        var secondValues: [Int] = []
        let lock = NSLock()

        var token: RegistrationToken? = callback.subscribe(throttle: 0) { value in
            lock.withLock { firstValues.append(value) }
        }
        callback.invoke(1)
        try? await Task.sleep(nanoseconds: 50 * NSEC_PER_MSEC)
        #expect(lock.withLock { firstValues } == [1])

        token = nil
        callback.invoke(2)
        try? await Task.sleep(nanoseconds: 50 * NSEC_PER_MSEC)

        token = callback.subscribe(throttle: 0) { value in
            lock.withLock { secondValues.append(value) }
        }
        callback.invoke(3)
        try? await Task.sleep(nanoseconds: 50 * NSEC_PER_MSEC)

        #expect(lock.withLock { firstValues } == [1])
        #expect(lock.withLock { secondValues } == [3])
        _ = token
    }
}

@MainActor
@Suite("PostHog trailing throttle tests", .resetsGlobalState)
struct PostHogTrailingThrottleTests {
    private func waitUntil(_ condition: () -> Bool) async {
        let deadline = DispatchTime.now().uptimeNanoseconds + 2 * NSEC_PER_SEC
        while !condition(), DispatchTime.now().uptimeNanoseconds < deadline {
            try? await Task.sleep(nanoseconds: 5 * NSEC_PER_MSEC)
        }
        #expect(condition())
    }

    @Test("A burst delivers only the latest pending value without another invoke")
    func latestPendingValue() async {
        let callback = PostHogThrottledMulticastCallback<Int>()
        var values: [Int] = []
        let token = callback.subscribe(throttle: 0.2, trailing: true) { values.append($0) }
        callback.invoke(0)
        await waitUntil { values == [0] }
        for value in 1 ... 100 {
            callback.invoke(value)
        }
        #expect(values == [0])
        await waitUntil { values == [0, 100] }
        try? await Task.sleep(nanoseconds: 300 * NSEC_PER_MSEC)
        #expect(values == [0, 100], "No recurring snapshots once the screen is quiet")
        withExtendedLifetime(token) {}
    }

    @Test("Trailing delivery starts the next throttle window and stays on main")
    func trailingStartsNextWindow() async {
        let callback = PostHogThrottledMulticastCallback<Int>()
        var values: [Int] = []
        var times: [TimeInterval] = []
        let token = callback.subscribe(throttle: 0.2, trailing: true) { value in
            #expect(Thread.isMainThread)
            values.append(value)
            times.append(ProcessInfo.processInfo.systemUptime)
            if value < 2 {
                callback.invoke(value + 1)
            }
        }
        callback.invoke(0)
        await waitUntil { values == [0, 1, 2] }
        #expect(times.count == 3)
        if times.count == 3 {
            #expect(times[2] - times[1] >= 0.18)
        }
        withExtendedLifetime(token) {}
    }

    @Test("A pending optional nil is delivered")
    func optionalPendingValue() async {
        let callback = PostHogThrottledMulticastCallback<Int?>()
        var values: [Int?] = []
        let token = callback.subscribe(throttle: 0.2, trailing: true) { values.append($0) }
        callback.invoke(1)
        await waitUntil { values.count == 1 }
        callback.invoke(nil)
        await waitUntil { values.count == 2 }
        #expect(values == [1, nil])
        withExtendedLifetime(token) {}
    }

    @Test("Default subscribers still drop while trailing subscribers recapture")
    func defaultStillDrops() async {
        let callback = PostHogThrottledMulticastCallback<Int>()
        var leading: [Int] = []
        var trailing: [Int] = []
        let leadingToken = callback.subscribe(throttle: 0.2) { leading.append($0) }
        let trailingToken = callback.subscribe(throttle: 0.2, trailing: true) { trailing.append($0) }
        callback.invoke(1)
        await waitUntil { leading == [1] && trailing == [1] }
        callback.invoke(2)
        await waitUntil { trailing == [1, 2] }
        #expect(leading == [1])
        withExtendedLifetime((leadingToken, trailingToken)) {}
    }

    @Test("An isolated invocation does not schedule an extra capture")
    func noUnnecessaryTrailingCapture() async {
        let callback = PostHogThrottledMulticastCallback<Int>()
        var values: [Int] = []
        let token = callback.subscribe(throttle: 0.1, trailing: true) { values.append($0) }
        callback.invoke(1)
        await waitUntil { values == [1] }
        try? await Task.sleep(nanoseconds: 250 * NSEC_PER_MSEC)
        #expect(values == [1])
        callback.invoke(2)
        await waitUntil { values == [1, 2] }
        withExtendedLifetime(token) {}
    }

    @Test("Unsubscribing cancels pending work and resubscribing starts fresh")
    func unsubscribeAndResubscribe() async {
        let callback = PostHogThrottledMulticastCallback<Int>()
        var values: [Int] = []
        var token: RegistrationToken? = callback.subscribe(throttle: 0.2, trailing: true) { values.append($0) }
        callback.invoke(1)
        await waitUntil { values == [1] }
        callback.invoke(2)
        token = nil
        #expect(callback.subscriberCount == 0)
        token = callback.subscribe(throttle: 0.2, trailing: true) { values.append($0) }
        callback.invoke(3)
        await waitUntil { values == [1, 3] }
        try? await Task.sleep(nanoseconds: 300 * NSEC_PER_MSEC)
        #expect(values == [1, 3])
        withExtendedLifetime(token) {}
    }

    @Test("Queued leading delivery is cancelled before main can run it")
    func cancelQueuedLeadingDelivery() async {
        let callback = PostHogThrottledMulticastCallback<Int>()
        var values: [Int] = []
        var token: RegistrationToken? = callback.subscribe(throttle: 0.2, trailing: true) { values.append($0) }
        callback.invoke(1)
        token = nil
        try? await Task.sleep(nanoseconds: 100 * NSEC_PER_MSEC)
        #expect(values.isEmpty)
        withExtendedLifetime(token) {}
    }

    @Test("Pending work retains neither the publisher nor the subscriber")
    func pendingWorkDoesNotRetainOwner() async {
        final class Owner {}
        var owner: Owner? = Owner()
        weak var weakOwner = owner
        var callback: PostHogThrottledMulticastCallback<Int>? = PostHogThrottledMulticastCallback<Int>()
        weak var weakCallback = callback
        var values: [Int] = []
        let token = callback?.subscribe(throttle: 0.2, trailing: true) { [owner] value in
            withExtendedLifetime(owner) { values.append(value) }
        }
        owner = nil
        callback?.invoke(1)
        await waitUntil { values == [1] }
        callback?.invoke(2)
        callback = nil
        #expect(weakCallback == nil)
        #expect(weakOwner == nil)
        try? await Task.sleep(nanoseconds: 300 * NSEC_PER_MSEC)
        #expect(values == [1])
        withExtendedLifetime(token) {}
    }

    @Test("A busy main thread coalesces overdue captures instead of queueing snapshots")
    func busyMainThread() async {
        let callback = PostHogThrottledMulticastCallback<Int>()
        var values: [Int] = []
        let token = callback.subscribe(throttle: 0.1, trailing: true) { values.append($0) }
        // Deliberately hold main across multiple windows without yielding to delivery.
        // A synchronous helper keeps Thread.sleep out of the async context.
        func holdMain() {
            callback.invoke(1)
            Thread.sleep(forTimeInterval: 0.15)
            callback.invoke(2)
            Thread.sleep(forTimeInterval: 0.15)
            callback.invoke(3)
        }
        holdMain()
        await waitUntil { !values.isEmpty }
        try? await Task.sleep(nanoseconds: 150 * NSEC_PER_MSEC)
        #expect(values == [3])
        withExtendedLifetime(token) {}
    }

    @Test("Concurrent layouts schedule one trailing capture")
    func concurrentInvocations() async {
        let callback = PostHogThrottledMulticastCallback<Int>()
        var values: [Int] = []
        let token = callback.subscribe(throttle: 0.2, trailing: true) { values.append($0) }
        callback.invoke(0)
        await waitUntil { values == [0] }
        DispatchQueue.concurrentPerform(iterations: 100) { callback.invoke($0) }
        callback.invoke(100)
        await waitUntil { values == [0, 100] }
        try? await Task.sleep(nanoseconds: 250 * NSEC_PER_MSEC)
        #expect(values == [0, 100])
        withExtendedLifetime(token) {}
    }

    @Test("Trailing subscribers have independent windows and new subscribers fire immediately")
    func independentWindows() async {
        let callback = PostHogThrottledMulticastCallback<Int>()
        var slow: [Int] = []
        var fast: [Int] = []
        let slowToken = callback.subscribe(throttle: 0.8, trailing: true) { slow.append($0) }
        callback.invoke(1)
        await waitUntil { slow == [1] }
        let fastToken = callback.subscribe(throttle: 0.1, trailing: true) { fast.append($0) }
        callback.invoke(2)
        await waitUntil { fast == [2] }
        #expect(slow == [1])
        callback.invoke(3)
        await waitUntil { fast == [2, 3] }
        #expect(slow == [1])
        await waitUntil { slow == [1, 3] }
        withExtendedLifetime((slowToken, fastToken)) {}
    }

    @Test("Zero interval preserves every invocation")
    func zeroInterval() async {
        let callback = PostHogThrottledMulticastCallback<Int>()
        var values: [Int] = []
        let token = callback.subscribe(throttle: 0, trailing: true) { values.append($0) }
        for value in 0 ..< 10 {
            callback.invoke(value)
        }
        await waitUntil { values.count == 10 }
        #expect(values == Array(0 ..< 10))
        withExtendedLifetime(token) {}
    }
}
