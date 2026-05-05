//
//  PostHogReachabilityTest.swift
//  PostHogTests
//

import Foundation
@testable import PostHog
import Testing

#if !os(watchOS)
    @Suite("Reachability multicast")
    final class PostHogReachabilityTests {
        @Test("multiple subscribers all fire on every transition")
        func multicastNoStomp() throws {
            let reachability = try Reachability()
            var subscriberAReachable = 0
            var subscriberBReachable = 0
            var subscriberAUnreachable = 0
            var subscriberBUnreachable = 0

            let tokenAReachable = reachability.onReachable.subscribe { _ in subscriberAReachable += 1 }
            let tokenBReachable = reachability.onReachable.subscribe { _ in subscriberBReachable += 1 }
            let tokenAUnreachable = reachability.onUnreachable.subscribe { _ in subscriberAUnreachable += 1 }
            let tokenBUnreachable = reachability.onUnreachable.subscribe { _ in subscriberBUnreachable += 1 }
            // Hold the tokens for the duration of the test; releasing them would
            // unsubscribe.
            defer {
                _ = tokenAReachable
                _ = tokenBReachable
                _ = tokenAUnreachable
                _ = tokenBUnreachable
            }

            reachability.onUnreachable.invoke(reachability)
            reachability.onReachable.invoke(reachability)
            reachability.onUnreachable.invoke(reachability)

            // With single-slot callbacks, whichever subscriber registered first
            // would have shown 0. Multicast → both fire on every event.
            #expect(subscriberAReachable == 1)
            #expect(subscriberBReachable == 1)
            #expect(subscriberAUnreachable == 2)
            #expect(subscriberBUnreachable == 2)
        }

        @Test("releasing a subscription token unregisters that subscriber")
        func tokenDeallocUnsubscribes() throws {
            let reachability = try Reachability()
            var calls = 0

            do {
                let token = reachability.onReachable.subscribe { _ in calls += 1 }
                reachability.onReachable.invoke(reachability)
                #expect(calls == 1)
                _ = token
            } // token deallocates here

            reachability.onReachable.invoke(reachability)
            // Subscriber should have been auto-removed when its token went out
            // of scope, so the count is unchanged.
            #expect(calls == 1)
        }
    }
#endif
