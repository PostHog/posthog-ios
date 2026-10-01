import Foundation
@testable import PostHog
import Testing

@Suite("Replay batch boundaries", .serialized, .resetsGlobalState)
struct PostHogReplayBatchBoundaryTest {
    private final class Sender {
        private let lock = NSLock()
        private var requests: [[PostHogEvent]] = []
        private var completions: [(PostHogUploadInfo) -> Void] = []

        var batches: [[PostHogEvent]] { lock.withLock { requests } }

        func send(_ records: [PostHogEvent], completion: @escaping (PostHogUploadInfo) -> Void) {
            lock.withLock {
                requests.append(records)
                completions.append(completion)
            }
        }

        func complete(_ index: Int, status: Int) {
            let completion = lock.withLock { completions[index] }
            completion(PostHogUploadInfo(statusCode: status, error: nil))
        }
    }

    private func event(_ name: String, session: String = "a", identity: String = "anonymous") -> PostHogEvent {
        PostHogEvent(event: "$snapshot", distinctId: identity, properties: [
            "$session_id": session,
            "$snapshot_data": [["type": 2, "data": ["marker": name]]],
            "marker": name,
        ])
    }

    private func queue(_ config: PostHogConfig, _ sender: Sender, replay: Bool = true,
                       reachability: Reachability? = nil) -> PostHogQueue<PostHogEvent>
    {
        let api = PostHogApi(config)
        var endpoint = replay ? QueueEndpoint<PostHogEvent>.snapshot(api: api) : .batch(api: api)
        endpoint = QueueEndpoint(
            storageKey: endpoint.storageKey,
            oldStorageKeys: endpoint.oldStorageKeys,
            dispatchQueueLabel: endpoint.dispatchQueueLabel,
            initialCap: endpoint.initialCap,
            initialFlushAt: endpoint.initialFlushAt,
            maxQueueSize: endpoint.maxQueueSize,
            flushIntervalSeconds: endpoint.flushIntervalSeconds,
            rateCapMax: endpoint.rateCapMax,
            rateCapWindowSeconds: endpoint.rateCapWindowSeconds,
            encode: endpoint.encode,
            decode: endpoint.decode,
            describe: endpoint.describe,
            canBatchTogether: endpoint.canBatchTogether,
            send: sender.send,
            isRetriableStatusCode: endpoint.isRetriableStatusCode
        )
        return PostHogQueue(config, PostHogStorage(config), endpoint, reachability)
    }

    private func config(cap: Int = 50) -> PostHogConfig {
        let config = PostHogConfig(projectToken: UUID().uuidString, host: "http://localhost")
        config.flushAt = 100
        config.maxBatchSize = cap
        return config
    }

    private func flush(_ queue: PostHogQueue<PostHogEvent>, _ sender: Sender, count: Int) async throws {
        queue.flush()
        await waitUntil { sender.batches.count == count }
        try #require(sender.batches.count == count)
    }

    @Test("One flush sends every boundary group in its bounded window")
    func singleFlush() async throws {
        let sender = Sender()
        let queue = queue(config(cap: 4), sender)
        defer { queue.clear() }
        let events = [event("1"), event("2", session: "b"),
                      event("3", session: "b", identity: "identified"), event("4"),
                      event("outside", session: "c")]
        events.forEach { queue.add($0) }
        try await flush(queue, sender, count: 1)
        queue.add(event("appended", session: "d"))
        queue.flush() // An overlapping trigger must not claim another window.
        for index in 0 ..< 4 {
            await waitUntil { sender.batches.count == index + 1 }
            try #require(sender.batches.count == index + 1)
            #expect(sender.batches[index].map(\.uuid) == [events[index].uuid])
            sender.complete(index, status: 200)
        }
        try await Task.sleep(nanoseconds: 50_000_000)
        #expect(sender.batches.count == 4)
        #expect(queue.depth == 2)
        // The cap-excluded and concurrently appended entries are still eligible.
        try await flush(queue, sender, count: 5)
        sender.complete(4, status: 200)
        await waitUntil { sender.batches.count == 6 }
        try #require(sender.batches.count == 6)
        sender.complete(5, status: 200)
        #expect(queue.depth == 0)
    }

    @Test("A failed group stops continuation and preserves the remaining window", arguments: [503, -1, 413])
    func failureStopsContinuation(status: Int) async throws {
        let clock = MockDate()
        now = { clock.date }
        defer { now = { Date() } }
        let sender = Sender()
        let queue = queue(config(), sender)
        defer { queue.clear() }
        let events = [event("first"), event("second", session: "b"),
                      event("third", session: "b"), event("later", session: "c")]
        events.forEach { queue.add($0) }
        try await flush(queue, sender, count: 1)
        sender.complete(0, status: 200)
        await waitUntil { sender.batches.count == 2 }
        try #require(sender.batches.count == 2)
        sender.complete(1, status: status)
        try await Task.sleep(nanoseconds: 50_000_000)
        #expect(sender.batches.count == 2)
        #expect(queue.fileQueue.peekEntries(4).compactMap { PostHogEvent.fromJSON($0.data)?.uuid } == events.dropFirst().map(\.uuid))
        clock.date.addTimeInterval(60)
        try await flush(queue, sender, count: 3)
        #expect(sender.batches[2].first?.uuid == events[1].uuid)
        sender.complete(2, status: 200)
    }

    @Test("Stopping an in-flight flush leaves later groups for the next queue")
    func stopBetweenGroups() async throws {
        let config = config()
        let sender = Sender()
        let previous = queue(config, sender)
        defer { previous.clear() }
        previous.add(event("first"))
        let later = event("later", session: "b")
        previous.add(later)
        try await flush(previous, sender, count: 1)
        previous.stop()
        let reopenedSender = Sender()
        sender.complete(0, status: 200)
        try await Task.sleep(nanoseconds: 50_000_000)
        #expect(sender.batches.count == 1)
        #expect(previous.depth == 1)
        // A new queue owns the persisted tail; the stopped queue must not send it too.
        let reopened = queue(config, reopenedSender)
        try await flush(reopened, reopenedSender, count: 1)
        #expect(reopenedSender.batches[0].map(\.uuid) == [later.uuid])
        reopenedSender.complete(0, status: 200)
        #expect(reopened.depth == 0)
    }

    @Test("Reachability pauses continuation between groups")
    func pauseBetweenGroups() async throws {
        let reachability = try Reachability(notificationQueue: nil)
        let sender = Sender()
        let queue = queue(config(), sender, reachability: reachability)
        queue.start(disableReachabilityForTesting: false, disableQueueTimerForTesting: true)
        reachability.stopNotifier()
        defer { queue.clear()
            queue.stop()
        }
        queue.add(event("first"))
        queue.add(event("later", session: "b"))
        try await flush(queue, sender, count: 1)
        reachability.onUnreachable.invoke(reachability)
        sender.complete(0, status: 200)
        try await Task.sleep(nanoseconds: 50_000_000)
        #expect(sender.batches.count == 1)
        #expect(queue.depth == 1)
        reachability.onReachable.invoke(reachability)
        await waitUntil { sender.batches.count == 2 }
        try #require(sender.batches.count == 2)
        sender.complete(1, status: 200)
        #expect(queue.depth == 0)
    }

    @Test("Terminal responses continue to the next group", arguments: [400, 413])
    func terminalContinues(status: Int) async throws {
        let sender = Sender()
        let queue = queue(config(), sender)
        defer { queue.clear() }
        queue.add(event("first"))
        queue.add(event("later", session: "b"))
        try await flush(queue, sender, count: 1)
        sender.complete(0, status: status)
        await waitUntil { sender.batches.count == 2 }
        try #require(sender.batches.count == 2)
        #expect(queue.depth == 1)
        sender.complete(1, status: 200)
        #expect(queue.depth == 0)
    }

    @Test("Session and identity changes split FIFO batches, including repeated keys")
    func splitsBoundaries() async throws {
        let sender = Sender()
        let queue = queue(config(), sender)
        defer { queue.clear() }
        let events = [event("1"), event("2"), event("3", session: "b"),
                      event("4", session: "b", identity: "identified"), event("5")]
        events.forEach { queue.add($0) }
        let expectedSizes = [2, 1, 1, 1]
        for (index, size) in expectedSizes.enumerated() {
            try await flush(queue, sender, count: index + 1)
            #expect(sender.batches[index].count == size)
            sender.complete(index, status: 200)
        }
        #expect(queue.depth == 0)
        #expect(sender.batches.flatMap { $0 }.map(\.uuid) == events.map(\.uuid))
    }

    @Test("Persisted snapshots retain boundaries after queue reconstruction")
    func persistedBoundary() async throws {
        let config = config()
        let sender = Sender()
        var previous: PostHogQueue<PostHogEvent>? = queue(config, sender)
        previous!.add(event("old"))
        previous!.stop()
        previous = nil
        let next = queue(config, sender)
        defer { next.clear() }
        next.add(event("new", session: "b"))
        try await flush(next, sender, count: 1)
        #expect(sender.batches[0].map { $0.properties["$session_id"] as? String } == ["a"])
        sender.complete(0, status: 200)
        #expect(next.depth == 1)
        try await flush(next, sender, count: 2)
        #expect(sender.batches[1].map { $0.properties["$session_id"] as? String } == ["b"])
        sender.complete(1, status: 200)
        #expect(next.depth == 0)
    }

    @Test("Homogeneous batches honor the configured cap")
    func respectsCap() async throws {
        let sender = Sender()
        let queue = queue(config(cap: 2), sender)
        defer { queue.clear() }
        (1 ... 5).forEach { queue.add(event(String($0))) }
        for (index, size) in [2, 2, 1].enumerated() {
            try await flush(queue, sender, count: index + 1)
            #expect(sender.batches[index].count == size)
            sender.complete(index, status: 200)
        }
        #expect(queue.depth == 0)
    }

    @Test("Upload disposition preserves the boundary and concurrent appends", arguments: [200, 400, 503, 413])
    func disposition(status: Int) async throws {
        let clock = MockDate()
        now = { clock.date }
        defer { now = { Date() } }
        let sender = Sender()
        let queue = queue(config(), sender)
        defer { queue.clear() }
        queue.add(event("first"))
        queue.add(event("second"))
        queue.add(event("later", session: "b"))
        let originalIds = queue.fileQueue.peekEntries(3).map(\.id)
        try await flush(queue, sender, count: 1)
        #expect(sender.batches[0].count == 2)
        queue.add(event("appended", session: "c"))
        sender.complete(0, status: status)
        let retained = queue.fileQueue.peekEntries(4).map(\.id)
        if status == 503 || status == 413 {
            #expect(Array(retained.prefix(3)) == originalIds)
            #expect(queue.depth == 4)
            clock.date.addTimeInterval(60)
            try await flush(queue, sender, count: 2)
            #expect(sender.batches[1].count == (status == 413 ? 1 : 2))
            #expect(sender.batches[1].allSatisfy { $0.properties["$session_id"] as? String == "a" })
            sender.complete(1, status: 200)
        } else {
            #expect(retained.first == originalIds.last)
            #expect(queue.depth == 2)
        }
    }

    @Test("Unreadable entries do not remove snapshots beyond the boundary")
    func unreadableEntries() async throws {
        let sender = Sender()
        let queue = queue(config(), sender)
        defer { queue.clear() }
        queue.fileQueue.add(Data("invalid".utf8))
        queue.add(event("first"))
        queue.fileQueue.add(Data("invalid".utf8))
        queue.add(event("later", session: "b"))
        let laterId = try #require(queue.fileQueue.peekEntries(4).last?.id)
        try await flush(queue, sender, count: 1)
        #expect(sender.batches[0].count == 1)
        sender.complete(0, status: 200)
        #expect(queue.fileQueue.peekEntries(4).map(\.id) == [laterId])
    }
}
