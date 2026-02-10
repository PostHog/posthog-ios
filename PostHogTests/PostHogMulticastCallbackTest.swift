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
