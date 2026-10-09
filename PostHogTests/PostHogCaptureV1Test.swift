//
//  PostHogCaptureV1Test.swift
//  PostHogTests
//

import Foundation
import OHHTTPStubs
import OHHTTPStubsSwift
@_spi(PostHogInternal) @testable import PostHog
import Testing

@Suite("Capture V1 transport", .serialized, .resetsGlobalState)
final class PostHogCaptureV1Test {
    private let server: MockPostHogServer

    init() {
        deleteSafely(applicationSupportDirectoryURL())
        server = MockPostHogServer()
        server.start(batchCount: 0)
    }

    deinit {
        server.stop()
    }

    private func makeApi(requestHeaders: [String: String]? = nil) -> PostHogApi {
        let config = PostHogConfig(projectToken: "phc_capture_v1", host: "http://localhost:9001/proxy")
        config.requestHeaders = requestHeaders
        return PostHogApi(config)
    }

    private func send(_ api: PostHogApi, _ events: [PostHogEvent]) async -> PostHogUploadInfo {
        await withCheckedContinuation { continuation in
            api.captureV1(events: events) { continuation.resume(returning: $0) }
        }
    }

    private func body(_ request: URLRequest) throws -> [String: Any] {
        try #require(server.parseRequest(request))
    }

    @Test("sends events to /i/v1/analytics/events with Bearer auth and V1 headers")
    func sendsV1Request() async throws {
        let api = makeApi(requestHeaders: [
            "Authorization": "Bearer custom", "PostHog-Attempt": "9", "PostHog-Request-Id": "custom",
        ])
        _ = await send(api, [PostHogEvent(event: "test", distinctId: "user")])

        let request = try #require(server.batchRequests.first)
        #expect(request.url?.path == "/proxy/i/v1/analytics/events")
        #expect(request.httpMethod == "POST")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer phc_capture_v1")
        #expect(request.value(forHTTPHeaderField: "PostHog-Sdk-Info") == "\(postHogSdkName)/\(postHogVersion)")
        #expect(request.value(forHTTPHeaderField: "PostHog-Attempt") == "1")
        let requestId = try #require(request.value(forHTTPHeaderField: "PostHog-Request-Id"))
        #expect(UUID(uuidString: requestId) != nil)
        let timestamp = try #require(request.value(forHTTPHeaderField: "PostHog-Request-Timestamp"))
        #expect(timestamp.hasSuffix("Z"))
        #expect(toISO8601Date(timestamp) != nil)
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
        #expect(request.value(forHTTPHeaderField: "Content-Encoding") == "gzip")
    }

    @Test("builds the V1 body: created_at root, promoted session/window IDs, no $lib")
    func buildsV1Body() async throws {
        let event = PostHogEvent(
            event: "test",
            distinctId: "user",
            properties: [
                "$session_id": "session-1",
                "$window_id": "window-1",
                "$lib": "posthog-ios",
                "$lib_version": "1.0.0",
                "$process_person_profile": false,
                "custom": "value",
            ]
        )
        _ = await send(makeApi(), [event])

        let request = try #require(server.batchRequests.first)
        let body = try body(request)
        #expect(Set(body.keys) == ["created_at", "batch"])
        let createdAt = try #require(body["created_at"] as? String)
        #expect(toISO8601Date(createdAt) != nil)

        let events = try #require(body["batch"] as? [[String: Any]])
        let sent = try #require(events.first)
        #expect(sent["event"] as? String == "test")
        #expect(sent["uuid"] as? String == event.uuid.postHogUuidString)
        #expect(sent["distinct_id"] as? String == "user")
        #expect(sent["timestamp"] as? String == toISO8601String(event.timestamp))
        #expect(sent["session_id"] as? String == "session-1")
        #expect(sent["window_id"] as? String == "window-1")
        #expect(sent["options"] == nil)

        let properties = try #require(sent["properties"] as? [String: Any])
        for key in ["$session_id", "$window_id", "$lib", "$lib_version"] {
            #expect(properties[key] == nil, "\(key) should not be in properties")
        }
        // Options hoisting is not part of this transport change.
        #expect(properties["$process_person_profile"] as? Bool == false)
        #expect(properties["custom"] as? String == "value")

        // The stored event is not reshaped.
        #expect(event.properties["$session_id"] as? String == "session-1")
        #expect(event.properties["$lib"] as? String == "posthog-ios")
    }

    @Test("sends each UUID once per batch")
    func dedupesUuids() async throws {
        let first = PostHogEvent(event: "first", distinctId: "user")
        let duplicate = PostHogEvent(event: "duplicate", distinctId: "user", uuid: first.uuid)
        let other = PostHogEvent(event: "other", distinctId: "user")
        _ = await send(makeApi(), [first, duplicate, other])

        let request = try #require(server.batchRequests.first)
        let events = try #require(try body(request)["batch"] as? [[String: Any]])
        #expect(events.map { $0["event"] as? String } == ["first", "other"])
    }

    @Test("reports retry results and treats ok, warning, drop and missing results as delivered")
    func reportsRetryResults() async throws {
        let events = (0 ..< 5).map { PostHogEvent(event: "e\($0)", distinctId: "user") }
        let uuids = events.map(\.uuid.postHogUuidString)
        server.captureV1ResponseHandler = { _, _ in
            HTTPStubsResponse(jsonObject: ["results": [
                uuids[0]: ["result": "ok"],
                uuids[1]: ["result": "warning", "details": "truncated"],
                uuids[2]: ["result": "drop", "details": "invalid"],
                uuids[3]: ["result": "retry"],
            ]], statusCode: 200, headers: ["Retry-After": "2"])
        }

        let result = await send(makeApi(), events)

        #expect(result.statusCode == 200)
        #expect(result.retryRecordIds == [uuids[3]])
        #expect(result.retryAfter == 2)
    }

    @Test("treats a 200 without a results map as delivered")
    func malformedSuccessIsDelivered() async {
        server.captureV1ResponseHandler = { _, _ in
            HTTPStubsResponse(data: Data("not json".utf8), statusCode: 200, headers: nil)
        }

        let result = await send(makeApi(), [PostHogEvent(event: "test", distinctId: "user")])

        #expect(result.statusCode == 200)
        #expect(result.retryRecordIds?.isEmpty ?? true)
    }

    @Test("a retry reuses the request ID and increments the attempt; an independent flush starts over")
    func retryIdentity() async throws {
        let events = (0 ..< 2).map { PostHogEvent(event: "e\($0)", distinctId: "user") }
        let retried = events[1].uuid.postHogUuidString
        server.captureV1EventResult = { uuid, index in
            index < 3 && uuid == retried ? "retry" : "ok"
        }
        server.captureV1ResponseHandler = nil
        let api = makeApi()

        // 1: both events, server asks to retry the second one.
        _ = await send(api, events)
        // 2: the retried event alone, still marked retry.
        _ = await send(api, [events[1]])
        // 3: retried again (whole batch this time via 503).
        server.captureV1ResponseHandler = { _, _ in
            HTTPStubsResponse(jsonObject: [], statusCode: 503, headers: nil)
        }
        _ = await send(api, [events[1]])
        server.captureV1ResponseHandler = nil
        // 4: delivered.
        _ = await send(api, [events[1]])
        // 5: an unrelated flush.
        _ = await send(api, [PostHogEvent(event: "next", distinctId: "user")])

        let requests = server.batchRequests
        try #require(requests.count == 5)
        let ids = requests.map { $0.value(forHTTPHeaderField: "PostHog-Request-Id") }
        let attempts = requests.map { $0.value(forHTTPHeaderField: "PostHog-Attempt") }
        let createdAt = try requests.map { try body($0)["created_at"] as? String }
        #expect(attempts == ["1", "2", "3", "4", "1"])
        #expect(Set(ids[0 ... 3]).count == 1)
        #expect(ids[4] != ids[0])
        #expect(Set(createdAt[0 ... 3]).count == 1)
    }

    @Test("falls back to /batch on 404 for the rest of the session")
    func fallsBackToBatchOn404() async throws {
        server.captureV1ResponseHandler = { _, _ in
            HTTPStubsResponse(jsonObject: [], statusCode: 404, headers: nil)
        }
        let api = makeApi()
        let event = PostHogEvent(event: "first", distinctId: "user")

        let result = await send(api, [event])

        #expect(result.statusCode == 200)
        #expect(!api.usesCaptureV1)
        var paths = server.batchRequests.map { $0.url?.path }
        #expect(paths == ["/proxy/i/v1/analytics/events", "/proxy/batch"])
        let legacyRequest = try #require(server.batchRequests.last)
        #expect(try body(legacyRequest)["api_key"] as? String == "phc_capture_v1")
        #expect(server.parsePostHogEvents(legacyRequest).map(\.uuid) == [event.uuid])

        _ = await send(api, [PostHogEvent(event: "second", distinctId: "user")])

        paths = server.batchRequests.map { $0.url?.path }
        #expect(paths == ["/proxy/i/v1/analytics/events", "/proxy/batch", "/proxy/batch"])
        // A new API instance (next launch) tries V1 again.
        #expect(makeApi().usesCaptureV1)
    }

    @Test("only 408 and 500/502/503/504 are retried", arguments: [
        (408, true), (500, true), (502, true), (503, true), (504, true),
        (301, false), (400, false), (401, false), (402, false), (403, false),
        (413, false), (415, false), (429, false), (501, false),
    ])
    func statusCodeClassification(statusCode: Int, retriable: Bool) {
        let endpoint = QueueEndpoint<PostHogEvent>.batch(api: makeApi())
        #expect(endpoint.isRetriableStatusCode(statusCode) == retriable)
    }
}

@Suite("Capture V1 queue partial retry", .serialized, .resetsGlobalState)
final class PostHogCaptureV1QueueTest {
    private let server: MockPostHogServer

    init() {
        deleteSafely(applicationSupportDirectoryURL())
        server = MockPostHogServer()
        server.start(batchCount: 0)
    }

    deinit {
        server.stop()
    }

    @Test("removes ok, warning and drop events and keeps retry events for the next attempt")
    func keepsOnlyRetryEvents() async throws {
        try await withMockedClock { clock in
            let config = PostHogConfig(projectToken: "phc_partial_\(UUID().uuidString)", host: "http://localhost:9001")
            config.flushAt = 100
            let storage = PostHogStorage(config)
            let queue = PostHogQueue(config, storage, .batch(api: PostHogApi(config)), nil)
            server.batchProjectToken = config.projectToken
            defer {
                queue.stop()
                queue.clear()
                deleteSafely(storage.appFolderUrl)
            }

            let events = ["ok", "warning", "drop", "retry"].map { PostHogEvent(event: $0, distinctId: "user") }
            let results = Dictionary(uniqueKeysWithValues: events.map { ($0.uuid.postHogUuidString, $0.event) })
            server.captureV1EventResult = { uuid, index in index == 1 ? results[uuid] ?? "ok" : "ok" }
            for event in events {
                queue.add(event)
            }

            queue.flush()
            await waitUntil { queue.depth == 1 }
            #expect(queue.depth == 1)
            #expect(queue.currentRetryCountForTesting == 1)
            let keptData = try #require(queue.fileQueue.peek(1).first)
            let kept = try #require(PostHogEvent.fromJSON(keptData))
            #expect(kept.uuid == events[3].uuid)

            // Paused for backoff until the clock moves past it.
            queue.flush()
            try await Task.sleep(nanoseconds: 100_000_000)
            #expect(server.batchRequests.count == 1)

            clock.date = clock.date.addingTimeInterval(retryDelay + 1)
            queue.flush()
            await waitUntil { queue.depth == 0 }
            #expect(queue.depth == 0)
            #expect(queue.currentRetryCountForTesting == 0)

            let requests = server.batchRequests
            try #require(requests.count == 2)
            #expect(server.parsePostHogEvents(requests[1]).map(\.uuid) == [events[3].uuid])
            #expect(requests[1].value(forHTTPHeaderField: "PostHog-Attempt") == "2")
            #expect(
                requests[1].value(forHTTPHeaderField: "PostHog-Request-Id")
                    == requests[0].value(forHTTPHeaderField: "PostHog-Request-Id")
            )
        }
    }
}
