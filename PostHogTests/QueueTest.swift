//
//  QueueTest.swift
//  PostHogTests
//
//  Created by Ben White on 08.02.23.
//

import Nimble
import Quick

@testable import PostHog

class QueueTest: QuickSpec {
    override func spec() {
        var queue: PostHogQueue!

        beforeEach {
            let config = PostHogConfig(apiKey: "test")
            let storage = PostHogStorage(config)
            let api = PostHogApi(config)
            queue = PostHogQueue(config, storage, api, nil)
        }

        it("Adds items to the queue") {
            queue.add(PostHogEvent(event: "event1", distinctId: "123"))
            queue.add(PostHogEvent(event: "event1", distinctId: "123"))
            queue.add(PostHogEvent(event: "event1", distinctId: "123"))

            expect(queue.depth) == 3
        }

        it("Consumes items from the queue") {
            var consumedEvents = [PostHogEvent]()
            let expectation = self.expectation(description: "Callback")

//            queue.consume { payload in
//                consumedEvents = payload.events
//                payload.completion(true)
//                expectation.fulfill()
//            }

            queue.add(PostHogEvent(event: "event1", distinctId: "123"))
            queue.add(PostHogEvent(event: "event2", distinctId: "123"))
            queue.add(PostHogEvent(event: "event3", distinctId: "123"))
            queue.flush()

            self.wait(for: [expectation], timeout: 5)

            expect(consumedEvents.count) == 3
            expect(consumedEvents[0].event) == "event1"
            expect(consumedEvents[1].event) == "event2"
            expect(consumedEvents[2].event) == "event3"
            expect(queue.depth) == 0
        }

        it("Returns processing to the queue if failed") {
            var consumedEvents = [PostHogEvent]()
            let expectation = self.expectation(description: "Callback")

//            queue.consume { payload in
//                consumedEvents = payload.events
//                payload.completion(false)
//                expectation.fulfill()
//            }

            queue.add(PostHogEvent(event: "event1", distinctId: "123"))
            queue.add(PostHogEvent(event: "event2", distinctId: "123"))
            queue.add(PostHogEvent(event: "event3", distinctId: "123"))
            queue.flush()

            self.wait(for: [expectation], timeout: 5)
            expect(consumedEvents.count) == 3
            expect(queue.depth) == 3
        }

        afterEach {
            queue.clear()
        }
    }
}
