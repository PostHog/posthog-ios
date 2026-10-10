//
//  PostHogQueueTest.swift
//  PostHogTests
//
//  Created by Manoel Aranda Neto on 30.10.23.
//

import Foundation
import OHHTTPStubs
import OHHTTPStubsSwift
@testable import PostHog
import Testing

private final class ControlledBatchSender {
    private let lock = NSLock()
    private var completions = [(PostHogUploadInfo) -> Void]()
    private var recordedBatches = [[PostHogEvent]]()

    var batches: [[PostHogEvent]] {
        lock.withLock { recordedBatches }
    }

    var requestCount: Int {
        lock.withLock { completions.count }
    }

    func send(_ events: [PostHogEvent], completion: @escaping (PostHogUploadInfo) -> Void) {
        lock.withLock {
            recordedBatches.append(events)
            completions.append(completion)
        }
    }

    /// Records an issue instead of trapping when the request never arrived, so one late request
    /// fails this test rather than crashing the whole test process.
    func completeRequest(at index: Int, with result: PostHogUploadInfo, sourceLocation: SourceLocation = #_sourceLocation) {
        let completion = lock.withLock { index < completions.count ? completions[index] : nil }
        guard let completion else {
            Issue.record("No request at index \(index); only \(requestCount) arrived", sourceLocation: sourceLocation)
            return
        }
        completion(result)
    }
}

@Suite("PostHog queue", .serialized, .resetsGlobalState)
final class PostHogQueueTest {
    private var cleanupJobs = [() -> Void]()
    private let server: MockPostHogServer

    init() {
        deleteSafely(applicationSupportDirectoryURL())
        server = MockPostHogServer()
        server.start()
    }

    deinit {
        cleanupJobs.forEach { $0() }
        cleanupJobs.removeAll()
        server.stop()
    }

    /// Polls until `value` equals `expected` (up to 30s, the old polling ceiling), then asserts it.
    private func expectEventually<T: Equatable>(
        _ value: () -> T,
        _ expected: T,
        sourceLocation: SourceLocation = #_sourceLocation
    ) async {
        await waitUntil(timeout: 30) { value() == expected }
        let actual = value()
        #expect(actual == expected, sourceLocation: sourceLocation)
    }

    /// Waits for an upload-processed latch (formerly an `XCTestExpectation` + `XCTWaiter.wait`) and
    /// asserts it was signaled before the timeout.
    private func expectSignaled(_ latch: AsyncLatch, sourceLocation: SourceLocation = #_sourceLocation) async {
        await latch.wait(timeout: testRequestTimeout)
        #expect(latch.isSignaled, sourceLocation: sourceLocation)
    }

    private func getSut(flushAt: Int = 1, maxQueueSize: Int = 1000, maxBatchSize: Int = 50, maxRetries: Int = 3, sender: ControlledBatchSender? = nil, afterUpload: (() -> Void)? = nil) -> PostHogQueue<PostHogEvent> {
        let config = PostHogConfig(projectToken: UUID().uuidString, host: "http://localhost:9001")
        config.flushAt = flushAt
        config.maxQueueSize = maxQueueSize
        config.maxBatchSize = maxBatchSize
        config.maxRetries = maxRetries
        config.sendFeatureFlagEvent = false
        let storage = PostHogStorage(config)
        let api = PostHogApi(config)
        let base = QueueEndpoint<PostHogEvent>.batch(api: api)
        let endpoint = QueueEndpoint<PostHogEvent>(
            storageKey: base.storageKey,
            oldStorageKeys: base.oldStorageKeys,
            dispatchQueueLabel: base.dispatchQueueLabel,
            initialCap: base.initialCap,
            initialFlushAt: base.initialFlushAt,
            maxQueueSize: base.maxQueueSize,
            flushIntervalSeconds: base.flushIntervalSeconds,
            rateCapMax: base.rateCapMax,
            rateCapWindowSeconds: base.rateCapWindowSeconds,
            encode: base.encode,
            decode: base.decode,
            describe: base.describe,
            recordId: base.recordId,
            send: { events, completion in
                let send = sender?.send ?? base.send
                send(events) { result in
                    completion(result)
                    afterUpload?()
                }
            },
            isRetriableStatusCode: base.isRetriableStatusCode
        )
        let sut = PostHogQueue(config, storage, endpoint, nil)
        // Only count capture requests from this fixture's queue: the stub and the activation hook are
        // process-global, so a stray request from another queue/SDK instance would otherwise shift
        // batchRequests.count and the request number the batchResponseHandler keys on.
        server.batchProjectToken = config.projectToken
        cleanupJobs.append {
            sut.stop()
            sut.clear()
            deleteSafely(storage.appFolderUrl)
        }
        return sut
    }

    @Test("isolates storage between queue fixtures")
    func isolatesStorageBetweenQueueFixtures() {
        let first = getSut(flushAt: 100)
        let second = getSut(flushAt: 100)
        defer {
            first.clear()
            second.clear()
        }
        second.add(PostHogEvent(event: "retained", distinctId: "id"))
        first.clear()
        #expect(second.fileQueue.peek(10).count == 1)
    }

    @Test("add item to queue")
    func addItemToQueue() async {
        let sut = getSut()

        let event = PostHogEvent(event: "event", distinctId: "distinctId")
        sut.add(event)

        #expect(sut.depth == 1)

        let events = getBatchedEvents(server)
        #expect(events.count == 1)

        // getBatchedEvents only waits for the request to arrive; the queue pops the batch after
        // the response is processed, so poll rather than assert synchronously.
        await expectEventually({ sut.depth }, 0)

        sut.clear()
    }

    @Test("add item to queue and flush respecting flushAt")
    func addItemToQueueAndFlushRespectingFlushAt() async {
        let sender = ControlledBatchSender()
        let sut = getSut(flushAt: 2, sender: sender)

        let event = PostHogEvent(event: "event", distinctId: "distinctId")
        let event2 = PostHogEvent(event: "event2", distinctId: "distinctId2")
        let event3 = PostHogEvent(event: "event3", distinctId: "distinctId3")

        sut.add(event)
        #expect(sut.depth == 1)

        #expect(sender.requestCount == 0)
        sut.add(event2)
        await expectEventually({ sender.requestCount }, 1)
        #expect(sender.batches.first?.map(\.event) == ["event", "event2"])
        #expect(sut.depth == 2)
        sender.completeRequest(at: 0, with: PostHogUploadInfo(statusCode: 200, error: nil))
        #expect(sut.depth == 0)

        sut.add(event3)
        #expect(sut.depth == 1)
        #expect(sender.requestCount == 1)

        sut.clear()
    }

    @Test("add item to queue and rotate queue")
    func addItemToQueueAndRotateQueue() throws {
        let sut = getSut(flushAt: 3, maxQueueSize: 2)

        let event = PostHogEvent(event: "event", distinctId: "distinctId")
        let event2 = PostHogEvent(event: "event2", distinctId: "distinctId2")
        let event3 = PostHogEvent(event: "event3", distinctId: "distinctId3")
        sut.add(event)
        sut.add(event2)
        sut.add(event3)

        #expect(sut.depth == 2)

        sut.flush()

        let events = getBatchedEvents(server)

        #expect(events.count == 2)

        let first = try #require(events.first)
        let last = try #require(events.last)
        #expect(first.event == "event2")
        #expect(last.event == "event3")

        sut.clear()
    }

    @Test("halves both batch cap and flush threshold and retains batch on HTTP 413 when cap > 1")
    func halvesBatchCapAndFlushAtOn413WhenCapAboveOne() async {
        let sut = getSut(flushAt: 4, maxBatchSize: 4)
        server.batchResponseHandler = { _, _ in
            HTTPStubsResponse(jsonObject: [], statusCode: 413, headers: nil)
        }

        for i in 0 ..< 4 {
            sut.add(PostHogEvent(event: "event\(i)", distinctId: "id\(i)"))
        }

        _ = getBatchedEvents(server)

        await expectEventually({ sut.currentBatchCapForTesting }, 2)
        await expectEventually({ sut.currentFlushAtForTesting }, 2)
        await expectEventually({ sut.depth }, 4)

        sut.clear()
    }

    @Test("halves cap based on actual batch size when queue depth was below cap")
    func halvesCapBasedOnActualBatchSizeWhenQueueDepthWasBelowCap() async {
        // cap=10, but only 4 events were sent (queue depth was below cap).
        // Halve from `min(cap, batchSize)` = 4 → cap = 2, not 5. Avoids
        // wasted halvings on a cap that wasn't reached anyway.
        let sut = getSut(flushAt: 4, maxBatchSize: 10)
        server.batchResponseHandler = { _, _ in
            HTTPStubsResponse(jsonObject: [], statusCode: 413, headers: nil)
        }

        for i in 0 ..< 4 {
            sut.add(PostHogEvent(event: "event\(i)", distinctId: "id\(i)"))
        }

        _ = getBatchedEvents(server)

        await expectEventually({ sut.currentBatchCapForTesting }, 2)
        await expectEventually({ sut.depth }, 4)

        sut.clear()
    }

    @Test("clamps flushAt to cap on halve so we don't buffer more than a batch")
    func clampsFlushAtToCapOnHalve() async {
        // cap=20, flushAt=10. A 413 fires on a partial batch of 2 events.
        // Cap halves aggressively (min(20, 2) / 2 = 1) while flushAt would
        // halve to 5 — leaving flushAt > cap and piling 5 events to send
        // 1 at a time. Clamping flushAt to cap keeps them in step.
        let sut = getSut(flushAt: 10, maxBatchSize: 20)
        server.batchResponseHandler = { _, _ in
            HTTPStubsResponse(jsonObject: [], statusCode: 413, headers: nil)
        }

        for i in 0 ..< 2 {
            sut.add(PostHogEvent(event: "event\(i)", distinctId: "id\(i)"))
        }
        sut.flush()

        _ = getBatchedEvents(server)

        await expectEventually({ sut.currentBatchCapForTesting }, 1)
        await expectEventually({ sut.currentFlushAtForTesting }, 1)

        sut.clear()
    }

    @Test("drops batch on HTTP 413 when cap is already 1")
    func dropsBatchOn413WhenCapIsAlreadyOne() async {
        let sut = getSut(flushAt: 1, maxBatchSize: 1)
        server.batchResponseHandler = { _, _ in
            HTTPStubsResponse(jsonObject: [], statusCode: 413, headers: nil)
        }

        sut.add(PostHogEvent(event: "oversized", distinctId: "id"))

        _ = getBatchedEvents(server)

        await expectEventually({ sut.depth }, 0)
        // Cap stays at 1 — no reset to maxBatchSize, matching Android.
        #expect(sut.currentBatchCapForTesting == 1)

        sut.clear()
    }

    @Test("retains batch on retriable 5xx and does not change cap")
    func retainsBatchOnRetriable5xxAndDoesNotChangeCap() async {
        let sut = getSut(flushAt: 2, maxBatchSize: 4)
        server.batchResponseHandler = { _, _ in
            HTTPStubsResponse(jsonObject: [], statusCode: 500, headers: nil)
        }

        sut.add(PostHogEvent(event: "event1", distinctId: "id1"))
        sut.add(PostHogEvent(event: "event2", distinctId: "id2"))

        _ = getBatchedEvents(server)

        await expectEventually({ sut.depth }, 2)
        await expectEventually({ sut.currentBatchCapForTesting }, 4)

        sut.clear()
    }

    @Test("caps Retry-After at the maximum retry delay", arguments: [("5", 5.0), ("3600", maxRetryDelay)])
    func capsRetryAfter(retryAfter: String, expectedDelay: TimeInterval) async throws {
        try await withMockedClock { clock in
            let uploaded = AsyncLatch()
            let sut = getSut(flushAt: 100) { uploaded.signal() }
            server.batchResponseHandler = { _, _ in
                HTTPStubsResponse(jsonObject: [], statusCode: 503, headers: ["Retry-After": retryAfter])
            }

            sut.add(PostHogEvent(event: "event", distinctId: "id"))
            sut.flush()
            await expectSignaled(uploaded)

            let pausedUntil = try #require(sut.pausedUntilForTesting)
            #expect(abs(pausedUntil.timeIntervalSince(clock.date) - expectedDelay) < 0.001)
            sut.clear()
        }
    }

    @Test("pops batch on HTTP 429 (terminal for capture V1) and does not change cap")
    func popsBatchOnHTTP429AndDoesNotChangeCap() async {
        let sut = getSut(flushAt: 2, maxBatchSize: 4)
        server.batchResponseHandler = { _, _ in
            HTTPStubsResponse(jsonObject: [], statusCode: 429, headers: nil)
        }

        sut.add(PostHogEvent(event: "event1", distinctId: "id1"))
        sut.add(PostHogEvent(event: "event2", distinctId: "id2"))

        _ = getBatchedEvents(server)

        await expectEventually({ sut.depth }, 0)
        await expectEventually({ sut.currentBatchCapForTesting }, 4)

        sut.clear()
    }

    @Test("retains batch on HTTP 408 (request timeout is retriable) and does not change cap")
    func retainsBatchOnHTTP408AndDoesNotChangeCap() async {
        let sut = getSut(flushAt: 2, maxBatchSize: 4)
        server.batchResponseHandler = { _, _ in
            HTTPStubsResponse(jsonObject: [], statusCode: 408, headers: nil)
        }

        sut.add(PostHogEvent(event: "event1", distinctId: "id1"))
        sut.add(PostHogEvent(event: "event2", distinctId: "id2"))

        _ = getBatchedEvents(server)

        await expectEventually({ sut.depth }, 2)
        await expectEventually({ sut.currentBatchCapForTesting }, 4)

        sut.clear()
    }

    @Test("retains retryable HTTP failures past maxRetries and drains after recovery")
    func retainsRetryableHTTPFailuresPastMaxRetriesAndDrainsAfterRecovery() async {
        let mockNow = MockDate()
        now = { mockNow.date }
        defer { now = { Date() } }

        let uploads = (1 ... 6).map { _ in AsyncLatch() }
        var uploadIndex = 0
        let sut = getSut(flushAt: 100, maxBatchSize: 4, maxRetries: 1) {
            guard uploadIndex < uploads.count else {
                Issue.record("Unexpected extra upload #\(uploadIndex + 1)")
                return
            }
            let upload = uploads[uploadIndex]
            uploadIndex += 1
            upload.signal()
        }
        server.start(batchCount: 6)
        server.batchResponseHandler = { _, requestNumber in
            requestNumber <= 3 || requestNumber == 5
                ? HTTPStubsResponse(jsonObject: [], statusCode: 503, headers: nil)
                : HTTPStubsResponse(jsonObject: ["status": "ok"], statusCode: 200, headers: nil)
        }

        sut.add(PostHogEvent(event: "event1", distinctId: "id1"))
        sut.add(PostHogEvent(event: "event2", distinctId: "id2"))

        for expectedAttempt in 1 ... 3 {
            sut.flush()
            await expectEventually({ server.batchRequests.count }, expectedAttempt)
            await expectSignaled(uploads[expectedAttempt - 1])
            #expect(sut.currentRetryCountForTesting == expectedAttempt)
            #expect(sut.depth == 2)
            mockNow.date.addTimeInterval(60)
        }

        sut.flush()
        await expectSignaled(uploads[3])
        #expect(server.batchRequests.count == 4)
        #expect(sut.depth == 0)
        #expect(sut.currentRetryCountForTesting == 0)

        sut.add(PostHogEvent(event: "fresh", distinctId: "id3"))
        sut.flush()
        await expectSignaled(uploads[4])
        #expect(server.batchRequests.count == 5)
        #expect(sut.currentRetryCountForTesting == 1)
        #expect(sut.depth == 1)
        sut.flush()
        #expect(server.batchRequests.count == 5)
        mockNow.date.addTimeInterval(1)
        sut.flush()
        await expectSignaled(uploads[5])
        #expect(server.batchRequests.count == 6)
        await expectEventually({ sut.depth }, 0)
        await expectEventually({ sut.currentRetryCountForTesting }, 0)

        sut.clear()
    }

    @Test("retains transport failures past maxRetries and drains after recovery")
    func retainsTransportFailuresPastMaxRetriesAndDrainsAfterRecovery() async {
        let mockNow = MockDate()
        now = { mockNow.date }
        defer { now = { Date() } }

        let uploads = (1 ... 4).map { _ in AsyncLatch() }
        var uploadIndex = 0
        let sut = getSut(flushAt: 100, maxBatchSize: 4, maxRetries: 0) {
            guard uploadIndex < uploads.count else {
                Issue.record("Unexpected extra upload #\(uploadIndex + 1)")
                return
            }
            let upload = uploads[uploadIndex]
            uploadIndex += 1
            upload.signal()
        }
        let networkError = NSError(domain: NSURLErrorDomain, code: NSURLErrorNetworkConnectionLost, userInfo: nil)
        server.start(batchCount: 4)
        server.batchResponseHandler = { _, requestNumber in
            requestNumber <= 3
                ? HTTPStubsResponse(error: networkError)
                : HTTPStubsResponse(jsonObject: ["status": "ok"], statusCode: 200, headers: nil)
        }

        sut.add(PostHogEvent(event: "event1", distinctId: "id1"))
        sut.add(PostHogEvent(event: "event2", distinctId: "id2"))

        for expectedAttempt in 1 ... 3 {
            sut.flush()
            await expectEventually({ server.batchRequests.count }, expectedAttempt)
            await expectSignaled(uploads[expectedAttempt - 1])
            #expect(sut.currentRetryCountForTesting == expectedAttempt)
            #expect(sut.depth == 2)
            mockNow.date.addTimeInterval(60)
        }

        sut.flush()
        await expectSignaled(uploads[3])
        #expect(server.batchRequests.count == 4)
        await expectEventually({ sut.depth }, 0)

        sut.clear()
    }

    @Test("late success removes exact in-flight identities after full-capacity replacement")
    func lateSuccessRemovesExactInFlightIdentitiesAfterFullCapacityReplacement() async {
        let config = PostHogConfig(projectToken: "queue_identity_\(UUID().uuidString)", host: "http://localhost:9001")
        config.flushAt = 100
        config.maxQueueSize = 2
        config.maxBatchSize = 2
        let storage = PostHogStorage(config)
        let sender = ControlledBatchSender()
        let endpoint = QueueEndpoint<PostHogEvent>(
            storageKey: .queue,
            oldStorageKeys: [],
            dispatchQueueLabel: "com.posthog.Queue.IdentityTest",
            initialCap: { $0.maxBatchSize },
            initialFlushAt: { $0.flushAt },
            maxQueueSize: { $0.maxQueueSize },
            flushIntervalSeconds: { $0.flushIntervalSeconds },
            rateCapMax: { _ in 0 },
            rateCapWindowSeconds: { _ in 0 },
            encode: { toJSONData($0.toJSON()) },
            decode: { PostHogEvent.fromJSON($0) },
            describe: { $0.event },
            send: sender.send,
            isRetriableStatusCode: { _ in false }
        )
        let sut = PostHogQueue(config, storage, endpoint, nil)
        defer { sut.clear() }
        let identicalEvent = PostHogEvent(event: "identical", distinctId: "same-id")

        sut.add(identicalEvent)
        sut.add(identicalEvent)
        let inFlightIds = sut.fileQueue.peekEntries(2).map(\.id)

        sut.flush()
        await expectEventually({ sender.requestCount }, 1)

        // Replace the entire in-flight batch with byte-identical payloads.
        sut.add(identicalEvent)
        sut.add(identicalEvent)
        let replacementIds = sut.fileQueue.peekEntries(2).map(\.id)
        #expect(Set(inFlightIds).isDisjoint(with: replacementIds))

        sender.completeRequest(at: 0, with: PostHogUploadInfo(statusCode: 200, error: nil))

        await expectEventually({ sut.depth }, 2)
        #expect(sut.fileQueue.peekEntries(2).map(\.id) == replacementIds)

        sut.flush()
        await expectEventually({ sender.requestCount }, 2)
        sender.completeRequest(at: 1, with: PostHogUploadInfo(statusCode: 200, error: nil))
        await expectEventually({ sut.depth }, 0)
    }

    @Test("halves cap repeatedly across multiple 413s and drops once cap reaches 1")
    func halvesCapRepeatedlyAcrossMultiple413sAndDropsAtOne() async {
        // flushAt is high so add() doesn't trigger an auto-flush — we drive
        // each flush manually to observe the multi-step halving sequence.
        let uploads = (1 ... 3).map { _ in AsyncLatch() }
        var uploadIndex = 0
        let sut = getSut(flushAt: 100, maxBatchSize: 4, maxRetries: 0) {
            guard uploadIndex < uploads.count else {
                Issue.record("Unexpected extra upload #\(uploadIndex + 1)")
                return
            }
            let upload = uploads[uploadIndex]
            uploadIndex += 1
            upload.signal()
        }
        server.start(batchCount: 3)
        server.batchResponseHandler = { _, _ in
            HTTPStubsResponse(jsonObject: [], statusCode: 413, headers: nil)
        }

        for i in 0 ..< 4 {
            sut.add(PostHogEvent(event: "event\(i)", distinctId: "id\(i)"))
        }

        // First flush: batch=4 → 413 → cap halves to 2, batch retained.
        sut.flush()
        await expectSignaled(uploads[0])
        #expect(sut.currentBatchCapForTesting == 2)
        #expect(sut.depth == 4)

        // Second flush: batch=2 → 413 → cap halves to 1, batch retained.
        sut.flush()
        await expectSignaled(uploads[1])
        #expect(sut.currentBatchCapForTesting == 1)
        #expect(sut.depth == 4)

        // Third flush: batch=1, cap already at 1 → drop one record. Cap
        // stays at 1 (no reset, matching Android).
        sut.flush()
        await expectSignaled(uploads[2])
        #expect(sut.depth == 3)
        #expect(sut.currentBatchCapForTesting == 1)

        sut.clear()
    }

    @Test("pops batch on 5xx codes outside the narrow retriable set")
    func popsBatchOn5xxCodesOutsideTheNarrowRetriableSet() async {
        // 501/505/etc. are NOT in the narrow 5xx retriable set
        // {500, 502, 503, 504}. Treat as non-retriable so a poison
        // record can't block the queue.
        let upload = AsyncLatch()
        let sut = getSut(flushAt: 2, maxBatchSize: 4) { upload.signal() }
        server.batchResponseHandler = { _, _ in
            HTTPStubsResponse(jsonObject: [], statusCode: 501, headers: nil)
        }

        sut.add(PostHogEvent(event: "event1", distinctId: "id1"))
        sut.add(PostHogEvent(event: "event2", distinctId: "id2"))

        _ = getBatchedEvents(server)
        await expectSignaled(upload)

        #expect(sut.depth == 0)
        #expect(sut.currentBatchCapForTesting == 4)

        sut.clear()
    }

    @Test("retains batch on a network error")
    func retainsBatchOnANetworkError() async {
        let sut = getSut(flushAt: 2, maxBatchSize: 4)
        let networkError = NSError(domain: NSURLErrorDomain, code: NSURLErrorNotConnectedToInternet, userInfo: nil)
        server.batchResponseHandler = { _, _ in
            HTTPStubsResponse(error: networkError)
        }

        sut.add(PostHogEvent(event: "event1", distinctId: "id1"))
        sut.add(PostHogEvent(event: "event2", distinctId: "id2"))

        _ = getBatchedEvents(server)

        await expectEventually({ sut.depth }, 2)
        await expectEventually({ sut.currentBatchCapForTesting }, 4)

        sut.clear()
    }

    @Test("pops batch on non-retriable 4xx so a poison record cannot block the queue")
    func popsBatchOnNonRetriable4xx() async {
        let sut = getSut(flushAt: 2, maxBatchSize: 4)
        server.batchResponseHandler = { _, _ in
            HTTPStubsResponse(jsonObject: [], statusCode: 401, headers: nil)
        }

        sut.add(PostHogEvent(event: "event1", distinctId: "id1"))
        sut.add(PostHogEvent(event: "event2", distinctId: "id2"))

        _ = getBatchedEvents(server)

        await expectEventually({ sut.depth }, 0)
        await expectEventually({ sut.currentBatchCapForTesting }, 4)

        sut.clear()
    }

    @Test("pops batch on 2xx and leaves cap unchanged (no ramp-up)")
    func popsBatchOn2xxAndLeavesCapUnchangedNoRampUp() async {
        let sut = getSut(flushAt: 2, maxBatchSize: 4)

        sut.add(PostHogEvent(event: "event1", distinctId: "id1"))
        sut.add(PostHogEvent(event: "event2", distinctId: "id2"))

        _ = getBatchedEvents(server)

        await expectEventually({ sut.depth }, 0)
        // Cap was never reduced, so it should still be at maxBatchSize.
        #expect(sut.currentBatchCapForTesting == 4)

        sut.clear()
    }
}

@Suite("PostHog queue upload disposition", .serialized, .resetsGlobalState)
struct PostHogQueueUploadDispositionTest {
    private func makeQueue(snapshot: Bool, sender: ControlledBatchSender) -> PostHogQueue<PostHogEvent> {
        let config = PostHogConfig(projectToken: "queue_disposition_\(UUID().uuidString)", host: "http://localhost:9001")
        config.flushAt = 100
        config.maxBatchSize = 4
        config.maxRetries = 0
        let api = PostHogApi(config)
        let base: QueueEndpoint<PostHogEvent> = snapshot ? .snapshot(api: api) : .batch(api: api)
        let endpoint = QueueEndpoint<PostHogEvent>(
            storageKey: base.storageKey,
            oldStorageKeys: [],
            dispatchQueueLabel: base.dispatchQueueLabel,
            initialCap: base.initialCap,
            initialFlushAt: base.initialFlushAt,
            maxQueueSize: base.maxQueueSize,
            flushIntervalSeconds: base.flushIntervalSeconds,
            rateCapMax: base.rateCapMax,
            rateCapWindowSeconds: base.rateCapWindowSeconds,
            encode: base.encode,
            decode: base.decode,
            describe: base.describe,
            recordId: base.recordId,
            canBatchTogether: base.canBatchTogether,
            send: sender.send,
            isRetriableStatusCode: base.isRetriableStatusCode
        )
        return PostHogQueue(config, PostHogStorage(config), endpoint, nil)
    }

    private func waitForRequest(_ count: Int, sender: ControlledBatchSender) async throws {
        await waitUntil { sender.requestCount == count }
        try #require(sender.requestCount == count)
    }

    @Test("received HTTP disposition wins over an accompanying transport error", arguments: [-1, 200, 400, 408, 429, 503], [false, true])
    func receivedHTTPDisposition(statusCode: Int, snapshot: Bool) async throws {
        let sender = ControlledBatchSender()
        let queue = makeQueue(snapshot: snapshot, sender: sender)
        defer { queue.clear() }
        queue.add(PostHogEvent(event: "sent", distinctId: "id"))
        let sentIds = queue.fileQueue.peekEntries(1).map(\.id)
        queue.flush()
        try await waitForRequest(1, sender: sender)
        queue.add(PostHogEvent(event: "not-sent", distinctId: "id"))
        let allIds = queue.fileQueue.peekEntries(2).map(\.id)
        let response = statusCode == -1 ? nil : HTTPURLResponse(
            url: try #require(URL(string: "http://localhost/batch")),
            statusCode: statusCode, httpVersion: nil, headerFields: nil
        )
        processUploadResponse(endpointName: "test", data: nil, response: response, error: URLError(.networkConnectionLost)) {
            sender.completeRequest(at: 0, with: $0)
        }

        // 429 is terminal for capture V1 (events) but retried by /snapshot.
        let retryable = [-1, 408, 503].contains(statusCode) || (snapshot && statusCode == 429)
        let expectedIds = retryable ? allIds : allIds.filter { !sentIds.contains($0) }
        #expect(queue.fileQueue.peekEntries(2).map(\.id) == expectedIds)
        #expect(queue.currentRetryCountForTesting == (retryable ? 1 : 0))
        let reloaded = PostHogFileBackedQueue(queue: queue.fileQueue.queue)
        #expect(Set(reloaded.peekEntries(2).map(\.id)) == Set(expectedIds))
    }

    @Test("413 reaches singleton after retryable failures and preserves later records", arguments: [false, true])
    func shrinkingAfterRetryableFailures(snapshot: Bool) async throws {
        let mockNow = MockDate()
        now = { mockNow.date }
        defer { now = { Date() } }
        let sender = ControlledBatchSender()
        let queue = makeQueue(snapshot: snapshot, sender: sender)
        defer { queue.clear() }
        for name in ["poison", "later-1", "later-2", "later-3"] {
            queue.add(PostHogEvent(event: name, distinctId: "id"))
        }
        let originalIds = queue.fileQueue.peekEntries(4).map(\.id)
        for attempt in 0 ..< 3 {
            queue.flush()
            try await waitForRequest(attempt + 1, sender: sender)
            sender.completeRequest(at: attempt, with: PostHogUploadInfo(statusCode: 503, error: nil))
            #expect(queue.fileQueue.peekEntries(4).map(\.id) == originalIds)
            mockNow.date.addTimeInterval(60)
        }
        for (attempt, cap) in [(3, 2), (4, 1)] {
            queue.flush()
            try await waitForRequest(attempt + 1, sender: sender)
            sender.completeRequest(at: attempt, with: PostHogUploadInfo(statusCode: 413, error: nil))
            #expect(queue.currentBatchCapForTesting == cap)
            #expect(queue.fileQueue.peekEntries(4).map(\.id) == originalIds)
        }
        queue.flush()
        try await waitForRequest(6, sender: sender)
        sender.completeRequest(at: 5, with: PostHogUploadInfo(statusCode: 413, error: nil))
        #expect(queue.fileQueue.peekEntries(4).map(\.id) == Array(originalIds.dropFirst()))
        #expect(queue.currentRetryCountForTesting == 0)
        for attempt in 6 ..< 9 {
            queue.flush()
            try await waitForRequest(attempt + 1, sender: sender)
            sender.completeRequest(at: attempt, with: PostHogUploadInfo(statusCode: 200, error: nil))
        }
        #expect(queue.depth == 0)
    }
}
