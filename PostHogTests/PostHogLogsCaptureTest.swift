//
//  PostHogLogsCaptureTest.swift
//  PostHogTests
//

import Foundation
import OHHTTPStubs
import OHHTTPStubsSwift
@testable import PostHog
import Testing
import XCTest

@Suite("PostHog logs capture", .serialized)
final class PostHogLogsCaptureTests {
    private var server: MockPostHogServer
    let mockAppLifecycle: MockApplicationLifecyclePublisher

    init() {
        mockAppLifecycle = MockApplicationLifecyclePublisher()
        DI.main.appLifecyclePublisher = mockAppLifecycle

        server = MockPostHogServer()
        server.start()
    }

    deinit {
        server.stop()
        DI.main.appLifecyclePublisher = ApplicationLifecyclePublisher.shared
    }

    // MARK: - Helpers

    private func setupSdk(
        rateCapMaxLogs: Int = 0, // disabled for tests so add() never silently drops
        flushIntervalSeconds: TimeInterval = 30,
        maxBatchSize: Int = 50,
        flushAt: Int? = nil,
        optOut: Bool = false
    ) -> PostHogSDK {
        let token = "logs_capture_\(UUID().uuidString)"
        let config = PostHogConfig(projectToken: token, host: "http://localhost:9001")
        config.optOut = optOut
        config.disableReachabilityForTesting = true
        config.disableQueueTimerForTesting = true
        config.disableFlushOnBackgroundForTesting = true
        config.logs.rateCapMaxLogs = rateCapMaxLogs
        config.logs.flushIntervalSeconds = flushIntervalSeconds
        config.logs.maxBatchSize = maxBatchSize
        if let flushAt {
            config.logs.flushAt = flushAt
        }

        return PostHogSDK.with(config)
    }

    private func waitForLogsRequests(count: Int, timeout: TimeInterval = 3) {
        server.logsExpectationCount = count
        server.logsExpectation = XCTestExpectation(description: "\(count) logs requests")
        if server.logsRequests.count >= count {
            server.logsExpectation?.fulfill()
        }
        let result = XCTWaiter.wait(for: [server.logsExpectation!], timeout: timeout)
        #expect(result == .completed, "Expected \(count) logs request(s) within \(timeout)s, got \(server.logsRequests.count)")
    }

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

    // MARK: - captureLog

    @Test("captureLog from main thread enqueues a record on disk")
    func captureFromMainThread() async throws {
        let sdk = setupSdk()
        defer { sdk.close() }

        sdk.captureLog("hello")
        sdk.flush()

        waitForLogsRequests(count: 1)
        #expect(server.logsRequests.count == 1)
    }

    @Test("captureLog from a background thread enqueues a record")
    func captureFromBackgroundThread() async throws {
        let sdk = setupSdk()
        defer { sdk.close() }

        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                sdk.captureLog("from-bg")
                continuation.resume()
            }
        }
        sdk.flush()

        waitForLogsRequests(count: 1)
        #expect(server.logsRequests.count == 1)
    }

    @Test("captureLog from many concurrent threads — no lost records, no crashes")
    func captureConcurrent() async throws {
        // Disable rate cap and threshold-flush so the burst stays in the
        // file queue until the explicit sdk.flush() drains it as one batch.
        // This keeps the assertion deterministic even when the shared
        // URLSession serializes requests on a single connection.
        let sdk = setupSdk(maxBatchSize: 1000, flushAt: 1000)
        defer { sdk.close() }

        let total = 200
        let group = DispatchGroup()
        for i in 0 ..< total {
            group.enter()
            DispatchQueue.global(qos: .utility).async {
                sdk.captureLog("log-\(i)")
                group.leave()
            }
        }
        group.wait()
        sdk.flush()

        // Decode every batch the server saw and accumulate the bodies.
        // Wait until we've seen all 200 (or time out).
        func collectBodies() -> Set<String> {
            var bodies: Set<String> = []
            for request in server.logsRequests {
                guard let data = request.body(),
                      let unzipped = try? data.gunzipped(),
                      let json = try? JSONSerialization.jsonObject(with: unzipped) as? [String: Any],
                      let resourceLogs = json["resourceLogs"] as? [[String: Any]],
                      let scopeLogs = resourceLogs.first?["scopeLogs"] as? [[String: Any]],
                      let records = scopeLogs.first?["logRecords"] as? [[String: Any]]
                else { continue }
                for record in records {
                    if let body = record["body"] as? [String: Any],
                       let text = body["stringValue"] as? String
                    {
                        bodies.insert(text)
                    }
                }
            }
            return bodies
        }

        await waitUntil(timeoutNanoseconds: 5_000_000_000) {
            collectBodies().count == total
        }

        let bodies = collectBodies()
        #expect(bodies.count == total)
        // No duplicates, no missing records — full set log-0 through log-199.
        let expected = Set((0 ..< total).map { "log-\($0)" })
        #expect(bodies == expected)
    }

    @Test("captureLog with empty body is dropped, no request fires")
    func captureEmptyBody() async throws {
        let sdk = setupSdk()
        defer { sdk.close() }

        // Earlier tests may have left in-flight requests on the shared mock
        // server; let them land before snapshotting the baseline so we measure
        // the delta from this test only.
        try? await Task.sleep(nanoseconds: 300_000_000)
        let baseline = server.logsRequests.count
        sdk.captureLog("")
        sdk.flush()

        try? await Task.sleep(nanoseconds: 200_000_000)
        #expect(server.logsRequests.count == baseline)
    }

    @Test("captureLog while opted out is dropped")
    func captureWhileOptedOut() async throws {
        let sdk = setupSdk(optOut: true)
        defer { sdk.close() }

        let baseline = server.logsRequests.count
        sdk.captureLog("should-not-send")
        sdk.flush()

        try? await Task.sleep(nanoseconds: 200_000_000)
        #expect(server.logsRequests.count == baseline)
    }

    @Test("logger.info is equivalent to captureLog level: .info")
    func loggerInfoEquivalence() async throws {
        let sdk = setupSdk(maxBatchSize: 2)
        defer { sdk.close() }

        sdk.captureLog("via-direct", level: .info)
        sdk.logger.info("via-facade")
        sdk.flush()

        waitForLogsRequests(count: 1)
        let request = try #require(server.logsRequests.first)
        let body = try #require(request.body())
        let unzipped = try body.gunzipped()
        let json = try #require(JSONSerialization.jsonObject(with: unzipped) as? [String: Any])
        let resourceLogs = try #require(json["resourceLogs"] as? [[String: Any]])
        let scopeLogs = try #require(resourceLogs[0]["scopeLogs"] as? [[String: Any]])
        let records = try #require(scopeLogs[0]["logRecords"] as? [[String: Any]])
        #expect(records.count == 2)

        // Both records should carry severityNumber 9 (info) AND the bodies
        // we sent. A regression where `logger.info` routed to a different
        // level but happened to also produce 2 records would be caught here.
        for record in records {
            #expect(record["severityNumber"] as? Int == 9)
        }
        let bodies = Set(records.compactMap { record -> String? in
            (record["body"] as? [String: Any])?["stringValue"] as? String
        })
        #expect(bodies == ["via-direct", "via-facade"])
    }

    @Test("logger covers all six severity levels")
    func loggerAllLevels() async throws {
        let sdk = setupSdk(maxBatchSize: 6)
        defer { sdk.close() }

        sdk.logger.trace("t")
        sdk.logger.debug("d")
        sdk.logger.info("i")
        sdk.logger.warn("w")
        sdk.logger.error("e")
        sdk.logger.fatal("f")
        sdk.flush()

        waitForLogsRequests(count: 1)
        let request = try #require(server.logsRequests.first)
        let body = try #require(request.body())
        let unzipped = try body.gunzipped()
        let json = try #require(JSONSerialization.jsonObject(with: unzipped) as? [String: Any])
        let resourceLogs = try #require(json["resourceLogs"] as? [[String: Any]])
        let scopeLogs = try #require(resourceLogs[0]["scopeLogs"] as? [[String: Any]])
        let records = try #require(scopeLogs[0]["logRecords"] as? [[String: Any]])

        let severityNumbers = records.compactMap { $0["severityNumber"] as? Int }.sorted()
        #expect(severityNumbers == [1, 5, 9, 13, 17, 21]) // OTLP severity numbers
    }

    @Test("captureLog snapshots distinctId at capture time, not flush time")
    func captureSnapshotsDistinctIdAtCaptureTime() async throws {
        let sdk = setupSdk(maxBatchSize: 1)
        defer { sdk.close() }

        sdk.identify("user-A")
        sdk.captureLog("at-A")
        // Identify as a different user before flushing — the captured record
        // must still carry user-A.
        sdk.identify("user-B")
        sdk.flush()

        waitForLogsRequests(count: 1)
        let request = try #require(server.logsRequests.first)
        let body = try #require(request.body())
        let unzipped = try body.gunzipped()
        let json = try #require(JSONSerialization.jsonObject(with: unzipped) as? [String: Any])
        let resourceLogs = try #require(json["resourceLogs"] as? [[String: Any]])
        let scopeLogs = try #require(resourceLogs[0]["scopeLogs"] as? [[String: Any]])
        let records = try #require(scopeLogs[0]["logRecords"] as? [[String: Any]])
        let attrs = try #require(records[0]["attributes"] as? [[String: Any]])
        let attrMap = Dictionary(uniqueKeysWithValues: attrs.compactMap { kv -> (String, [String: Any])? in
            guard let key = kv["key"] as? String, let value = kv["value"] as? [String: Any] else { return nil }
            return (key, value)
        })
        #expect(attrMap["posthogDistinctId"]?["stringValue"] as? String == "user-A")
    }

    @Test("captureLog OTLP wire payload includes resource attributes")
    func captureWirePayloadResourceAttributes() async throws {
        let sdk = setupSdk(maxBatchSize: 1)
        defer { sdk.close() }

        sdk.captureLog("hi")
        sdk.flush()

        waitForLogsRequests(count: 1)
        let request = try #require(server.logsRequests.first)
        let body = try #require(request.body())
        let unzipped = try body.gunzipped()
        let json = try #require(JSONSerialization.jsonObject(with: unzipped) as? [String: Any])
        let resourceLogs = try #require(json["resourceLogs"] as? [[String: Any]])
        let resource = try #require(resourceLogs[0]["resource"] as? [String: Any])
        let attrs = try #require(resource["attributes"] as? [[String: Any]])
        let keys = attrs.compactMap { $0["key"] as? String }
        #expect(keys.contains("service.name"))
        #expect(keys.contains("os.name"))
        #expect(keys.contains("os.version"))
        #expect(keys.contains("telemetry.sdk.name"))
        #expect(keys.contains("telemetry.sdk.version"))
    }

    @Test("flush from background thread drains the logs queue")
    func flushFromBackgroundThread() async throws {
        let sdk = setupSdk()
        defer { sdk.close() }

        sdk.captureLog("hello")
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                sdk.flush()
                continuation.resume()
            }
        }

        waitForLogsRequests(count: 1)
        #expect(server.logsRequests.count == 1)
    }

    @Test("backgrounding triggers a logs flush via PostHog.flush()")
    func backgroundingFlushesLogs() async throws {
        // Re-enable the background flush hook for this test (the helper turns it
        // off by default to keep other tests deterministic).
        let token = "logs_capture_bg_\(UUID().uuidString)"
        let config = PostHogConfig(projectToken: token, host: "http://localhost:9001")
        config.disableReachabilityForTesting = true
        config.disableQueueTimerForTesting = true
        config.disableFlushOnBackgroundForTesting = false
        config.logs.rateCapMaxLogs = 0
        let sdk = PostHogSDK.with(config)
        defer { sdk.close() }

        sdk.captureLog("during-foreground")
        // Simulate the app entering background — the SDK subscribes to this
        // publisher in setup() and calls flush() on each emission, which now
        // drains all three queues including logs.
        mockAppLifecycle.simulateAppDidEnterBackground()

        waitForLogsRequests(count: 1)
        #expect(server.logsRequests.count == 1)
    }
}
