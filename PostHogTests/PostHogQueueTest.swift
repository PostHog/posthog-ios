//
//  PostHogQueueTest.swift
//  PostHogTests
//
//  Created by Manoel Aranda Neto on 30.10.23.
//

import Foundation
import Nimble
import OHHTTPStubs
import OHHTTPStubsSwift
@testable import PostHog
import Quick
import XCTest

class PostHogQueueTest: QuickSpec {
    func getSut(flushAt: Int = 1, maxQueueSize: Int = 1000, maxBatchSize: Int = 50) -> PostHogQueue {
        let config = PostHogConfig(projectToken: testProjectToken, host: "http://localhost:9001")
        config.flushAt = flushAt
        config.maxQueueSize = maxQueueSize
        config.maxBatchSize = maxBatchSize
        config.sendFeatureFlagEvent = false
        let storage = PostHogStorage(config)
        let api = PostHogApi(config)
        return PostHogQueue(config, storage, api, .batch, nil)
    }

    override func spec() {
        var server: MockPostHogServer!

        beforeEach {
            server = MockPostHogServer()
            server.start()
        }
        afterEach {
            server.stop()
        }

        it("add item to queue") {
            let sut = self.getSut()

            let event = PostHogEvent(event: "event", distinctId: "distinctId")
            sut.add(event)

            expect(sut.depth) == 1

            let events = getBatchedEvents(server)
            expect(events.count) == 1

            expect(sut.depth) == 0

            sut.clear()
        }

        it("add item to queue and flush respecting flushAt") {
            let sut = self.getSut(flushAt: 2)

            let event = PostHogEvent(event: "event", distinctId: "distinctId")
            let event2 = PostHogEvent(event: "event2", distinctId: "distinctId2")
            let event3 = PostHogEvent(event: "event3", distinctId: "distinctId3")

            // First event should not trigger flush (below flushAt threshold)
            sut.add(event)
            expect(sut.depth) == 1

            // Adding two more events: second event reaches flushAt=2 and triggers flush,
            // third event stays in queue
            sut.add(event2)
            sut.add(event3)

            let events = getBatchedEvents(server)
            expect(events.count) == 2

            expect(sut.depth) == 1

            sut.clear()
        }

        it("add item to queue and rotate queue") {
            let sut = self.getSut(flushAt: 3, maxQueueSize: 2)

            let event = PostHogEvent(event: "event", distinctId: "distinctId")
            let event2 = PostHogEvent(event: "event2", distinctId: "distinctId2")
            let event3 = PostHogEvent(event: "event3", distinctId: "distinctId3")
            sut.add(event)
            sut.add(event2)
            sut.add(event3)

            expect(sut.depth) == 2

            sut.flush()

            let events = getBatchedEvents(server)

            expect(events.count) == 2

            let first = events.first!
            let last = events.last!
            expect(first.event) == "event2"
            expect(last.event) == "event3"

            sut.clear()
        }

        it("halves both batch cap and flush threshold and retains batch on HTTP 413 when cap > 1") {
            let sut = self.getSut(flushAt: 4, maxBatchSize: 4)
            server.batchResponseHandler = { _, _ in
                HTTPStubsResponse(jsonObject: [], statusCode: 413, headers: nil)
            }

            for i in 0 ..< 4 {
                sut.add(PostHogEvent(event: "event\(i)", distinctId: "id\(i)"))
            }

            _ = getBatchedEvents(server)

            expect(sut.currentBatchCapForTesting).toEventually(equal(2))
            expect(sut.currentFlushAtForTesting).toEventually(equal(2))
            expect(sut.depth).toEventually(equal(4))

            sut.clear()
        }

        it("drops batch on HTTP 413 when cap is already 1") {
            let sut = self.getSut(flushAt: 1, maxBatchSize: 1)
            server.batchResponseHandler = { _, _ in
                HTTPStubsResponse(jsonObject: [], statusCode: 413, headers: nil)
            }

            sut.add(PostHogEvent(event: "oversized", distinctId: "id"))

            _ = getBatchedEvents(server)

            expect(sut.depth).toEventually(equal(0))
            // Cap stays at 1 — no reset to maxBatchSize, matching Android.
            expect(sut.currentBatchCapForTesting) == 1

            sut.clear()
        }

        it("retains batch on retriable 5xx and does not change cap") {
            let sut = self.getSut(flushAt: 2, maxBatchSize: 4)
            server.batchResponseHandler = { _, _ in
                HTTPStubsResponse(jsonObject: [], statusCode: 500, headers: nil)
            }

            sut.add(PostHogEvent(event: "event1", distinctId: "id1"))
            sut.add(PostHogEvent(event: "event2", distinctId: "id2"))

            _ = getBatchedEvents(server)

            expect(sut.depth).toEventually(equal(2))
            expect(sut.currentBatchCapForTesting).toEventually(equal(4))

            sut.clear()
        }

        it("retains batch on HTTP 429 and does not change cap") {
            let sut = self.getSut(flushAt: 2, maxBatchSize: 4)
            server.batchResponseHandler = { _, _ in
                HTTPStubsResponse(jsonObject: [], statusCode: 429, headers: nil)
            }

            sut.add(PostHogEvent(event: "event1", distinctId: "id1"))
            sut.add(PostHogEvent(event: "event2", distinctId: "id2"))

            _ = getBatchedEvents(server)

            expect(sut.depth).toEventually(equal(2))
            expect(sut.currentBatchCapForTesting).toEventually(equal(4))

            sut.clear()
        }

        it("halves cap repeatedly across multiple 413s and drops once cap reaches 1") {
            // flushAt is high so add() doesn't trigger an auto-flush — we drive
            // each flush manually to observe the multi-step halving sequence.
            let sut = self.getSut(flushAt: 100, maxBatchSize: 4)
            server.start(batchCount: 3)
            server.batchResponseHandler = { _, _ in
                HTTPStubsResponse(jsonObject: [], statusCode: 413, headers: nil)
            }

            for i in 0 ..< 4 {
                sut.add(PostHogEvent(event: "event\(i)", distinctId: "id\(i)"))
            }

            // First flush: batch=4 → 413 → cap halves to 2, batch retained.
            sut.flush()
            expect(sut.currentBatchCapForTesting).toEventually(equal(2))
            expect(sut.depth) == 4

            // Second flush: batch=2 → 413 → cap halves to 1, batch retained.
            sut.flush()
            expect(sut.currentBatchCapForTesting).toEventually(equal(1))
            expect(sut.depth) == 4

            // Third flush: batch=1, cap already at 1 → drop one record. Cap
            // stays at 1 (no reset, matching Android).
            sut.flush()
            expect(sut.depth).toEventually(equal(3))
            expect(sut.currentBatchCapForTesting) == 1

            sut.clear()
        }

        it("pops batch on 5xx codes outside the narrow retriable set") {
            // 501/505/etc. are NOT in {429, 500, 502, 503, 504} — match
            // posthog-android's RETRYABLE_STATUS_CODES exactly. Treat as
            // non-retriable so a poison record can't block the queue.
            let sut = self.getSut(flushAt: 2, maxBatchSize: 4)
            server.batchResponseHandler = { _, _ in
                HTTPStubsResponse(jsonObject: [], statusCode: 501, headers: nil)
            }

            sut.add(PostHogEvent(event: "event1", distinctId: "id1"))
            sut.add(PostHogEvent(event: "event2", distinctId: "id2"))

            _ = getBatchedEvents(server)

            expect(sut.depth).toEventually(equal(0))
            expect(sut.currentBatchCapForTesting) == 4

            sut.clear()
        }

        it("retains batch on a network error") {
            let sut = self.getSut(flushAt: 2, maxBatchSize: 4)
            let networkError = NSError(domain: NSURLErrorDomain, code: NSURLErrorNotConnectedToInternet, userInfo: nil)
            server.batchResponseHandler = { _, _ in
                HTTPStubsResponse(error: networkError)
            }

            sut.add(PostHogEvent(event: "event1", distinctId: "id1"))
            sut.add(PostHogEvent(event: "event2", distinctId: "id2"))

            _ = getBatchedEvents(server)

            expect(sut.depth).toEventually(equal(2))
            expect(sut.currentBatchCapForTesting).toEventually(equal(4))

            sut.clear()
        }

        it("pops batch on non-retriable 4xx so a poison record cannot block the queue") {
            let sut = self.getSut(flushAt: 2, maxBatchSize: 4)
            server.batchResponseHandler = { _, _ in
                HTTPStubsResponse(jsonObject: [], statusCode: 401, headers: nil)
            }

            sut.add(PostHogEvent(event: "event1", distinctId: "id1"))
            sut.add(PostHogEvent(event: "event2", distinctId: "id2"))

            _ = getBatchedEvents(server)

            expect(sut.depth).toEventually(equal(0))
            expect(sut.currentBatchCapForTesting).toEventually(equal(4))

            sut.clear()
        }

        it("pops batch on 2xx and leaves cap unchanged (no ramp-up)") {
            let sut = self.getSut(flushAt: 2, maxBatchSize: 4)

            sut.add(PostHogEvent(event: "event1", distinctId: "id1"))
            sut.add(PostHogEvent(event: "event2", distinctId: "id2"))

            _ = getBatchedEvents(server)

            expect(sut.depth).toEventually(equal(0))
            // Cap was never reduced, so it should still be at maxBatchSize.
            expect(sut.currentBatchCapForTesting) == 4

            sut.clear()
        }
    }
}
