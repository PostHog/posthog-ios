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
        rateCapMaxLogs: Int = 0, // disabled by default in tests so add(...) never silently drops
        rateCapWindowSeconds: TimeInterval = 10,
        beforeSend: PostHogBeforeSendLogBlock? = nil
    ) -> (PostHogLogsQueue, PostHogConfig) {
        // Unique project token per test → isolated storage folder.
        let token = "logs_test_\(UUID().uuidString)"
        let config = PostHogConfig(projectToken: token, host: "http://localhost:9001")
        config.logs.maxBufferSize = maxBufferSize
        config.logs.maxBatchSize = maxBatchSize
        config.logs.rateCapMaxLogs = rateCapMaxLogs
        config.logs.rateCapWindowSeconds = rateCapWindowSeconds
        config.logs.beforeSend = beforeSend

        let storage = PostHogStorage(config)
        let api = PostHogApi(config)
        let queue = PostHogLogsQueue(config, storage, api)
        // Start without the periodic timer so tests are deterministic. The
        // reachability flag is accepted for API symmetry but currently ignored.
        queue.start(disableReachabilityForTesting: true, disableQueueTimerForTesting: true)
        queue.clear()
        return (queue, config)
    }

    private func makeRecord(
        body: String = "hello",
        level: PostHogLogSeverity = .info,
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
        let (queue, _) = makeQueue(maxBufferSize: 100, maxBatchSize: 2)
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
        let (queue, _) = makeQueue(maxBufferSize: 100, maxBatchSize: 4)
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

    @Test("413 on a single-record batch drops the poison record and resets the cap")
    func handle413SingleRecordDrops() async throws {
        let configuredMax = 8
        let (queue, _) = makeQueue(maxBufferSize: 100, maxBatchSize: configuredMax)
        defer { queue.clear()
            queue.stop()
        }

        // Halve the cap once so we can verify the poison-drop path resets it.
        // First request: 413 with batchSize > 1 → halve. Second request: 413 with
        // batchSize == 1 → drop record + reset cap to configuredMax.
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
        // After the poison-drop branch fires, the cap must be reset to the
        // configured maximum so the next batch isn't unnecessarily small.
        #expect(queue.currentBatchCapForTesting == configuredMax)
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

    // MARK: - beforeSend

    @Test("beforeSend returning nil drops the record")
    func beforeSendDrop() async throws {
        let (queue, _) = makeQueue(beforeSend: { _ in nil })
        defer { queue.clear()
            queue.stop()
        }

        queue.add(makeRecord(body: "should-be-dropped"))
        // Give the (would-be) async write time to run.
        await waitUntil(timeoutNanoseconds: 500_000_000) { queue.depth > 0 }
        #expect(queue.depth == 0)
    }

    @Test("beforeSend mutating body to empty drops the record")
    func beforeSendEmptyBodyDrops() async throws {
        let (queue, _) = makeQueue(beforeSend: { record in
            var copy = record
            copy.body = ""
            return copy
        })
        defer { queue.clear()
            queue.stop()
        }

        queue.add(makeRecord(body: "non-empty"))
        await waitUntil(timeoutNanoseconds: 500_000_000) { queue.depth > 0 }
        #expect(queue.depth == 0)
    }

    @Test("beforeSend mutating the record changes what is queued")
    func beforeSendMutates() async throws {
        let (queue, _) = makeQueue(beforeSend: { record in
            var copy = record
            copy.body = "redacted"
            return copy
        })
        defer { queue.clear()
            queue.stop()
        }

        queue.add(makeRecord(body: "original"))
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
        let (queue, _) = makeQueue(maxBufferSize: 100, maxBatchSize: 1)
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
}
