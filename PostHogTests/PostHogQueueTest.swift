//
//  PostHogQueueTest.swift
//  PostHogTests
//
//  Created by Manoel Aranda Neto on 30.10.23.
//

import Foundation
import Nimble
@testable import PostHog
import Quick
import XCTest

class PostHogQueueTest: QuickSpec {
    func getSut() -> PostHogQueue {
        let config = PostHogConfig(apiKey: "123", host: "http://localhost:9001")
        config.flushAt = 1
        let storage = PostHogStorage(config)
        let api = PostHogApi(config)
        return PostHogQueue(config, storage, api, nil)
    }

    func getBatchedEvents(_ server: MockPostHogServer) -> [PostHogEvent] {
        let result = XCTWaiter.wait(for: [server.expectation(1)], timeout: 10.0)

        if result != XCTWaiter.Result.completed {
            XCTFail("The expected requests never arrived")
        }

        for request in server.requests.reversed() {
            if request.url?.path == "/batch" {
                return server.parsePostHogEvents(request)
            }
        }

        return []
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

            let events = self.getBatchedEvents(server)
            expect(events.count) == 1

            expect(sut.depth) == 0

            sut.clear()
        }

        it("add item to queue and flush respecting flushAt") {
            let sut = self.getSut()

            let event = PostHogEvent(event: "event", distinctId: "distinctId")
            let event2 = PostHogEvent(event: "event2", distinctId: "distinctId2")
            sut.add(event)
            sut.add(event2)

            expect(sut.depth) == 2

            let events = self.getBatchedEvents(server)
            expect(events.count) == 1

            expect(sut.depth) == 1

            sut.clear()
        }
    }
}
