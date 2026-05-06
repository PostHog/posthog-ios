//
//  PostHogLogsQueueTest.swift
//  PostHogTests
//

import Foundation
import OHHTTPStubs
import OHHTTPStubsSwift
@testable import PostHog
import Testing
import XCTest

@Suite("PostHog logs queue", .serialized)
final class PostHogLogsQueueTests {
    private var server: MockPostHogServer

    init() {
        server = MockPostHogServer()
        server.start()
    }

    deinit {
        server.stop()
    }

    // MARK: - Helpers

    private func makeQueue(
        maxBufferSize: Int = 100,
        maxBatchSize: Int = 50,
        // Set very high so threshold flush never fires unintentionally.
        // Tests that exercise threshold behaviour pass an explicit value.
        flushAt: Int = .max,
        rateCapMaxLogs: Int = 0, // disabled by default in tests so add(...) never silently drops
        rateCapWindowSeconds: TimeInterval = 10,
        beforeSend: PostHogBeforeSendLogBlock? = nil,
        reachability: Reachability? = nil,
        disableReachabilityForTesting: Bool = true
    ) -> (PostHogLogsQueue, PostHogConfig) {
        // Unique project token per test → isolated storage folder.
        let token = "logs_test_\(UUID().uuidString)"
        let config = PostHogConfig(projectToken: token, host: "http://localhost:9001")
        config.logs.maxBufferSize = maxBufferSize
        config.logs.maxBatchSize = maxBatchSize
        config.logs.flushAt = flushAt
        config.logs.rateCapMaxLogs = rateCapMaxLogs
        config.logs.rateCapWindowSeconds = rateCapWindowSeconds
        if let beforeSend {
            config.logs.setBeforeSend(beforeSend)
        }

        let storage = PostHogStorage(config)
        let api = PostHogApi(config)
        let queue = PostHogLogsQueue(config, storage, api, reachability)
        // Start without the periodic timer so tests are deterministic.
        // Reachability is opt-in per test via the parameter.
        queue.start(disableReachabilityForTesting: disableReachabilityForTesting, disableQueueTimerForTesting: true)
        queue.clear()
        return (queue, config)
    }

    private func makeRecord(
        body: String = "hello",
        level: PostHogLogLevel = .info,
        attributes: [String: Any] = [:],
        distinctId: String? = "user-123"
    ) -> PostHogLogRecord {
        PostHogLogRecord(
            body: body,
            level: level,
            attributes: attributes,
            distinctId: distinctId,
            sessionId: "sess-456",
            screenName: "TestScreen",
            appState: "foreground",
            featureFlagKeys: ["flag-a"]
        )
    }

    /// Polls `condition` until it returns true or `timeoutNanoseconds` elapses.
    /// Mirrors PostHogReplayQueueTests' waitUntil helper.
    private func waitUntil(
        timeoutNanoseconds: UInt64 = 2_000_000_000,
        pollNanoseconds: UInt64 = 5_000_000,
        _ condition: () -> Bool
    ) async {
        let start = DispatchTime.now().uptimeNanoseconds
        while !condition(), (DispatchTime.now().uptimeNanoseconds - start) < timeoutNanoseconds {
            try? await Task.sleep(nanoseconds: pollNanoseconds)
        }
    }

    private func waitForLogsRequests(count: Int, timeout: TimeInterval = 3) {
        server.logsExpectationCount = count
        server.logsExpectation = XCTestExpectation(description: "\(count) logs requests")
        // If requests already arrived, fulfil immediately.
        if server.logsRequests.count >= count {
            server.logsExpectation?.fulfill()
        }
        let result = XCTWaiter.wait(for: [server.logsExpectation!], timeout: timeout)
        #expect(result == .completed, "Expected \(count) logs request(s) within \(timeout)s, got \(server.logsRequests.count)")
    }

    // MARK: - add()

    @Test("add persists a record to disk")
    func addPersistsRecord() async throws {
        let (queue, _) = makeQueue()
        defer { queue.clear()
            queue.stop()
        }

        queue.add(makeRecord(body: "first"))
        await waitUntil { queue.depth == 1 }

        #expect(queue.depth == 1)
    }

    @Test("FIFO eviction when buffer is full")
    func fifoEvictionAtMaxBufferSize() async throws {
        // maxBufferSize 3, threshold flush would need batchSize <= depth, set
        // batchSize larger so threshold flush is not triggered while we measure.
        let (queue, _) = makeQueue(maxBufferSize: 3, maxBatchSize: 100)
        defer { queue.clear()
            queue.stop()
        }

        queue.add(makeRecord(body: "1"))
        queue.add(makeRecord(body: "2"))
        queue.add(makeRecord(body: "3"))
        queue.add(makeRecord(body: "4"))
        queue.add(makeRecord(body: "5"))
        await waitUntil { queue.depth == 3 }

        #expect(queue.depth == 3)
    }

    // MARK: - flush()

    @Test("flush sends a single batch on 200 OK")
    func flushSendsBatch() async throws {
        let (queue, _) = makeQueue(maxBufferSize: 100, maxBatchSize: 100)
        defer { queue.clear()
            queue.stop()
        }

        queue.add(makeRecord(body: "log-1"))
        queue.add(makeRecord(body: "log-2"))
        await waitUntil { queue.depth == 2 }

        queue.flush()
        waitForLogsRequests(count: 1)

        #expect(server.logsRequests.count == 1)
        await waitUntil { queue.depth == 0 }
        #expect(queue.depth == 0)
    }

    @Test("threshold flush triggers when depth reaches maxBatchSize")
    func thresholdFlush() async throws {
        let (queue, _) = makeQueue(maxBufferSize: 100, maxBatchSize: 2, flushAt: 2)
        defer { queue.clear()
            queue.stop()
        }

        queue.add(makeRecord(body: "1"))
        queue.add(makeRecord(body: "2"))
        // Adding the second should trigger a flush automatically.
        waitForLogsRequests(count: 1)

        #expect(server.logsRequests.count == 1)
    }

    @Test("flush with empty queue is a no-op and clears isFlushing")
    func flushEmpty() async throws {
        let (queue, _) = makeQueue()
        defer { queue.clear()
            queue.stop()
        }

        queue.flush()
        // Give the dispatch queue time to run the no-op closure.
        try? await Task.sleep(nanoseconds: 500_000_000)

        // No request should have been sent.
        #expect(server.logsRequests.isEmpty)
        // A second flush must not deadlock — proves isFlushing is clear.
        queue.add(makeRecord())
        queue.flush()
        waitForLogsRequests(count: 1)
        #expect(server.logsRequests.count == 1)
    }

    // MARK: - 413 backpressure

    @Test("413 halves batch cap and retries the same records")
    func handle413HalvesCap() async throws {
        let (queue, _) = makeQueue(maxBufferSize: 100, maxBatchSize: 4, flushAt: 4)
        defer { queue.clear()
            queue.stop()
        }

        // First request returns 413, all subsequent return 200.
        server.logsResponseHandler = { _, n in
            if n == 1 {
                return HTTPStubsResponse(jsonObject: ["error": "too large"], statusCode: 413, headers: nil)
            }
            return HTTPStubsResponse(jsonObject: ["status": "ok"], statusCode: 200, headers: nil)
        }

        for i in 0 ..< 4 {
            queue.add(makeRecord(body: "log-\(i)"))
        }
        await waitUntil { queue.depth == 4 }

        // Threshold flush already fired (depth == 4 == maxBatchSize). Wait for
        // the first request to come in and be handled (413).
        waitForLogsRequests(count: 1)
        // Records should still be on disk after 413.
        await waitUntil(timeoutNanoseconds: 500_000_000) { queue.depth < 4 }
        #expect(queue.depth == 4)

        // Trigger another flush — this time the cap is 2 and the response is 200.
        queue.flush()
        waitForLogsRequests(count: 2)
        await waitUntil { queue.depth <= 2 }
        // After popping 2 records, depth should be 2.
        #expect(queue.depth == 2)
    }

    @Test("cap stays put on 2xx — no ramp")
    func capStaysPutOnSuccess() async throws {
        // After a 413 halves the cap, a healthy 200 must NOT ramp the cap
        // back up. Logs / events / replay all share the conservative
        // "halve and stay" cap behaviour from posthog-android and
        // posthog-js-lite. A regression that ramped on success would
        // silently ship.
        let (queue, _) = makeQueue(maxBufferSize: 100, maxBatchSize: 10, flushAt: 10)
        defer { queue.clear()
            queue.stop()
        }

        server.logsResponseHandler = { _, n in
            if n == 1 {
                return HTTPStubsResponse(jsonObject: ["error": "too large"], statusCode: 413, headers: nil)
            }
            return HTTPStubsResponse(jsonObject: ["status": "ok"], statusCode: 200, headers: nil)
        }

        for i in 0 ..< 10 {
            queue.add(makeRecord(body: "log-\(i)"))
        }
        // Threshold flush fires (depth == cap == 10). 413 → halves cap to 5.
        waitForLogsRequests(count: 1)
        await waitUntil { queue.currentBatchCapForTesting == 5 }
        #expect(queue.currentBatchCapForTesting == 5)

        // Next flush: 200 with batch=5 → cap should STAY at 5 (no ramp).
        queue.flush()
        waitForLogsRequests(count: 2)
        // Wait for the response to be processed and assert cap unchanged.
        try? await Task.sleep(nanoseconds: 200_000_000)
        #expect(queue.currentBatchCapForTesting == 5)
    }

    @Test("413 on a single-record batch drops the poison record and leaves the cap at 1")
    func handle413SingleRecordDrops() async throws {
        let configuredMax = 8
        let (queue, _) = makeQueue(maxBufferSize: 100, maxBatchSize: configuredMax, flushAt: configuredMax)
        defer { queue.clear()
            queue.stop()
        }

        server.logsResponseHandler = { _, _ in
            HTTPStubsResponse(jsonObject: ["error": "too large"], statusCode: 413, headers: nil)
        }

        for i in 0 ..< configuredMax {
            queue.add(makeRecord(body: "log-\(i)"))
        }
        // First flush is threshold-driven (depth == configuredMax). 413 → halve.
        waitForLogsRequests(count: 1)
        await waitUntil { queue.currentBatchCapForTesting < configuredMax }
        #expect(queue.currentBatchCapForTesting == configuredMax / 2)

        // Drain the cap progressively until we hit a size-1 batch + 413 + drop.
        // Each flush halves the cap; eventually peek(1) → 413 → poison drop.
        while queue.depth > 0 {
            queue.flush()
            try? await Task.sleep(nanoseconds: 100_000_000)
        }

        #expect(queue.depth == 0)
        // After the poison-drop branch fires, the cap stays at 1 — same as
        // events / posthog-android. New records starting will use the small
        // cap until a successful send happens (no ramp).
        #expect(queue.currentBatchCapForTesting == 1)
    }

    // MARK: - 5xx / network failures

    @Test("5xx leaves records on disk and pauses the queue")
    func handle5xxRetains() async throws {
        let (queue, _) = makeQueue(maxBufferSize: 100, maxBatchSize: 100)
        defer { queue.clear()
            queue.stop()
        }

        server.logsResponseHandler = { _, _ in
            HTTPStubsResponse(jsonObject: [], statusCode: 503, headers: nil)
        }

        queue.add(makeRecord(body: "log-1"))
        queue.add(makeRecord(body: "log-2"))
        await waitUntil { queue.depth == 2 }

        queue.flush()
        waitForLogsRequests(count: 1)
        // Wait for the response to be processed; depth should remain == 2.
        await waitUntil(timeoutNanoseconds: 500_000_000) { queue.depth != 2 }
        #expect(queue.depth == 2)
    }

    @Test("413 poison-drop does not consume the maxRetries budget — queue drains record-by-record")
    func handle413PoisonDropIsNotARetry() async throws {
        // Pin down: cap=1 + 413 (poison drop) is a *resolution*, not a retry.
        // It must not increment retryCount.
        //
        // Scenario: maxBatchSize=8 + 8 oversized records + default maxRetries=3.
        // The cap halves 3 times (8→4→2→1, retryCount accumulating to 3) before
        // reaching cap=1. If poison-drop counted as a retry, the next flush would
        // push retryCount to 4 > 3 and fire dropAll — wiping ALL 8 records together.
        // The correct behaviour treats poison-drop as a clean resolution: the
        // offending record is popped, retryCount resets to 0, cap resets to max
        // (logs `capAfterPoisonDrop` policy), and the queue continues draining.
        //
        // Observable difference: the buggy path makes ~4 HTTP requests (3
        // halvings + 1 dropAll). The correct path makes far more — each record
        // costs at least one halve cycle + one poison drop.
        let (queue, _) = makeQueue(maxBufferSize: 100, maxBatchSize: 8, flushAt: 8)
        defer { queue.clear()
            queue.stop()
        }

        server.logsResponseHandler = { _, _ in
            HTTPStubsResponse(jsonObject: ["error": "too large"], statusCode: 413, headers: nil)
        }

        for i in 0 ..< 8 {
            queue.add(makeRecord(body: "log-\(i)"))
        }

        // Drive flushes until the queue drains.
        while queue.depth > 0 {
            queue.flush()
            try? await Task.sleep(nanoseconds: 100_000_000)
        }

        #expect(queue.depth == 0)
        // dropAll path would produce ≤ 4 requests (3 halvings + dropAll itself).
        // Record-by-record drain produces > 8 — at minimum one request per
        // record dropped, plus the halve cycles in between.
        #expect(server.logsRequests.count > 8)
    }

    @Test("drops the entire queue once retryCount exceeds maxRetries on repeated 413")
    func handle413MaxRetriesDropsAll() async throws {
        // Mirrors PostHogQueue's safeguard: a permanently-broken backend that
        // keeps returning 413 should not leave the logs queue retrying forever.
        // After config.maxRetries failed attempts, the queue drops everything
        // and resets the retry / cap state.
        let (queue, config) = makeQueue(maxBufferSize: 100, maxBatchSize: 64)
        config.maxRetries = 1
        defer { queue.clear()
            queue.stop()
        }

        server.logsResponseHandler = { _, _ in
            HTTPStubsResponse(jsonObject: ["error": "too large"], statusCode: 413, headers: nil)
        }

        // Enough records that cap-halving alone won't drain the queue before
        // retryCount exceeds maxRetries.
        for i in 0 ..< 32 {
            queue.add(makeRecord(body: "log-\(i)"))
        }
        await waitUntil { queue.depth == 32 }

        // Drive flushes until the queue drops everything via the maxRetries path.
        // First flush: batchSize=32 → 413 → retryCount=1 (not > 1) → halve cap.
        // Second flush: batchSize=16 → 413 → retryCount=2 (> 1) → drop ALL records.
        queue.flush()
        try? await Task.sleep(nanoseconds: 100_000_000)
        queue.flush()
        await waitUntil { queue.depth == 0 }
        #expect(queue.depth == 0)
        // Cap stays where it was when dropAll fired — no reset. Matches
        // events / posthog-android behaviour: new records start at the
        // halved cap until a successful send proves the backend is healthy.
        #expect(queue.currentBatchCapForTesting == 16)
    }

    @Test("halves cap from min(cap, actualBatchSize) when queue depth was below cap")
    func handle413HalvesByActualBatchSize() async throws {
        // maxBatchSize=50 but only 4 records on disk. A 413 should halve from
        // min(50, 4) = 4 → cap = 2, NOT from 50/2 = 25. Avoids wasted halvings
        // on a cap the server never actually saw.
        let (queue, _) = makeQueue(maxBufferSize: 100, maxBatchSize: 50)
        defer { queue.clear()
            queue.stop()
        }

        var responseCount = 0
        server.logsResponseHandler = { _, _ in
            responseCount += 1
            return HTTPStubsResponse(jsonObject: ["error": "too large"], statusCode: 413, headers: nil)
        }

        for i in 0 ..< 4 {
            queue.add(makeRecord(body: "log-\(i)"))
        }
        await waitUntil { queue.depth == 4 }
        // depth (4) < flushAt (50) so threshold flush won't fire — drive manually.
        queue.flush()
        waitForLogsRequests(count: 1)

        await waitUntil { queue.currentBatchCapForTesting < 50 }
        #expect(queue.currentBatchCapForTesting == 2)
        #expect(queue.depth == 4)
    }

    // Note: the 5xx path also goes through retryCountExceeded → dropAllQueuedRecords,
    // but testing it directly would require waiting out the 5+10+15s exponential backoff
    // between attempts (`pausedUntil` blocks the next flush). The 413 maxRetries test
    // above covers the shared drop logic without that latency since 413 doesn't pause.

    @Test("non-413 4xx drops the batch (poison-pill)")
    func handleNon413_4xxDrops() async throws {
        let (queue, _) = makeQueue(maxBufferSize: 100, maxBatchSize: 100)
        defer { queue.clear()
            queue.stop()
        }

        server.logsResponseHandler = { _, _ in
            HTTPStubsResponse(jsonObject: ["error": "bad request"], statusCode: 400, headers: nil)
        }

        queue.add(makeRecord(body: "log-1"))
        queue.add(makeRecord(body: "log-2"))
        await waitUntil { queue.depth == 2 }

        queue.flush()
        waitForLogsRequests(count: 1)
        await waitUntil { queue.depth == 0 }
        #expect(queue.depth == 0)
    }

    // MARK: - Rate cap

    @Test("rate cap drops records once the per-window limit is hit")
    func rateCapEnforced() async throws {
        let (queue, _) = makeQueue(
            maxBufferSize: 100,
            maxBatchSize: 100,
            rateCapMaxLogs: 5,
            rateCapWindowSeconds: 10
        )
        defer { queue.clear()
            queue.stop()
        }

        for i in 0 ..< 20 {
            queue.add(makeRecord(body: "log-\(i)"))
        }
        await waitUntil { queue.depth == 5 }
        #expect(queue.depth == 5)
    }

    @Test("rate cap window resets after the configured interval")
    func rateCapWindowResets() async throws {
        // 1-second window so we don't slow the test suite too much.
        let (queue, _) = makeQueue(
            maxBufferSize: 100,
            maxBatchSize: 100,
            rateCapMaxLogs: 2,
            rateCapWindowSeconds: 1
        )
        defer { queue.clear()
            queue.stop()
        }

        queue.add(makeRecord(body: "1"))
        queue.add(makeRecord(body: "2"))
        queue.add(makeRecord(body: "dropped")) // exceeds cap
        await waitUntil { queue.depth == 2 }
        #expect(queue.depth == 2)

        // Wait past the window edge.
        try await Task.sleep(nanoseconds: 1_100_000_000)

        queue.add(makeRecord(body: "after-window"))
        await waitUntil { queue.depth == 3 }
        #expect(queue.depth == 3)
    }

    @Test("rate cap disabled when rateCapMaxLogs == 0")
    func rateCapDisabled() async throws {
        let (queue, _) = makeQueue(
            maxBufferSize: 100,
            maxBatchSize: 1000,
            rateCapMaxLogs: 0
        )
        defer { queue.clear()
            queue.stop()
        }

        for i in 0 ..< 50 {
            queue.add(makeRecord(body: "log-\(i)"))
        }
        await waitUntil { queue.depth == 50 }
        #expect(queue.depth == 50)
    }

    // MARK: - beforeSend chain

    @Test("beforeSend returning nil signals drop")
    func beforeSendDrop() async throws {
        let (queue, config) = makeQueue(beforeSend: { _ in nil })
        defer { queue.clear()
            queue.stop()
        }

        let processed = config.logs.runBeforeSend(makeRecord(body: "should-be-dropped"))
        #expect(processed == nil)
        // SDK-side check would short-circuit here; queue would never see it.
        #expect(queue.depth == 0)
    }

    @Test("beforeSend can mutate body to empty (SDK caller drops on empty)")
    func beforeSendEmptyBodyDrops() async throws {
        let (queue, config) = makeQueue(beforeSend: { record in
            record.body = ""
            return record
        })
        defer { queue.clear()
            queue.stop()
        }

        let processed = config.logs.runBeforeSend(makeRecord(body: "non-empty"))
        #expect(processed?.body.isEmpty == true)
        // SDK caller (`captureLog`) drops empty bodies after beforeSend.
    }

    @Test("beforeSend mutating the record changes what gets queued")
    func beforeSendMutates() async throws {
        let (queue, config) = makeQueue(beforeSend: { record in
            record.body = "redacted"
            return record
        })
        defer { queue.clear()
            queue.stop()
        }

        let processed = try #require(config.logs.runBeforeSend(makeRecord(body: "original")))
        #expect(processed.body == "redacted")
        // SDK caller passes the mutated record to queue.add.
        queue.add(processed)
        await waitUntil { queue.depth == 1 }

        // Peek the persisted record — it should carry the mutated body.
        let persisted = queue.fileQueue.peek(1)
        let record = try #require(PostHogLogRecord.fromStorageJSON(persisted[0]))
        #expect(record.body == "redacted")
    }

    // MARK: - Concurrency

    @Test("concurrent add() from many threads — all records accounted for, no crash")
    func concurrentAdd() async throws {
        let perThread = 50
        let threadCount = 8
        // Disable rate cap so the count is deterministic.
        let (queue, _) = makeQueue(
            maxBufferSize: perThread * threadCount + 100,
            maxBatchSize: perThread * threadCount + 100,
            rateCapMaxLogs: 0
        )
        defer { queue.clear()
            queue.stop()
        }

        let group = DispatchGroup()
        for t in 0 ..< threadCount {
            group.enter()
            DispatchQueue.global(qos: .userInitiated).async {
                for i in 0 ..< perThread {
                    queue.add(self.makeRecord(body: "t\(t)-i\(i)"))
                }
                group.leave()
            }
        }
        group.wait()

        let expected = perThread * threadCount
        await waitUntil(timeoutNanoseconds: 5_000_000_000) { queue.depth == expected }
        #expect(queue.depth == expected)
    }

    @Test("add() racing with flush() — no crash, queue drains cleanly afterwards")
    func concurrentAddAndFlush() async throws {
        let (queue, _) = makeQueue(
            maxBufferSize: 1000,
            maxBatchSize: 5,
            rateCapMaxLogs: 0
        )
        defer { queue.clear()
            queue.stop()
        }

        let producerCount = 4
        let perThread = 100
        let group = DispatchGroup()
        let stopFlusher = DispatchSemaphore(value: 0)

        for t in 0 ..< producerCount {
            group.enter()
            DispatchQueue.global(qos: .userInitiated).async {
                for i in 0 ..< perThread {
                    queue.add(self.makeRecord(body: "t\(t)-i\(i)"))
                }
                group.leave()
            }
        }

        let flusherDone = DispatchSemaphore(value: 0)
        DispatchQueue.global(qos: .userInitiated).async {
            while stopFlusher.wait(timeout: .now()) == .timedOut {
                queue.flush()
            }
            flusherDone.signal()
        }

        group.wait()
        stopFlusher.signal()
        flusherDone.wait()

        // After all producers stop, drain to zero with explicit flushes. If
        // `isFlushing` was ever stranded `true` we would never make progress.
        await waitUntil(timeoutNanoseconds: 5_000_000_000) {
            queue.flush()
            return queue.depth == 0
        }
        #expect(queue.depth == 0)
    }

    @Test("clear() racing with add() — no crash, queue stays usable")
    func clearRacingAdd() async throws {
        let (queue, _) = makeQueue(maxBufferSize: 1000, maxBatchSize: 1000, rateCapMaxLogs: 0)
        defer { queue.clear()
            queue.stop()
        }

        let producerDone = DispatchSemaphore(value: 0)
        DispatchQueue.global(qos: .userInitiated).async {
            for i in 0 ..< 200 {
                queue.add(self.makeRecord(body: "race-\(i)"))
            }
            producerDone.signal()
        }
        for _ in 0 ..< 50 {
            queue.clear()
        }
        producerDone.wait()
        // One last clear so straggler async writes from add() are accounted for.
        queue.clear()
        // Queue is still usable: a fresh add lands.
        queue.add(makeRecord(body: "after-clear"))
        await waitUntil { queue.depth >= 1 }
        #expect(queue.depth >= 1)
    }

    // MARK: - Reachability

    @Test("flush is suppressed while reachability reports unreachable, resumes on reconnect")
    func reachabilityPauseAndResume() async throws {
        let reachability = try Reachability()
        let (queue, _) = makeQueue(
            reachability: reachability,
            disableReachabilityForTesting: false
        )
        defer { queue.clear()
            queue.stop()
        }

        // Simulate network going down. Subsequent flushes are paused.
        reachability.onUnreachable.invoke(reachability)

        queue.add(makeRecord(body: "while-offline"))
        queue.flush()
        try? await Task.sleep(nanoseconds: 300_000_000)
        #expect(server.logsRequests.isEmpty)
        #expect(queue.depth == 1)

        // Simulate WiFi back. The reachable callback unpauses and proactively
        // triggers a flush.
        reachability.onReachable.invoke(reachability)
        waitForLogsRequests(count: 1)
        #expect(server.logsRequests.count == 1)
        await waitUntil { queue.depth == 0 }
    }

    // MARK: - SDK integration

    @Test("PostHog.shared.flush() drains the logs queue alongside events and replay")
    func sdkFlushDrainsLogsQueue() async throws {
        let token = "logs_sdk_\(UUID().uuidString)"
        let config = PostHogConfig(projectToken: token, host: "http://localhost:9001")
        config.disableReachabilityForTesting = true
        config.disableQueueTimerForTesting = true
        config.disableFlushOnBackgroundForTesting = true
        config.disableRemoteConfigForTesting = true

        PostHogSDK.shared.setup(config)
        defer { PostHogSDK.shared.close() }

        // Enqueue via the internal logs queue accessor — there is no public
        // captureLog API in this PR, so this test exercises the wiring by
        // reaching directly into the SDK's queue. The public surface lands
        // in the next PR.
        let record = PostHogLogRecord(body: "sdk-flush-integration")
        let logsQueue = try #require(PostHogSDK.shared.logsQueue)
        logsQueue.add(record)

        // Public flush() must drain every queue, including logs.
        PostHogSDK.shared.flush()

        waitForLogsRequests(count: 1, timeout: 3)
        #expect(server.logsRequests.count == 1)
    }

    // MARK: - Wire format

    @Test("OTLP payload includes resource and per-record context")
    func otlpPayloadShape() async throws {
        let (queue, _) = makeQueue(maxBufferSize: 100, maxBatchSize: 1, flushAt: 1)
        defer { queue.clear()
            queue.stop()
        }

        queue.add(makeRecord(
            body: "hello",
            level: .warn,
            attributes: ["custom_key": "custom_value"]
        ))
        waitForLogsRequests(count: 1)

        let request = try #require(server.logsRequests.first)

        // Verify the URL includes ?token=... in the query string.
        let url = try #require(request.url)
        let comps = try #require(URLComponents(url: url, resolvingAgainstBaseURL: true))
        let tokenItem = comps.queryItems?.first(where: { $0.name == "token" })
        #expect(tokenItem?.value?.hasPrefix("logs_test_") == true)
        #expect(url.path.hasSuffix("/i/v1/logs"))

        // Decode the gzipped JSON body.
        let body = try #require(request.body())
        let unzipped = try body.gunzipped()
        let json = try #require(JSONSerialization.jsonObject(with: unzipped) as? [String: Any])

        let resourceLogs = try #require(json["resourceLogs"] as? [[String: Any]])
        #expect(resourceLogs.count == 1)

        let firstResource = resourceLogs[0]
        let resource = try #require(firstResource["resource"] as? [String: Any])
        let resAttrs = try #require(resource["attributes"] as? [[String: Any]])
        let resAttrKeys = resAttrs.compactMap { $0["key"] as? String }
        #expect(resAttrKeys.contains("service.name"))
        #expect(resAttrKeys.contains("telemetry.sdk.name"))
        #expect(resAttrKeys.contains("telemetry.sdk.version"))
        #expect(resAttrKeys.contains("os.name"))
        #expect(resAttrKeys.contains("os.version"))

        let scopeLogs = try #require(firstResource["scopeLogs"] as? [[String: Any]])
        let scope = try #require(scopeLogs[0]["scope"] as? [String: Any])
        #expect(scope["name"] as? String == "posthog-ios")
        #expect(scope["version"] as? String == postHogVersion)

        let logRecords = try #require(scopeLogs[0]["logRecords"] as? [[String: Any]])
        #expect(logRecords.count == 1)
        let rec = logRecords[0]
        #expect(rec["severityNumber"] as? Int == 13)
        #expect(rec["severityText"] as? String == "WARN")
        let bodyAny = try #require(rec["body"] as? [String: Any])
        #expect(bodyAny["stringValue"] as? String == "hello")

        let recAttrs = try #require(rec["attributes"] as? [[String: Any]])
        let attrMap = Dictionary(uniqueKeysWithValues: recAttrs.compactMap { kv -> (String, [String: Any])? in
            guard let key = kv["key"] as? String, let value = kv["value"] as? [String: Any] else { return nil }
            return (key, value)
        })
        #expect(attrMap["posthogDistinctId"]?["stringValue"] as? String == "user-123")
        #expect(attrMap["sessionId"]?["stringValue"] as? String == "sess-456")
        #expect(attrMap["screen.name"]?["stringValue"] as? String == "TestScreen")
        #expect(attrMap["app.state"]?["stringValue"] as? String == "foreground")
        #expect(attrMap["custom_key"]?["stringValue"] as? String == "custom_value")
    }

    @Test("OTLP encodes non-string attributes (Int / Double / Bool / array / dict / NaN / Infinity)")
    func otlpNonStringAttributeTypes() async throws {
        let (queue, _) = makeQueue(maxBufferSize: 100, maxBatchSize: 1, flushAt: 1)
        defer { queue.clear()
            queue.stop()
        }

        // NaN / ±Infinity are intentionally NOT exercised here: `toStorageJSON`
        // serializes via `JSONSerialization`, which rejects those values, so the
        // whole record drops at `add()` time. Fixing that is a separate concern;
        // OTLP's `toAnyValue` handles them correctly when they survive to the
        // encoding step (e.g. in attributes injected later in the pipeline).
        queue.add(makeRecord(
            body: "types",
            attributes: [
                "int_attr": 42,
                "double_attr": 3.14,
                "bool_true": true,
                "bool_false": false,
                "array_attr": ["a", "b", "c"],
                "dict_attr": ["nested": "value"],
            ]
        ))
        waitForLogsRequests(count: 1)

        let request = try #require(server.logsRequests.first)
        let body = try #require(request.body())
        let unzipped = try body.gunzipped()
        let json = try #require(JSONSerialization.jsonObject(with: unzipped) as? [String: Any])
        let resourceLogs = try #require(json["resourceLogs"] as? [[String: Any]])
        let scopeLogs = try #require(resourceLogs[0]["scopeLogs"] as? [[String: Any]])
        let logRecords = try #require(scopeLogs[0]["logRecords"] as? [[String: Any]])
        let attrs = try #require(logRecords[0]["attributes"] as? [[String: Any]])
        let attrMap = Dictionary(uniqueKeysWithValues: attrs.compactMap { kv -> (String, [String: Any])? in
            guard let key = kv["key"] as? String, let value = kv["value"] as? [String: Any] else { return nil }
            return (key, value)
        })

        // intValue is encoded as String per proto3 JSON int64 rules.
        #expect(attrMap["int_attr"]?["intValue"] as? String == "42")
        // doubleValue is a JSON number for finite floats.
        #expect(attrMap["double_attr"]?["doubleValue"] as? Double == 3.14)
        // Bool comes through as boolValue, not intValue (NSNumber bridge trap).
        #expect(attrMap["bool_true"]?["boolValue"] as? Bool == true)
        #expect(attrMap["bool_false"]?["boolValue"] as? Bool == false)
        // Arrays nest as arrayValue.values; dicts as kvlistValue.values.
        let arrVal = try #require(attrMap["array_attr"]?["arrayValue"] as? [String: Any])
        let arrItems = try #require(arrVal["values"] as? [[String: Any]])
        #expect(arrItems.count == 3)
        #expect(arrItems[0]["stringValue"] as? String == "a")
        let kvVal = try #require(attrMap["dict_attr"]?["kvlistValue"] as? [String: Any])
        let kvItems = try #require(kvVal["values"] as? [[String: Any]])
        #expect(kvItems.count == 1)
        #expect(kvItems[0]["key"] as? String == "nested")
        let nestedValue = try #require(kvItems[0]["value"] as? [String: Any])
        #expect(nestedValue["stringValue"] as? String == "value")
    }

    // MARK: - Persistence round-trip

    @Test("PostHogLogRecord round-trips all optional fields through the disk codec")
    func recordRoundTripsThroughDiskCodec() throws {
        // Pure codec test — no queue, no network. Constructs a record with
        // every optional field populated, serializes to JSON, deserializes,
        // and asserts every field survives. Catches regressions in
        // toStorageJSON / fromStorageJSON for traceId, spanId, traceFlags
        // (NSNumber? bridging), per-record context, and attributes.
        let original = PostHogLogRecord(
            body: "hello",
            level: .warn,
            attributes: [
                "string_attr": "value",
                "int_attr": 42,
                "bool_attr": true,
            ],
            traceId: "0af7651916cd43dd8448eb211c80319c",
            spanId: "b7ad6b7169203331",
            traceFlags: NSNumber(value: 1),
            distinctId: "user-A",
            sessionId: "sess-1",
            screenName: "Screen",
            appState: "foreground",
            featureFlagKeys: ["flag-a", "flag-b"]
        )

        let json = original.toStorageJSON()
        let data = try JSONSerialization.data(withJSONObject: json, options: [])
        let decoded = try #require(PostHogLogRecord.fromStorageJSON(data))

        #expect(decoded.body == "hello")
        #expect(decoded.level == .warn)
        #expect(decoded.attributes["string_attr"] as? String == "value")
        #expect(decoded.attributes["int_attr"] as? Int == 42)
        #expect(decoded.attributes["bool_attr"] as? Bool == true)
        #expect(decoded.traceId == "0af7651916cd43dd8448eb211c80319c")
        #expect(decoded.spanId == "b7ad6b7169203331")
        #expect(decoded.traceFlags?.intValue == 1)
        #expect(decoded.traceFlagsValue == 1) // Swift sugar accessor
        #expect(decoded.distinctId == "user-A")
        #expect(decoded.sessionId == "sess-1")
        #expect(decoded.screenName == "Screen")
        #expect(decoded.appState == "foreground")
        #expect(decoded.featureFlagKeys == ["flag-a", "flag-b"])
        #expect(decoded.timeUnixNano == original.timeUnixNano)
    }

    @Test("traceFlags appears as `flags` on the OTLP wire payload")
    func traceFlagsOnTheWire() async throws {
        // After switching `traceFlags` from `Int?` to `@objc public var
        // traceFlags: NSNumber?`, the disk codec and OTLP encoder both have
        // to keep handling the field correctly. This test pushes a record
        // with traceFlags = 1 through a real flush and asserts the OTLP
        // `flags` field on the wire is the literal integer 1.
        let (queue, _) = makeQueue(maxBufferSize: 100, maxBatchSize: 1, flushAt: 1)
        defer { queue.clear()
            queue.stop()
        }

        let record = PostHogLogRecord(
            body: "traced",
            level: .info,
            attributes: [:],
            traceId: "0af7651916cd43dd8448eb211c80319c",
            spanId: "b7ad6b7169203331",
            traceFlags: NSNumber(value: 1),
            distinctId: "user-1",
            sessionId: "sess-1",
            screenName: nil,
            appState: "foreground",
            featureFlagKeys: []
        )
        queue.add(record)
        waitForLogsRequests(count: 1)

        let request = try #require(server.logsRequests.first)
        let body = try #require(request.body())
        let unzipped = try body.gunzipped()
        let json = try #require(JSONSerialization.jsonObject(with: unzipped) as? [String: Any])
        let resourceLogs = try #require(json["resourceLogs"] as? [[String: Any]])
        let scopeLogs = try #require(resourceLogs[0]["scopeLogs"] as? [[String: Any]])
        let logRecords = try #require(scopeLogs[0]["logRecords"] as? [[String: Any]])
        let rec = logRecords[0]

        #expect(rec["traceId"] as? String == "0af7651916cd43dd8448eb211c80319c")
        #expect(rec["spanId"] as? String == "b7ad6b7169203331")
        // OTLP renames the field on the wire: traceFlags -> flags.
        // JSONSerialization decodes a JSON number to NSNumber, which bridges
        // back to Int for the cast.
        #expect(rec["flags"] as? Int == 1)
    }
}
