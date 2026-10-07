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
        func multicastNoStomp() {
            let reachability = Reachability()
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

        @Test("releasing a reachable subscription token unregisters that subscriber")
        func tokenDeallocUnsubscribesOnReachable() {
            let reachability = Reachability()
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

        @Test("releasing an unreachable subscription token unregisters that subscriber")
        func tokenDeallocUnsubscribesOnUnreachable() {
            let reachability = Reachability()
            var calls = 0

            do {
                let token = reachability.onUnreachable.subscribe { _ in calls += 1 }
                reachability.onUnreachable.invoke(reachability)
                #expect(calls == 1)
                _ = token
            }

            reachability.onUnreachable.invoke(reachability)
            #expect(calls == 1)
        }
    }

    @Suite("Reachability notifier")
    final class PostHogReachabilityNotifierTests {
        @Test("the first start reports the current connection once")
        func firstStartReportsCurrentConnection() {
            let reachability = Reachability(notificationQueue: nil, monitorsPaths: false)
            var reachable = 0
            let token = reachability.onReachable.subscribe { _ in reachable += 1 }
            defer { _ = token }

            reachability.update(.wifi)
            #expect(reachable == 0)

            reachability.startNotifier()
            #expect(reachable == 1)

            reachability.startNotifier()
            #expect(reachable == 1)
        }

        @Test("paths after start are reported, paths after stop are not")
        func reportsPathsWhileRunning() {
            let reachability = Reachability(notificationQueue: nil, monitorsPaths: false)
            var reachable = 0
            var unreachable = 0
            let tokens = [
                reachability.onReachable.subscribe { _ in reachable += 1 },
                reachability.onUnreachable.subscribe { _ in unreachable += 1 },
            ]
            defer { _ = tokens }

            // No path yet, so starting reports nothing.
            reachability.startNotifier()
            #expect(reachable == 0)

            reachability.update(.cellular)
            reachability.update(.unavailable)
            #expect(reachable == 1)
            #expect(unreachable == 1)

            reachability.stopNotifier()
            reachability.update(.wifi)
            #expect(reachable == 1)
            #expect(reachability.connection == .wifi)
        }

        @Test("queued notifications report the connection at delivery, not a stale one")
        func notificationsReportConnectionAtDelivery() {
            let notificationQueue = DispatchQueue(label: "test.reachability.notifications")
            let reachability = Reachability(notificationQueue: notificationQueue, monitorsPaths: false)
            var reachable = 0
            var unreachable = 0
            let tokens = [
                reachability.onReachable.subscribe { _ in reachable += 1 },
                reachability.onUnreachable.subscribe { _ in unreachable += 1 },
            ]
            defer { _ = tokens }

            // Offline at launch, then the network comes back before the start notification runs.
            reachability.update(.unavailable)
            notificationQueue.suspend()
            reachability.startNotifier()
            reachability.update(.wifi)
            notificationQueue.resume()
            notificationQueue.sync {}

            // A stale `onUnreachable` would pause the queues while online.
            #expect(unreachable == 0)
            #expect(reachable == 2)
        }

        @Test("without a path, connection is nil and only the first reads wait")
        func connectionWithoutPath() {
            let reachability = Reachability(notificationQueue: nil, monitorsPaths: false)
            #expect(reachability.connection == nil)

            let start = Date()
            #expect(reachability.connection == nil)
            #expect(Date().timeIntervalSince(start) < 0.05)
        }
    }
#endif
