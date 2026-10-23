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
        #expect(sent["options"] as? [String: Bool] == ["process_person_profile": false])

        let properties = try #require(sent["properties"] as? [String: Any])
        for key in ["$session_id", "$window_id", "$lib", "$lib_version", "$process_person_profile"] {
            #expect(properties[key] == nil, "\(key) should not be in properties")
        }
        #expect(properties["custom"] as? String == "value")

        // The stored event is not reshaped.
        #expect(event.properties["$session_id"] as? String == "session-1")
        #expect(event.properties["$lib"] as? String == "posthog-ios")
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

    @Test("treats a 2xx whose transfer then failed as delivered, so its ok events aren't stored twice")
    func failedTransferAfterSuccessIsDelivered() {
        let uuids = [UUID().postHogUuidString, UUID().postHogUuidString]
        let identity = CaptureV1RequestIdentity(uuids: Set(uuids), requestId: "request", attempt: 1, createdAt: "now")
        let info = PostHogUploadInfo(statusCode: 200, error: URLError(.networkConnectionLost))

        let result = makeApi().captureV1Result(info, path: PostHogApi.captureV1AnalyticsPath, data: nil, uuids: uuids, identity: identity)

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

    @Test("a 404 is terminal and doesn't fall back to /batch")
    func notFoundIsTerminal() async throws {
        server.captureV1ResponseHandler = { _, _ in
            HTTPStubsResponse(jsonObject: [], statusCode: 404, headers: nil)
        }
        let api = makeApi()

        let result = await send(api, [PostHogEvent(event: "first", distinctId: "user")])

        #expect(result.statusCode == 404)
        #expect(result.retryRecordIds == nil)
        #expect(!QueueEndpoint<PostHogEvent>.batch(api: api).isRetriableStatusCode(404))

        _ = await send(api, [PostHogEvent(event: "second", distinctId: "user")])

        let paths = server.batchRequests.map { $0.url?.path }
        #expect(paths == ["/proxy/i/v1/analytics/events", "/proxy/i/v1/analytics/events"])
    }

    @Test("sends empty and whitespace session and window IDs at the root unchanged", arguments: ["", "  "])
    func sendsBlankSessionIds(value: String) async throws {
        let event = PostHogEvent(event: "test", distinctId: "user", properties: ["$session_id": value, "$window_id": value])
        _ = await send(makeApi(), [event])

        let request = try #require(server.batchRequests.first)
        let sent = try #require((try body(request)["batch"] as? [[String: Any]])?.first)
        #expect(sent["session_id"] as? String == value)
        #expect(sent["window_id"] as? String == value)
        let properties = try #require(sent["properties"] as? [String: Any])
        #expect(properties["$session_id"] == nil)
        #expect(properties["$window_id"] == nil)
    }

    @Test("drops non-string session and window IDs from the root and properties")
    func dropsNonStringSessionIds() async throws {
        let event = PostHogEvent(event: "test", distinctId: "user", properties: ["$session_id": 42, "$window_id": ["w"]])
        _ = await send(makeApi(), [event])

        let request = try #require(server.batchRequests.first)
        let sent = try #require((try body(request)["batch"] as? [[String: Any]])?.first)
        #expect(sent["session_id"] == nil)
        #expect(sent["window_id"] == nil)
        let properties = try #require(sent["properties"] as? [String: Any])
        #expect(properties["$session_id"] == nil)
        #expect(properties["$window_id"] == nil)
    }

    @Test("a dropped non-string ID logs its key and JSON type but not its value; null drops silently", arguments: [
        (42 as Any, "number"),
        (3.5 as Any, "number"),
        (true as Any, "bool"),
        (["secret"] as Any, "array"),
        (["k": "secret"] as Any, "object"),
        (NSNull() as Any, nil),
    ] as [(Any, String?)])
    func warnsOnNonStringId(value: Any, type: String?) {
        var properties: [String: Any] = ["$window_id": value, "other": "kept"]
        var warnings: [String] = []

        let lifted = PostHogApi.liftStringProperty("$window_id", from: &properties) { warnings.append($0) }

        #expect(lifted == nil)
        #expect(properties.keys.sorted() == ["other"])
        #expect(warnings == type.map { ["dropping $window_id: a \($0) value is not a string"] } ?? [])
    }

    @Test("follows a same-origin 307 or 308 with the same body and headers", arguments: [307, 308])
    func followsSameOriginRedirect(statusCode: Int) async throws {
        server.captureV1ResponseHandler = { _, index in
            index == 1
                ? HTTPStubsResponse(data: Data(), statusCode: Int32(statusCode), headers: [
                    "Location": "http://localhost:9001/moved/i/v1/analytics/events",
                ])
                : HTTPStubsResponse(jsonObject: ["results": [:]], statusCode: 200, headers: nil)
        }

        _ = await send(makeApi(), [PostHogEvent(event: "test", distinctId: "user")])

        // No check on the result: OHHTTPStubs delivers the 3xx without waiting for the redirect
        // decision, so the task can end with either response. The redirected request is what counts.
        let requests = server.batchRequests
        try #require(requests.count == 2)
        #expect(requests[1].url?.path == "/moved/i/v1/analytics/events")
        #expect(requests[1].httpMethod == "POST")
        #expect(requests[1].httpBody == requests[0].httpBody)
        for header in ["Authorization", "PostHog-Request-Id", "PostHog-Attempt", "PostHog-Sdk-Info", "Content-Encoding"] {
            #expect(requests[1].value(forHTTPHeaderField: header) == requests[0].value(forHTTPHeaderField: header))
        }
    }

    @Test("returns other redirects without following them", arguments: [
        (301, "http://localhost:9001/moved/i/v1/analytics/events"),
        (302, "http://localhost:9001/moved/i/v1/analytics/events"),
        (303, "http://localhost:9001/moved/i/v1/analytics/events"),
        (307, "http://other.example.com/i/v1/analytics/events"),
        (308, "https://localhost:9001/i/v1/analytics/events"),
        (307, "http://localhost:9002/i/v1/analytics/events"),
    ])
    func doesNotFollowOtherRedirects(statusCode: Int, location: String) async throws {
        server.captureV1ResponseHandler = { _, _ in
            HTTPStubsResponse(data: Data(), statusCode: Int32(statusCode), headers: ["Location": location])
        }

        let result = await send(makeApi(), [PostHogEvent(event: "test", distinctId: "user")])

        #expect(result.statusCode == statusCode)
        #expect(server.batchRequests.count == 1)
        #expect(!QueueEndpoint<PostHogEvent>.batch(api: makeApi()).isRetriableStatusCode(statusCode))
    }

    @Test("stops after 5 redirects")
    func stopsAfterMaxRedirects() throws {
        // Drives the delegate directly: a stubbed redirect chain races URLSession and can end
        // the task without a response.
        let host = try #require(URL(string: "http://localhost:9001"))
        let url = host.appendingPathComponent("i/v1/analytics/events")
        var original = URLRequest(url: url)
        original.setValue("request-id", forHTTPHeaderField: "PostHog-Request-Id")
        let task = URLSession.shared.dataTask(with: original)
        let redirect = URLRequest(url: host.appendingPathComponent("proxy/i/v1/analytics/events"))
        let response = try #require(HTTPURLResponse(url: url, statusCode: 307, httpVersion: nil, headerFields: nil))
        let handler = PostHogRedirectHandler(host: host, headerKeys: [])

        var followed: [Bool] = []
        for _ in 0 ... PostHogRedirectHandler.maxCaptureV1Redirects {
            handler.urlSession(URLSession.shared, task: task, willPerformHTTPRedirection: response, newRequest: redirect) {
                followed.append($0 != nil)
            }
        }

        #expect(followed == Array(repeating: true, count: PostHogRedirectHandler.maxCaptureV1Redirects) + [false])
    }

    @Test("re-sets the original headers on a followed redirect")
    func redirectResetsHeaders() throws {
        let host = try #require(URL(string: "https://us.i.posthog.com"))
        let url = host.appendingPathComponent("i/v1/analytics/events")
        var original = URLRequest(url: url)
        original.httpMethod = "POST"
        original.setValue("Bearer phc_test", forHTTPHeaderField: "Authorization")
        original.setValue("request-id", forHTTPHeaderField: "PostHog-Request-Id")
        original.setValue("2", forHTTPHeaderField: "PostHog-Attempt")
        // What URLSession hands the delegate: the new URL without `Authorization`.
        let stripped = try URLRequest(url: #require(URL(string: "https://US.i.posthog.com:443/next")))

        let redirected = try #require(PostHogRedirectHandler.captureV1Redirect(
            original: original, statusCode: 308, newRequest: stripped, host: host, hop: 5
        ))
        #expect(redirected.url?.path == "/next")
        #expect(redirected.httpMethod == "POST")
        #expect(redirected.value(forHTTPHeaderField: "Authorization") == "Bearer phc_test")
        #expect(redirected.value(forHTTPHeaderField: "PostHog-Request-Id") == "request-id")
        #expect(redirected.value(forHTTPHeaderField: "PostHog-Attempt") == "2")

        #expect(PostHogRedirectHandler.captureV1Redirect(
            original: original, statusCode: 308, newRequest: stripped, host: host, hop: 6
        ) == nil)
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

@Suite("Capture V1 event options", .serialized, .resetsGlobalState)
final class PostHogCaptureV1OptionsTest {
    private let server: MockPostHogServer

    init() {
        deleteSafely(applicationSupportDirectoryURL())
        server = MockPostHogServer()
        server.start(batchCount: 0)
    }

    deinit {
        server.stop()
    }

    private func makeApi() -> PostHogApi {
        PostHogApi(PostHogConfig(projectToken: "phc_options", host: "http://localhost:9001"))
    }

    /// Sends `event` through capture V1 and returns its wire JSON.
    private func sentEvent(_ event: PostHogEvent, api: PostHogApi? = nil) async throws -> [String: Any] {
        let api = api ?? makeApi()
        await withCheckedContinuation { continuation in
            api.captureV1(events: [event]) { _ in continuation.resume() }
        }
        let request = try #require(server.batchRequests.last)
        return try #require((server.parseRequest(request)?["batch"] as? [[String: Any]])?.first)
    }

    @Test("hoists each legacy property into its option", arguments: [
        ("$cookieless_mode", "cookieless_mode"),
        ("$ignore_sent_at", "disable_skew_correction"),
        ("$product_tour_id", "product_tour_id"),
        ("$process_person_profile", "process_person_profile"),
    ])
    func hoistsLegacyProperty(property: String, option: String) async throws {
        let sent = try await sentEvent(PostHogEvent(event: "test", distinctId: "user", properties: [property: "value"]))

        #expect(sent["options"] as? [String: String] == [option: "value"])
        #expect((sent["properties"] as? [String: Any])?[property] == nil)
    }

    @Test("an option wins over its legacy property, which is still removed; a null option is filled")
    func optionWinsOverLegacyProperty() async throws {
        let event = PostHogEvent(
            event: "test",
            distinctId: "user",
            properties: ["$cookieless_mode": false, "$product_tour_id": "legacy-tour", "custom": 1],
            options: ["cookieless_mode": true, "product_tour_id": NSNull(), "future_option": "kept"]
        )

        let sent = try await sentEvent(event)

        let options = try #require(sent["options"] as? [String: Any])
        #expect(options["cookieless_mode"] as? Bool == true)
        #expect(options["product_tour_id"] as? String == "legacy-tour")
        #expect(options["future_option"] as? String == "kept")
        #expect(options.count == 3)
        let properties = try #require(sent["properties"] as? [String: Any])
        #expect(Set(properties.keys) == ["custom"])
        // The stored event is not reshaped.
        #expect(event.properties["$cookieless_mode"] as? Bool == false)
    }

    @Test("sends empty options as {}")
    func sendsEmptyOptions() async throws {
        let sent = try await sentEvent(PostHogEvent(event: "test", distinctId: "user"))

        #expect((sent["options"] as? [String: Any])?.isEmpty == true)
    }

    @Test("replay snapshots don't send options")
    func snapshotsOmitOptions() async throws {
        let event = PostHogEvent(event: "$snapshot", distinctId: "user", properties: ["$session_id": "s"], options: ["cookieless_mode": true])
        await withCheckedContinuation { continuation in
            makeApi().snapshot(events: [event]) { _ in continuation.resume() }
        }

        let request = try #require(server.snapshotRequests.last)
        let body = try #require(request.body().flatMap { try? $0.gunzipped() })
        let sent = try #require((try JSONSerialization.jsonObject(with: body) as? [[String: Any]])?.first)
        #expect(sent["options"] == nil)
        #expect(sent["properties"] != nil)
    }

    @Test("options survive the queue's disk format, and events stored without options still decode")
    func persistsOptions() throws {
        let event = PostHogEvent(event: "test", distinctId: "user", options: ["cookieless_mode": true])
        let data = try #require(toJSONData(event.toJSON()))
        let decoded = try #require(PostHogEvent.fromJSON(data))
        #expect(decoded.options as? [String: Bool] == ["cookieless_mode": true])

        var legacy = PostHogEvent(event: "old", distinctId: "user", properties: ["$cookieless_mode": true]).toJSON()
        #expect(legacy["options"] == nil)
        legacy.removeValue(forKey: "options")
        let old = try #require(PostHogEvent.fromJSON(legacy))
        #expect(old.options.isEmpty)
        #expect(old.properties["$cookieless_mode"] as? Bool == true)
    }

    private func makeSDK(
        personProfiles: PostHogPersonProfiles = .identifiedOnly,
        flushAt: Int = 1,
        beforeSend: BeforeSendBlock? = nil
    ) -> PostHogSDK {
        let config = PostHogConfig(projectToken: "phc_options_\(UUID().uuidString)", host: "http://localhost:9001")
        config.flushAt = flushAt
        config.preloadFeatureFlags = false
        config.sendFeatureFlagEvent = false
        config.disableReachabilityForTesting = true
        config.disableQueueTimerForTesting = true
        config.disableFlushOnBackgroundForTesting = true
        config.captureApplicationLifecycleEvents = false
        config.personProfiles = personProfiles
        if let beforeSend {
            config.setBeforeSend(beforeSend)
        }
        server.batchProjectToken = config.projectToken
        return PostHogSDK.with(config)
    }

    /// Captures one event and returns its wire JSON.
    private func captureAndSend(_ sut: PostHogSDK, _ capture: (PostHogSDK) -> Void) async throws -> [String: Any] {
        server.reset(batchCount: 1)
        capture(sut)
        _ = try await getServerEvents(server)
        let request = try #require(server.batchRequests.first)
        return try #require((server.parseRequest(request)?["batch"] as? [[String: Any]])?.first)
    }

    @Test("registered and caller process_person_profile properties and options beat the SDK's")
    func processPersonProfilePrecedence() async throws {
        let sut = makeSDK(personProfiles: .never)
        defer { sut.close() }

        var sent = try await captureAndSend(sut) { $0.capture("test", properties: ["$process_person_profile": true]) }
        #expect((sent["options"] as? [String: Any])?["process_person_profile"] as? Bool == true)
        #expect((sent["properties"] as? [String: Any])?["$process_person_profile"] == nil)

        sut.register(["$process_person_profile": true])
        sent = try await captureAndSend(sut) { $0.capture("test") }
        sut.unregister("$process_person_profile")
        #expect((sent["options"] as? [String: Any])?["process_person_profile"] as? Bool == true)

        sent = try await captureAndSend(sut) {
            $0.capture("test", options: ["process_person_profile": true, "cookieless_mode": true])
        }
        #expect(sent["options"] as? [String: Bool] == ["process_person_profile": true, "cookieless_mode": true])
    }

    @Test("the SDK sends process_person_profile only as a false option when person processing is off")
    func processPersonProfileOnlyWhenOff() async throws {
        let personless = makeSDK(personProfiles: .never)
        var sent = try await captureAndSend(personless) { $0.capture("test") }
        personless.close()
        #expect(sent["options"] as? [String: Bool] == ["process_person_profile": false])
        #expect((sent["properties"] as? [String: Any])?["$process_person_profile"] == nil)

        let processed = makeSDK(personProfiles: .always)
        defer { processed.close() }
        sent = try await captureAndSend(processed) { $0.capture("test") }
        #expect((sent["options"] as? [String: Any])?.isEmpty == true)
        #expect((sent["properties"] as? [String: Any])?["$process_person_profile"] == nil)

        // A caller property overrides the SDK's state for that event, sent as the option.
        sent = try await captureAndSend(processed) { $0.capture("test", properties: ["$process_person_profile": false]) }
        #expect(sent["options"] as? [String: Bool] == ["process_person_profile": false])
        #expect((sent["properties"] as? [String: Any])?["$process_person_profile"] == nil)
    }

    @Test("the crash context keeps $process_person_profile false only when person processing is off")
    func crashContextKeepsPersonlessProperty() {
        for (personProfiles, expected) in [(PostHogPersonProfiles.never, false as Bool?), (.always, nil)] {
            let sut = makeSDK(personProfiles: personProfiles)
            var eventProperties: [String: Any]?
            let token = sut.onEventContextChanged.subscribe { eventProperties = $0["event_properties"] as? [String: Any] }
            sut.notifyContextDidChange()
            withExtendedLifetime(token) {}
            sut.close()
            #expect(eventProperties?["$process_person_profile"] as? Bool == expected)
        }
    }

    @Test("beforeSend has the final say over options")
    func beforeSendEditsOptions() async throws {
        let sut = makeSDK(personProfiles: .never) { event in
            #expect(event.options["product_tour_id"] as? String == "caller-tour")
            event.options["process_person_profile"] = true
            event.options["product_tour_id"] = "edited-tour"
            return event
        }
        defer { sut.close() }

        let sent = try await captureAndSend(sut) { $0.capture("test", options: ["product_tour_id": "caller-tour"]) }

        #expect(sent["options"] as? [String: AnyHashable] == ["process_person_profile": true, "product_tour_id": "edited-tour"])
    }

    @Test("a personless $set doesn't suppress the same properties set later with person processing")
    func personlessSetDoesNotDeduplicate() async throws {
        let sut = makeSDK(personProfiles: .always, flushAt: 2)
        defer { sut.close() }

        server.reset(batchCount: 1)
        sut.setPersonProperties(userPropertiesToSet: ["plan": "pro"], options: ["process_person_profile": false])
        sut.setPersonProperties(userPropertiesToSet: ["plan": "pro"])
        let events = try await getServerEvents(server)

        #expect(events.map(\.event) == ["$set", "$set"])
        #expect(events.last?.options["process_person_profile"] == nil)
    }

    @Test("a blank distinctId argument uses the current distinct ID", arguments: ["", "  "])
    func blankDistinctIdFallsBack(distinctId: String) async throws {
        let sut = makeSDK()
        defer { sut.close() }

        let sent = try await captureAndSend(sut) { $0.capture("test", distinctId: distinctId) }

        #expect(sent["distinct_id"] as? String == sut.getDistinctId())
    }

    @Test("a personal API key disables the SDK at setup")
    func personalApiKeyDisablesSdk() {
        let sut = PostHogSDK.with(PostHogConfig(projectToken: "phx_personal", host: "http://localhost:9001"))
        defer { sut.close() }

        // A disabled SDK has no storage, so it has no distinct ID.
        #expect(sut.getDistinctId() == "")
    }

    @Test("an event beforeSend returns again still gets a new UUID")
    func beforeSendReturningEarlierEventGetsNewUuid() async throws {
        var kept: PostHogEvent?
        let sut = makeSDK(flushAt: 2) { event in
            if kept == nil { kept = event }
            return kept
        }
        defer { sut.close() }

        server.reset(batchCount: 1)
        sut.capture("first")
        sut.capture("second")
        let events = try await getServerEvents(server)

        #expect(events.count == 2)
        #expect(Set(events.map(\.uuid)).count == 2)
    }

    @Test("the other event-sending methods apply options like capture does", arguments: [
        "screen", "identify", "identify existing user", "setPersonProperties", "alias", "group",
        "captureException Error", "captureException NSException",
    ])
    func eventSendingMethodsApplyOptions(method: String) async throws {
        let options: [String: Any] = ["process_person_profile": true, "cookieless_mode": true, "product_tour_id": "caller-tour"]
        // The setup identify and the call under test go out in one batch.
        let sut = makeSDK(flushAt: method == "identify existing user" ? 2 : 1) { event in
            if event.options["product_tour_id"] as? String == "caller-tour" {
                event.options["product_tour_id"] = "edited-tour"
            }
            return event
        }
        defer { sut.close() }
        // A legacy property the option must beat.
        sut.register(["$cookieless_mode": false])

        server.reset(batchCount: 1)
        let expectedEvent: String
        switch method {
        case "screen":
            sut.screen("Home", properties: ["$screen_name": "Other"], options: options)
            expectedEvent = "$screen"
        case "identify":
            sut.identify("user", options: options)
            expectedEvent = "$identify"
        case "identify existing user":
            sut.identify("user")
            sut.identify("user", userProperties: ["plan": "pro"], options: options)
            expectedEvent = "$set"
        case "setPersonProperties":
            sut.setPersonProperties(userPropertiesToSet: ["plan": "pro"], options: options)
            expectedEvent = "$set"
        case "alias":
            sut.alias("other-id", options: options)
            expectedEvent = "$create_alias"
        case "group":
            sut.group(type: "company", key: "acme", options: options)
            expectedEvent = "$groupidentify"
        case "captureException Error":
            sut.captureException(NSError(domain: "test", code: 1), options: options)
            expectedEvent = "$exception"
        default:
            sut.captureException(NSException(name: .genericException, reason: "boom"), options: options)
            expectedEvent = "$exception"
        }
        _ = try await getServerEvents(server)
        let request = try #require(server.batchRequests.first)
        let sent = try #require((server.parseRequest(request)?["batch"] as? [[String: Any]])?.last)

        #expect(sent["event"] as? String == expectedEvent)
        #expect(sent["options"] as? [String: AnyHashable] == [
            "process_person_profile": true, "cookieless_mode": true, "product_tour_id": "edited-tour",
        ])
        let properties = try #require(sent["properties"] as? [String: Any])
        #expect(properties["$cookieless_mode"] == nil)
        if method == "screen" {
            #expect(properties["$screen_name"] as? String == "Home")
        }
    }

    @Test("Objective-C keeps the old selectors and gains ones that take options")
    func objcSelectors() {
        let selectors = [
            "screenWithTitle:properties:", "screenWithTitle:properties:options:",
            "identifyWithDistinctId:userProperties:userPropertiesSetOnce:",
            "identifyWithDistinctId:userProperties:userPropertiesSetOnce:options:",
            "setPersonPropertiesWithUserPropertiesToSet:userPropertiesToSetOnce:",
            "setPersonPropertiesWithUserPropertiesToSet:userPropertiesToSetOnce:options:",
            "alias:", "alias:options:",
            "groupWithType:key:groupProperties:", "groupWithType:key:groupProperties:options:",
            "captureExceptionWithError:properties:", "captureExceptionWithError:properties:options:",
            "captureExceptionWithNSException:properties:", "captureExceptionWithNSException:properties:options:",
        ]
        for selector in selectors {
            #expect(PostHogSDK.instancesRespond(to: NSSelectorFromString(selector)), "\(selector)")
        }
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

    @Test("splits analytics batches at the byte limit and sends an event over it alone")
    func batchesByBytes() async throws {
        let config = PostHogConfig(projectToken: "phc_bytes_\(UUID().uuidString)", host: "http://localhost:9001")
        config.flushAt = 100
        let storage = PostHogStorage(config)
        let queue = PostHogQueue(config, storage, .batch(api: PostHogApi(config)), nil)
        server.batchProjectToken = config.projectToken
        defer {
            queue.stop()
            queue.clear()
            deleteSafely(storage.appFolderUrl)
        }

        // Two ~2 MiB events fit under 5 MiB; the ~6 MiB one doesn't fit with them and
        // is over the limit on its own.
        let small = String(repeating: "a", count: 2 * 1024 * 1024)
        let big = String(repeating: "b", count: 6 * 1024 * 1024)
        for blob in [small, small, big] {
            queue.add(PostHogEvent(event: "large", distinctId: "user", properties: ["blob": blob]))
        }
        queue.flush()
        await waitUntil(timeout: 10) { queue.depth == 0 }

        #expect(queue.depth == 0)
        #expect(server.batchRequests.map { server.parsePostHogEvents($0).count } == [2, 1])
    }
}

@Suite("Capture V1 AI lane", .serialized, .resetsGlobalState)
final class PostHogCaptureAiTest {
    private let server: MockPostHogServer

    init() {
        deleteSafely(applicationSupportDirectoryURL())
        server = MockPostHogServer()
        server.start(batchCount: 0)
    }

    deinit {
        server.stop()
    }

    private func makeSDK(configure: (PostHogConfig) -> Void = { _ in }, beforeSend: BeforeSendBlock? = nil) -> PostHogSDK {
        let config = PostHogConfig(projectToken: "phc_ai_\(UUID().uuidString)", host: "http://localhost:9001")
        config.flushAt = 1
        config.preloadFeatureFlags = false
        config.sendFeatureFlagEvent = false
        config.disableReachabilityForTesting = true
        config.disableQueueTimerForTesting = true
        config.disableFlushOnBackgroundForTesting = true
        config.captureApplicationLifecycleEvents = false
        if let beforeSend {
            config.setBeforeSend(beforeSend)
        }
        server.batchProjectToken = config.projectToken
        configure(config)
        return PostHogSDK.with(config)
    }

    @Test("captureAi sends to /i/v1/ai/events through beforeSend, and capture keeps $ai_ events on analytics")
    func routesByMethod() async throws {
        let sut = makeSDK { event in
            event.properties["edited"] = true
            return event
        }
        defer { sut.close() }

        let uuid = sut.captureAi("$ai_generation", distinctId: "user", properties: ["$ai_model": "gpt"], options: ["cookieless_mode": true])
        await waitUntil { self.server.aiRequests.count == 1 }

        let request = try #require(server.aiRequests.first)
        #expect(request.url?.path == "/i/v1/ai/events")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer \(sut.config.projectToken)")
        #expect(request.value(forHTTPHeaderField: "PostHog-Attempt") == "1")
        #expect(request.value(forHTTPHeaderField: "PostHog-Request-Id") != nil)
        #expect(request.timeoutInterval == 60)
        let event = try #require(server.parsePostHogEvents(request).first)
        #expect(event.event == "$ai_generation")
        #expect(event.uuid.postHogUuidString == uuid)
        #expect(event.distinctId == "user")
        #expect(event.properties["$ai_model"] as? String == "gpt")
        #expect(event.properties["edited"] as? Bool == true)
        #expect(event.options["cookieless_mode"] as? Bool == true)
        #expect(server.batchRequests.isEmpty)

        sut.capture("$ai_generation")
        await waitUntil { self.server.batchRequests.count == 1 }
        let batchRequest = try #require(server.batchRequests.first)
        #expect(server.parsePostHogEvents(batchRequest).map(\.event) == ["$ai_generation"])
        #expect(batchRequest.timeoutInterval < 60)
        #expect(server.aiRequests.count == 1)
    }

    @Test("captureAi returns nil when the event isn't queued")
    func returnsNilWhenNotQueued() {
        let sut = makeSDK { event in event.event == "$ai_span" ? nil : event }
        defer { sut.close() }

        #expect(sut.captureAi("$ai_span") == nil)
        #expect(sut.captureAi("$ai_generation", properties: ["$ai_input": String(repeating: "a", count: aiMaxEventBytes)]) == nil)
        sut.optOut()
        #expect(sut.captureAi("$ai_generation") == nil)
    }

    @Test("AI requests use captureAiTimeout and captureAiCompression, and analytics requests don't")
    func usesAiRequestSettings() async throws {
        let sut = makeSDK { config in
            config.captureAiTimeout = 90
            config.captureAiCompression = .none
        }
        defer { sut.close() }

        sut.captureAi("$ai_generation")
        await waitUntil { self.server.aiRequests.count == 1 }
        let request = try #require(server.aiRequests.first)
        #expect(request.timeoutInterval == 90)
        #expect(request.value(forHTTPHeaderField: "Content-Encoding") == nil)
        let batch = server.parseRequest(request, gzip: false)?["batch"] as? [[String: Any]]
        #expect(batch?.map { $0["event"] as? String } == ["$ai_generation"])

        sut.capture("signed_up")
        await waitUntil { self.server.batchRequests.count == 1 }
        let batchRequest = try #require(server.batchRequests.first)
        #expect(batchRequest.timeoutInterval < 90)
        #expect(batchRequest.value(forHTTPHeaderField: "Content-Encoding") == "gzip")
    }

    @Test("AI settings of 0 or less use their defaults, and captureAiMaxEventBytes can't exceed 8 MiB")
    func aiSettingLimits() {
        let config = PostHogConfig(projectToken: "phc_ai_settings")
        #expect(config.effectiveCaptureAiMaxQueueSize == 100)
        #expect(config.effectiveCaptureAiTimeout == 60)
        #expect(config.captureAiMaxStoredEventBytes == aiMaxEventBytes)

        config.captureAiMaxQueueSize = 3
        config.captureAiTimeout = 5
        config.captureAiMaxEventBytes = 1024
        #expect(QueueEndpoint.ai(api: PostHogApi(config)).maxQueueSize(config) == 3)
        #expect(config.effectiveCaptureAiTimeout == 5)
        #expect(config.captureAiMaxStoredEventBytes == 1024 + aiEventEnvelopeBytes)

        config.captureAiMaxQueueSize = 0
        config.captureAiTimeout = -1
        config.captureAiMaxEventBytes = 0
        #expect(config.effectiveCaptureAiMaxQueueSize == 100)
        #expect(config.effectiveCaptureAiTimeout == 60)
        #expect(config.captureAiMaxStoredEventBytes == aiMaxEventBytes)

        config.captureAiMaxEventBytes = 100 * 1024 * 1024
        #expect(config.captureAiMaxStoredEventBytes == aiMaxEventBytes)
    }

    @Test("drops an AI event over a lowered captureAiMaxEventBytes")
    func dropsEventOverConfiguredLimit() {
        let config = PostHogConfig(projectToken: "phc_ai_lowered", host: "http://localhost:9001")
        config.captureAiMaxEventBytes = 1024
        let storage = PostHogStorage(config)
        let queue = PostHogQueue(config, storage, .ai(api: PostHogApi(config)), nil)
        defer {
            queue.stop()
            queue.clear()
            deleteSafely(storage.appFolderUrl)
        }

        let overLimit = String(repeating: "a", count: 1024 + aiEventEnvelopeBytes)
        #expect(!queue.add(PostHogEvent(event: "$ai_generation", distinctId: "user", properties: ["$ai_input": overLimit])))
        #expect(queue.add(PostHogEvent(event: "$ai_generation", distinctId: "user", properties: ["$ai_input": "short"])))
        #expect(queue.depth == 1)
    }

    @Test("a 404 from the AI endpoint drops the batch")
    func notFoundIsTerminal() async throws {
        server.aiResponseHandler = { _, _ in HTTPStubsResponse(jsonObject: [:], statusCode: 404, headers: nil) }
        let config = PostHogConfig(projectToken: "phc_ai_404", host: "http://localhost:9001")
        let storage = PostHogStorage(config)
        let api = PostHogApi(config)
        let queue = PostHogQueue(config, storage, .ai(api: api), nil)
        defer {
            queue.stop()
            queue.clear()
            deleteSafely(storage.appFolderUrl)
        }

        queue.add(PostHogEvent(event: "$ai_generation", distinctId: "user"))
        queue.flush()
        await waitUntil { queue.depth == 0 }

        #expect(queue.depth == 0)
        #expect(server.aiRequests.count == 1)
        #expect(server.batchRequests.isEmpty)
    }

    @Test("drops an AI event over the size limit when it is queued")
    func dropsOversizedEvent() {
        let config = PostHogConfig(projectToken: "phc_ai_big", host: "http://localhost:9001")
        let storage = PostHogStorage(config)
        let queue = PostHogQueue(config, storage, .ai(api: PostHogApi(config)), nil)
        defer {
            queue.stop()
            queue.clear()
            deleteSafely(storage.appFolderUrl)
        }

        #expect(QueueEndpoint.ai(api: PostHogApi(config)).maxQueueBytes == aiMaxQueueBytes)
        let big = String(repeating: "a", count: aiMaxEventBytes)
        #expect(!queue.add(PostHogEvent(event: "$ai_generation", distinctId: "user", properties: ["$ai_input": big])))
        #expect(queue.depth == 0)
    }

    @Test("splits AI requests at the batch byte limit")
    func batchesByBytes() async throws {
        let config = PostHogConfig(projectToken: "phc_ai_bytes", host: "http://localhost:9001")
        config.flushAt = 100
        let storage = PostHogStorage(config)
        let queue = PostHogQueue(config, storage, .ai(api: PostHogApi(config)), nil)
        defer {
            queue.stop()
            queue.clear()
            deleteSafely(storage.appFolderUrl)
        }

        // Each event is a little over 2 MiB, so two fit under 5 MiB and the third goes next.
        let input = String(repeating: "a", count: 2 * 1024 * 1024)
        for _ in 0 ..< 3 {
            queue.add(PostHogEvent(event: "$ai_generation", distinctId: "user", properties: ["$ai_input": input]))
        }
        queue.flush()
        await waitUntil(timeout: 10) { queue.depth == 0 }

        #expect(queue.depth == 0)
        #expect(server.aiRequests.map { server.parsePostHogEvents($0).count } == [2, 1])
    }

    @Test("flushes once a batch's worth of bytes is queued, before flushAt is reached")
    func flushesAtBatchBytes() async throws {
        let config = PostHogConfig(projectToken: "phc_ai_byte_flush", host: "http://localhost:9001")
        config.flushAt = 100
        let storage = PostHogStorage(config)
        let queue = PostHogQueue(config, storage, .ai(api: PostHogApi(config)), nil)
        defer {
            queue.stop()
            queue.clear()
            deleteSafely(storage.appFolderUrl)
        }

        let input = String(repeating: "a", count: 3 * 1024 * 1024)
        queue.add(PostHogEvent(event: "$ai_generation", distinctId: "user", properties: ["$ai_input": input]))
        queue.add(PostHogEvent(event: "$ai_generation", distinctId: "user", properties: ["$ai_input": input]))
        await waitUntil(timeout: 10) { queue.depth == 0 }

        #expect(queue.depth == 0)
        #expect(server.aiRequests.map { server.parsePostHogEvents($0).count } == [1, 1])
    }
}
