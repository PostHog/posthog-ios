//
//  PostHogQueueTest.swift
//  PostHogTests
//
//  Created by Manoel Aranda Neto on 30.10.23.
//

import Foundation
@testable import PostHog
import Testing

@Suite("PostHogQueue Tests", .serialized)
class PostHogQueueTest {
    let server: MockPostHogServer
    let apiKey: String

    init() {
        apiKey = uniqueApiKey()
        server = MockPostHogServer()
        server.start()
    }

    deinit {
        let config = PostHogConfig(apiKey: apiKey)
        let storage = PostHogStorage(config)
        storage.reset()
        server.stop()
    }

    func getSut(flushAt: Int = 1, maxQueueSize: Int = 1000) -> PostHogQueue {
        let config = PostHogConfig(apiKey: apiKey, host: "http://localhost:9001")
        config.flushAt = flushAt
        config.maxQueueSize = maxQueueSize
        config.sendFeatureFlagEvent = false
        let storage = PostHogStorage(config)
        let api = PostHogApi(config)
        return PostHogQueue(config, storage, api, .batch, nil)
    }

    @Test("add item to queue")
    func addItemToQueue() async throws {
        let sut = getSut()

        let event = PostHogEvent(event: "event", distinctId: "distinctId")
        sut.add(event)

        #expect(sut.depth == 1)

        let events = try await getServerEvents(server)
        #expect(events.count == 1)

        #expect(sut.depth == 0)

        sut.clear()
    }

    @Test("add item to queue and flush respecting flushAt")
    func addItemToQueueAndFlushRespectingFlushAt() async throws {
        let sut = getSut()

        let event = PostHogEvent(event: "event", distinctId: "distinctId")
        let event2 = PostHogEvent(event: "event2", distinctId: "distinctId2")
        sut.add(event)
        sut.add(event2)

        #expect(sut.depth == 2)

        let events = try await getServerEvents(server)
        #expect(events.count == 1)

        #expect(sut.depth == 1)

        sut.clear()
    }

    @Test("add item to queue and rotate queue")
    func addItemToQueueAndRotateQueue() async throws {
        let sut = getSut(flushAt: 3, maxQueueSize: 2)

        let event = PostHogEvent(event: "event", distinctId: "distinctId")
        let event2 = PostHogEvent(event: "event2", distinctId: "distinctId2")
        let event3 = PostHogEvent(event: "event3", distinctId: "distinctId3")
        sut.add(event)
        sut.add(event2)
        sut.add(event3)

        #expect(sut.depth == 2)

        sut.flush()

        let events = try await getServerEvents(server)

        #expect(events.count == 2)

        let first = events.first!
        let last = events.last!
        #expect(first.event == "event2")
        #expect(last.event == "event3")

        sut.clear()
    }
}
