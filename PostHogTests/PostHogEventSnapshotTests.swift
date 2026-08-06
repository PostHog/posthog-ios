import Foundation
@testable import PostHog
import Testing
import XCTest

@Suite("Event and request golden snapshots", .serialized, .resetsGlobalState)
final class PostHogEventSnapshotTests {
    private let server: MockPostHogServer

    init() {
        deleteSafely(applicationSupportDirectoryURL())
        server = MockPostHogServer(version: 4)
        server.start(batchCount: 0)
    }

    deinit {
        server.stop()
        deleteSafely(applicationSupportDirectoryURL())
    }

    @Test("final enriched event shapes and batch request match the golden")
    func enrichedEventBatchGolden() async throws {
        server.reset(batchCount: 1)
        server.flagsResponseDelay = 1
        let sut = makeSDK(flushAt: 5, identified: false)
        defer { sut.close() }
        sut.sessionManager.setSessionId("00000000-0000-7000-8000-000000000001")

        await withMockedNow({ Self.fixedDate }) {
            sut.register(["registered_property": "registered-value"])
            sut.capture(
                "order completed",
                properties: [
                    "amount": 42.5,
                    "items": ["coffee", "cake"],
                    "nested": ["coupon": "WELCOME"] as [String: Any],
                ],
                userProperties: ["plan": "pro"],
                userPropertiesSetOnce: ["first_order": true],
                groups: ["workspace": "workspace-1"]
            )
            sut.identify(
                "user-123",
                userProperties: ["email": "person@example.com"],
                userPropertiesSetOnce: ["created_at": "2024-01-01"]
            )
            sut.group(
                type: "company",
                key: "posthog",
                groupProperties: ["industry": "analytics", "employees": 120]
            )
            sut.captureFeatureInteraction(flag: "checkout-redesign", flagVariant: "test")
            sut.captureException(
                NSError(
                    domain: "SnapshotError",
                    code: 7,
                    userInfo: [NSLocalizedDescriptionKey: "Golden failure"]
                ),
                properties: ["handled_by": "snapshot-test"]
            )
        }

        _ = try await getServerEvents(server)
        let request = try #require(server.batchRequests.first)
        var snapshot = try requestSnapshot(request, gzip: true)
        try normalizeBatchSnapshot(&snapshot)
        try assertGolden(snapshot, named: "event-shapes-batch")
    }

    @Test("session replay request matches the golden")
    func sessionReplayRequestGolden() async throws {
        server.reset(batchCount: 0, snapshotCount: 1)
        let sut = makeSDK(flushAt: 20, identified: true)
        defer { sut.close() }
        sut.sessionManager.setSessionId("00000000-0000-7000-8000-000000000002")

        await withMockedNow({ Self.fixedDate }) {
            sut.capture(
                "$snapshot",
                properties: [
                    "$session_id": "00000000-0000-7000-8000-000000000002",
                    "$snapshot_source": "mobile",
                    "$snapshot_data": [
                        "type": 3,
                        "data": ["source": 0, "href": "https://example.com/checkout"] as [String: Any],
                        "timestamp": 1_704_164_645_000 as Int64,
                    ] as [String: Any],
                ]
            )
            sut.flush()
        }

        try await waitForSnapshotRequest(server)
        let request = try #require(server.snapshotRequests.first)
        var snapshot = try requestSnapshot(request, gzip: true)
        try normalizeReplaySnapshot(&snapshot)
        try assertGolden(snapshot, named: "session-replay-request")
    }

    @Test("SDK-driven feature flag request matches the golden")
    func featureFlagRequestGolden() async throws {
        let sut = makeSDK(flushAt: 20, identified: true)
        defer { sut.close() }

        sut.remoteConfig?.canReloadFlagsForTesting = false
        sut.group(type: "company", key: "posthog")
        sut.remoteConfig?.canReloadFlagsForTesting = true

        server.reset(batchCount: 0, flagsCount: 1)
        sut.setPersonPropertiesForFlags(
            ["email": "person@example.com", "plan": "enterprise"],
            reloadFeatureFlags: false
        )
        sut.setGroupPropertiesForFlags(
            "company",
            properties: ["industry": "analytics", "employees": 120],
            reloadFeatureFlags: false
        )

        let loaded = AsyncLatch()
        sut.reloadFeatureFlags { loaded.signal() }
        await loaded.wait()

        let request = try #require(server.flagsRequests.first)
        var snapshot = try requestSnapshot(request, gzip: false)
        try normalizeFlagsSnapshot(&snapshot)
        try assertGolden(snapshot, named: "feature-flags-request")
    }

    private func makeSDK(flushAt: Int, identified: Bool) -> PostHogSDK {
        deleteSafely(applicationSupportDirectoryURL())
        let config = PostHogConfig(projectToken: "snapshot-project-token", host: "http://localhost:9001")
        config.flushAt = flushAt
        config.maxBatchSize = flushAt
        config.captureApplicationLifecycleEvents = false
        config.captureScreenViews = false
        config.enableSwizzling = false
        config.preloadFeatureFlags = false
        config.disableReachabilityForTesting = true
        config.disableQueueTimerForTesting = true
        config.disableFlushOnBackgroundForTesting = true
        config.personProfiles = .always
        config.bootstrap = PostHogBootstrapConfig(
            distinctId: identified ? "user-123" : "anonymous-123",
            isIdentifiedId: identified,
            featureFlags: ["checkout-redesign": "test", "beta": true],
            featureFlagPayloads: ["checkout-redesign": ["color": "blue"]]
        )
        return PostHogSDK.with(config)
    }

    private func requestSnapshot(_ request: URLRequest, gzip: Bool) throws -> [String: Any] {
        let url = try #require(request.url)
        let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
        let bodyData = try #require(request.body())
        let decodedBody = gzip ? try bodyData.gunzipped() : bodyData
        let body = try JSONSerialization.jsonObject(with: decodedBody)

        var headers: [String: String] = [:]
        for (name, value) in request.allHTTPHeaderFields ?? [:] {
            headers[name.lowercased()] = value
        }
        if let contentLength = headers["content-length"] {
            try #require(Int(contentLength) != nil)
            headers["content-length"] = "<content-length>"
        }
        if let userAgent = headers["user-agent"] {
            let prefix = "posthog-ios/"
            #expect(userAgent.hasPrefix(prefix))
            #expect(userAgent.count > prefix.count)
            headers["user-agent"] = "posthog-ios/<sdk-version>"
        }

        return [
            "method": try #require(request.httpMethod),
            "url": [
                "scheme": try #require(components.scheme),
                "host": try #require(components.host),
                "port": try #require(components.port),
                "path": components.path,
                "query": (components.queryItems ?? []).map {
                    ["name": $0.name, "value": $0.value as Any? ?? NSNull()] as [String: Any]
                },
            ] as [String: Any],
            "headers": headers,
            "body": body,
        ]
    }

    private func normalizeBatchSnapshot(_ snapshot: inout [String: Any]) throws {
        var body = try #require(snapshot["body"] as? [String: Any])
        let sentAt = try #require(body["sent_at"] as? String)
        try #require(toISO8601Date(sentAt) != nil)
        body["sent_at"] = "<iso8601-timestamp>"

        var events = try #require(body["batch"] as? [[String: Any]])
        for index in events.indices {
            try normalizeEvent(&events[index])
        }
        body["batch"] = events
        snapshot["body"] = body
    }

    private func normalizeReplaySnapshot(_ snapshot: inout [String: Any]) throws {
        var events = try #require(snapshot["body"] as? [[String: Any]])
        #expect(events.count == 1)
        for index in events.indices {
            try normalizeEvent(&events[index])
        }
        snapshot["body"] = events
    }

    private func normalizeFlagsSnapshot(_ snapshot: inout [String: Any]) throws {
        var body = try #require(snapshot["body"] as? [String: Any])
        let timezone = try #require(body["timezone"] as? String)
        #expect(!timezone.isEmpty)
        body["timezone"] = "<timezone>"

        let deviceId = try #require(body["$device_id"] as? String)
        try #require(UUID(uuidString: deviceId) != nil)
        body["$device_id"] = "<uuid>"

        if let anonymousId = body["$anon_distinct_id"] {
            let anonymousUUID = try #require(anonymousId as? String)
            try #require(UUID(uuidString: anonymousUUID) != nil)
            body["$anon_distinct_id"] = "<uuid>"
        }

        if var personProperties = body["person_properties"] as? [String: Any] {
            try normalizeEnvironmentProperties(&personProperties)
            body["person_properties"] = personProperties
        }
        snapshot["body"] = body
    }

    private func normalizeEvent(_ event: inout [String: Any]) throws {
        let timestamp = try #require(event["timestamp"] as? String)
        try #require(toISO8601Date(timestamp) != nil)
        event["timestamp"] = "<iso8601-timestamp>"

        let uuid = try #require(event["uuid"] as? String)
        try #require(UUID(uuidString: uuid) != nil)
        let uuidParts = uuid.split(separator: "-")
        #expect(uuidParts.count == 5)
        #expect(uuidParts[2].first == "7")
        let variantCharacter = try #require(uuidParts[3].first)
        let variantNibble = try #require(Int(String(variantCharacter), radix: 16))
        #expect(variantNibble & 0xC == 0x8)
        event["uuid"] = "<uuid-v7>"

        var properties = try #require(event["properties"] as? [String: Any])
        try normalizeEnvironmentProperties(&properties)
        try normalizeFeatureFlagProperties(&properties)
        try normalizeExceptionProperties(&properties)
        event["properties"] = properties
    }

    private func normalizeEnvironmentProperties(_ properties: inout [String: Any]) throws {
        if let rawVersion = properties["$lib_version"] {
            let version = try #require(rawVersion as? String)
            #expect(!version.isEmpty)
            properties["$lib_version"] = "<sdk-version>"
        }

        // These keys are optional in SwiftPM's command-line test bundle but are populated by
        // the Xcode test host. Validate them when available, then omit them from the shared golden.
        for key in ["$app_name", "$app_version", "$app_build"] where properties[key] != nil {
            let value = try #require(properties[key] as? String)
            #expect(!value.isEmpty)
            properties.removeValue(forKey: key)
        }

        let stringKeys = [
            "$app_namespace", "$device_model", "$device_type", "$device_name", "$os_name",
            "$os_version", "$locale", "$timezone",
        ]
        for key in stringKeys where properties[key] != nil {
            _ = try #require(properties[key] as? String)
            properties[key] = "<environment-string>"
        }

        let boolKeys = [
            "$is_testflight", "$is_sideloaded", "$is_emulator", "$is_ios_running_on_mac",
            "$is_mac_catalyst_app", "$network_wifi", "$network_cellular",
        ]
        for key in boolKeys where properties[key] != nil {
            _ = try #require(properties[key] as? Bool)
            properties[key] = "<environment-bool>"
        }

        for key in ["$screen_width", "$screen_height"] where properties[key] != nil {
            _ = try #require(properties[key] as? NSNumber)
            properties[key] = "<environment-number>"
        }
    }

    private func normalizeFeatureFlagProperties(_ properties: inout [String: Any]) throws {
        guard let flags = properties["$active_feature_flags"] as? [String] else { return }
        properties["$active_feature_flags"] = flags.sorted()
    }

    private func normalizeExceptionProperties(_ properties: inout [String: Any]) throws {
        if let rawDebugImages = properties["$debug_images"] {
            let debugImages = try #require(rawDebugImages as? [[String: Any]])
            #expect(!debugImages.isEmpty)
            for image in debugImages {
                _ = try #require(image["code_file"] as? String)
                let debugId = try #require(image["debug_id"] as? String)
                try #require(UUID(uuidString: debugId) != nil)
                _ = try #require(image["image_addr"] as? String)
                _ = try #require(image["image_size"] as? NSNumber)
                #expect(image["type"] as? String == "macho")
            }
            properties["$debug_images"] = ["<debug-image>"]
        }

        guard var exceptions = properties["$exception_list"] as? [[String: Any]] else { return }
        for index in exceptions.indices {
            if exceptions[index]["thread_id"] != nil {
                _ = try #require(exceptions[index]["thread_id"] as? NSNumber)
                exceptions[index]["thread_id"] = "<thread-id>"
            }
            if var stacktrace = exceptions[index]["stacktrace"] as? [String: Any] {
                let frames = try #require(stacktrace["frames"] as? [[String: Any]])
                #expect(!frames.isEmpty)
                stacktrace["frames"] = ["<stack-frame>"]
                exceptions[index]["stacktrace"] = stacktrace
            }
        }
        properties["$exception_list"] = exceptions
    }

    private func assertGolden(_ actual: Any, named name: String) throws {
        let actualJSON = try canonicalJSON(actual)
        if ProcessInfo.processInfo.environment["UPDATE_EVENT_SHAPE_SNAPSHOTS"] == "1" {
            let sourceURL = URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent()
                .appendingPathComponent("Resources")
                .appendingPathComponent("\(name).json")
            try "\(actualJSON)\n".write(to: sourceURL, atomically: true, encoding: .utf8)
            return
        }

        let url = try #require(Bundle.test.url(forResource: name, withExtension: "json"))
        let expectedData = try Data(contentsOf: url)
        let expected = try JSONSerialization.jsonObject(with: expectedData)
        let expectedJSON = try canonicalJSON(expected)
        #expect(actualJSON == expectedJSON)
    }

    private func canonicalJSON(_ object: Any) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
        return try #require(String(data: data, encoding: .utf8))
    }

    private static let fixedDate = Date(timeIntervalSince1970: 1_704_164_645)
}
