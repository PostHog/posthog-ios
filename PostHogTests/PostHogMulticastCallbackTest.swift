import Foundation
@testable import PostHog
import Testing

@Suite("PostHogMulticastCallback Tests")
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

@Suite("PostHogThrottledMulticastCallback Tests")
class PostHogThrottledMulticastCallbackTests {
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
}
