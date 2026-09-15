import Foundation
@testable import PostHog
import Testing

@Suite(.serialized)
struct PostHogEventNullSerializationTests {
    private func properties() -> [String: Any] {
        let none: String? = nil
        return [
            "test": NSNull(),
            "optional": none as Any,
            "nested": ["drop": NSNull()],
            "items": ["1", NSNull(), 2, ["drop": NSNull()], [NSNull()]],
            "empty": "", "zero": 0, "enabled": false,
            "literal": "null", "literalUndefined": "undefined",
            "emptyArray": [], "emptyObject": [:],
            "$set": ["drop": NSNull()],
            "$set_once": ["drop": NSNull()],
            "$group_set": ["drop": NSNull()],
        ]
    }

    private var expected: [String: Any] {
        [
            "nested": [:], "items": ["1", NSNull(), 2, [:], [NSNull()]],
            "empty": "", "zero": 0, "enabled": false,
            "literal": "null", "literalUndefined": "undefined",
            "emptyArray": [], "emptyObject": [:],
            "$set": [:], "$set_once": [:], "$group_set": [:],
        ]
    }

    private func expectProperties(_ json: [String: Any], _ expected: [String: Any]) throws {
        let actual = try #require(json["properties"] as? [String: Any])
        #expect(NSDictionary(dictionary: actual).isEqual(to: expected))
    }

    @Test(arguments: ["Nullable Properties", "$screen", "$identify", "$groupidentify", "$exception", "$ai_generation", "$snapshot"])
    func eventSerialization(eventName: String) throws {
        let input = properties()
        let event = PostHogEvent(event: eventName, distinctId: "test-user", properties: input)
        let json = try #require(fromJSONData(try JSONSerialization.data(withJSONObject: event.toJSON())))
        try expectProperties(json, expected)
        #expect(event.properties["test"] is NSNull)
        #expect(input["test"] is NSNull)
        #expect(json["event"] as? String == eventName)
        #expect(json["distinct_id"] as? String == "test-user")
        #expect(json["uuid"] as? String == event.uuid.postHogUuidString)
    }

    @Test
    func foundationBridgingAndOptionalArraySlots() throws {
        let none: Int? = nil
        let nested = NSMutableDictionary(dictionary: ["drop": NSNull()])
        let items = NSMutableArray(array: [NSNull(), nested])
        let event = PostHogEvent(event: "bridged", distinctId: "test-user", properties: [
            "nested": nested, "items": items, "optionals": [none, 1] as [Int?],
        ])
        try expectProperties(event.toJSON(), ["nested": [:], "items": [NSNull(), [:]], "optionals": [NSNull(), 1]])
        #expect(nested["drop"] is NSNull)
        #expect(items.count == 2)
    }

    @Test
    func allNullPropertiesKeepEventAndGenericJSONIsUnchanged() throws {
        let event = PostHogEvent(event: "only null", distinctId: "test-user", properties: ["test": NSNull()])
        try expectProperties(event.toJSON(), [:])
        let generic = try #require(toJSONData(["test": NSNull()]))
        #expect(fromJSONData(generic)?["test"] is NSNull)
    }

    @Test
    func typedPayloadsKeepNullsOnlyOnTheirOwnEvents() throws {
        let reserved: [(String, [String: Any])] = [
            ("$snapshot", ["$snapshot_data": [["data": ["parentId": NSNull()]]]]),
            ("$exception", ["$exception_list": [["value": NSNull()]], "$debug_images": [["debug_id": NSNull()]]]),
            ("$feature_flag_called", [
                "$feature_flag_response": NSNull(), "$feature_flag_reason": NSNull(),
                "$feature_flag_id": NSNull(), "$feature_flag_version": NSNull(),
            ]),
        ]
        for (name, payload) in reserved {
            var input = payload
            input["custom"] = ["drop": NSNull()]
            var expected = payload
            expected["custom"] = [String: Any]()
            try expectProperties(PostHogEvent(event: name, distinctId: "test-user", properties: input).toJSON(), expected)
        }
        try expectProperties(PostHogEvent(event: "custom", distinctId: "test-user", properties: [
            "$snapshot_data": ["drop": NSNull()], "$feature_flag_response": NSNull(),
        ]).toJSON(), ["$snapshot_data": [:]])
    }

    // No SDK setup or shared Application Support storage. Every file belongs to this test.
    private func withDirectory(_ body: (URL) throws -> Void) throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent(".null-serialization-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try body(root)
    }

    @Test
    func beforeSendAdditionsPrivacyFilteringAndDrops() throws {
        let chain = BeforeSendChain<PostHogEvent>()
        chain.set([{ event in
            event.properties.removeValue(forKey: "private")
            event.properties["hookNull"] = NSNull()
            event.properties["hookItems"] = [NSNull(), ["drop": NSNull()]]
            return event
        }])
        let event = PostHogEvent(event: "hook", distinctId: "test-user", properties: ["private": "secret"])
        let result = try #require(chain.run(event))
        try expectProperties(result.toJSON(), ["hookItems": [NSNull(), [:]]])
        chain.set([{ _ in nil }])
        #expect(chain.run(event) == nil)
    }

    @Test
    func diskWriteRestoreAndLateMutation() throws {
        try withDirectory { root in
            let event = PostHogEvent(event: "disk", distinctId: "test-user", properties: properties())
            // Models values introduced downstream of capture-time sanitization, by enrichment/hooks.
            event.properties["hookNull"] = NSNull()
            event.properties["hookItems"] = [NSNull(), ["drop": NSNull()]]
            var expected = expected
            expected["hookItems"] = [NSNull(), [:]]
            let queue = PostHogFileBackedQueue(queue: root)
            queue.add(try #require(toJSONData(event.toJSON())))
            let data = try #require(PostHogFileBackedQueue(queue: root).peek(1).first)
            try expectProperties(try #require(fromJSONData(data)), expected)
            let restored = try #require(PostHogEvent.fromJSON(data))
            restored.properties["lateNull"] = NSNull()
            try expectProperties(restored.toJSON(), expected)
        }
    }

    @Test(arguments: [false, true])
    func apiWireSerialization(snapshot: Bool) async throws {
        let config = PostHogConfig(projectToken: "test-null-serialization", host: "http://127.0.0.1:1")
        let session = URLSessionConfiguration.ephemeral
        session.protocolClasses = [NullSerializationURLProtocol.self]
        config.urlSessionConfiguration = session
        let api = PostHogApi(config)
        // Old persisted events can still contain nulls; the final API encoder must clean them.
        let oldData = try JSONSerialization.data(withJSONObject: [
            "event": snapshot ? "$snapshot" : "wire", "distinct_id": "test-user", "properties": properties(),
        ])
        let event = try #require(PostHogEvent.fromJSON(oldData))
        event.properties["lateNull"] = NSNull()
        let info: PostHogUploadInfo = await withCheckedContinuation { continuation in
            if snapshot {
                api.snapshot(events: [event]) { continuation.resume(returning: $0) }
            } else {
                api.batch(events: [event]) { continuation.resume(returning: $0) }
            }
        }
        #expect(info.statusCode == 200)
        let body = try #require(NullSerializationURLProtocol.body)
        let json = try JSONSerialization.jsonObject(with: body)
        let events = try #require(snapshot ? json as? [[String: Any]] : (json as? [String: Any])?["batch"] as? [[String: Any]])
        try expectProperties(try #require(events.first), expected)
    }

    @Test
    func legacyRewriteCleansPropertiesWithoutChangingEnvelope() throws {
        try withDirectory { root in
            let old = root.appendingPathComponent("v2.json")
            let destination = root.appendingPathComponent("v3")
            let legacy: [String: Any] = [
                "event": "legacy", "distinct_id": "test-user", "timestamp": "2024-01-01T00:00:00Z",
                "message_id": "old-id", "envelopeNull": NSNull(),
                "properties": properties().filter { $0.key != "optional" }, "$set": ["drop": NSNull()],
            ]
            try JSONSerialization.data(withJSONObject: [legacy]).write(to: old)
            let queue = PostHogFileBackedQueue(queue: destination, oldQueues: [old])
            let data = try #require(queue.peek(1).first)
            let json = try #require(fromJSONData(data))
            try expectProperties(json, expected)
            #expect((json["$set"] as? [String: Any])?.isEmpty == true)
            #expect(json["envelopeNull"] is NSNull)
            #expect(json["message_id"] as? String == "old-id")
            try expectProperties(try #require(PostHogEvent.fromJSON(data)).toJSON(), expected)
        }
    }
}

// Intercepts every URL in the test session; unexpected requests cannot reach the network.
private final class NullSerializationURLProtocol: URLProtocol {
    private static let lock = NSLock()
    private static var capturedBody: Data?
    static var body: Data? { lock.withLock { capturedBody } }

    override static func canInit(with _: URLRequest) -> Bool {
        true
    }
    override static func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        do {
            #expect(request.url?.host == "127.0.0.1")
            var data = request.httpBody ?? Data()
            if let stream = request.httpBodyStream {
                stream.open()
                defer { stream.close() }
                var buffer = [UInt8](repeating: 0, count: 4096)
                while stream.hasBytesAvailable {
                    let count = stream.read(&buffer, maxLength: buffer.count)
                    if count <= 0 { break }
                    data.append(contentsOf: buffer.prefix(count))
                }
            }
            if request.value(forHTTPHeaderField: "Content-Encoding") == "gzip" {
                data = try data.gunzipped()
            }
            Self.lock.withLock { Self.capturedBody = data }
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Data("{}".utf8))
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
