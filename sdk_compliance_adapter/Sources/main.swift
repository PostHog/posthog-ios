import Foundation
import PostHog
import Vapor

// Redirect all SDK on-disk storage into a private sandbox this adapter fully owns, so a
// test can be isolated by wiping the sandbox wholesale — without the adapter having to
// mirror the SDK's internal path layout (Application Support / <bundleId> / <token> / …).
// CFFIXED_USER_HOME makes Foundation resolve NSHomeDirectory() (and the Application Support
// directory under it) here; HOME covers any path that derives from it. Set before any SDK
// call so the first storage lookup already uses the sandbox.
let adapterStorageHome = (NSTemporaryDirectory() as NSString).appendingPathComponent("posthog-ios-compliance-home")
setenv("CFFIXED_USER_HOME", adapterStorageHome, 1)
setenv("HOME", adapterStorageHome, 1)

// Global state for the adapter
class AdapterState {
    var posthogSDK: PostHogSDK?
    var capturedEvents: [[String: Any]] = []
    var apiKey: String?
    var host: String?

    func reset() {
        capturedEvents = []
        apiKey = nil
        host = nil
        RequestInterceptor.reset()
    }
}

let state = AdapterState()

// Wipe PostHog's on-disk storage so queued events, cached flags, and groups don't
// leak across tests. close() tears down the SDK but leaves its file-backed queue and
// storage on disk; the harness resets before every test and expects a clean slate.
// All SDK storage is redirected under adapterStorageHome (see CFFIXED_USER_HOME above),
// so nuking that one directory clears everything regardless of the SDK's internal path
// layout. The SDK recreates the directories it needs on the next setup().
func clearPostHogStorage() {
    try? FileManager.default.removeItem(atPath: adapterStorageHome)
}

// Configure and create the Vapor application
var env = try Environment.detect()
try LoggingSystem.bootstrap(from: &env)
let app = try await Application.make(env)

// Middleware to log all requests
app.middleware.use(RouteLoggingMiddleware())

// Health endpoint
app.get("health") { req async throws -> Response in
    let health: [String: Any] = [
        "sdk_name": postHogiOSSdkName,
        "sdk_version": postHogVersion,
        "adapter_version": "1.0.0",
        // Declares which test suites apply. The iOS SDK posts events to /batch
        // (capture_v0) with gzip; it does not implement the /i/v1/e capture_v1
        // protocol. Without this, the harness skips the capability-gated capture
        // suites entirely.
        "capabilities": ["capture_v0", "encoding_gzip"],
    ]

    print("[ADAPTER] GET /health")
    return try await health.encodeResponse(for: req)
}

// Init endpoint
app.post("init") { req async throws -> Response in
    struct InitRequest: Content {
        let apiKey: String
        let host: String
        let flushAt: Int?
        let flushIntervalMs: Int?
        let maxRetries: Int?

        enum CodingKeys: String, CodingKey {
            // Wire field name remains api_key, but it carries the PostHog project token.
            case apiKey = "api_key"
            case host
            case flushAt = "flush_at"
            case flushIntervalMs = "flush_interval_ms"
            case maxRetries = "max_retries"
        }
    }

    let initReq = try req.content.decode(InitRequest.self)

    // Empty token: setup() stays disabled but the singleton is non-nil, hanging a later
    // reloadFeatureFlags() (callback never fires when disabled). Fail fast.
    guard !initReq.apiKey.isEmpty else {
        throw Abort(.badRequest, reason: "Empty project token; SDK would not enable.")
    }

    // Rewrite host.docker.internal to localhost since adapter runs on macOS host
    let host = initReq.host.replacingOccurrences(of: "host.docker.internal", with: "localhost")

    print("[ADAPTER] POST /init - api_key: \(initReq.apiKey), host: \(host) (original: \(initReq.host))")

    // Tear down any previous SDK instance. setup() is a no-op while the singleton
    // is already enabled, so without this the first test's config (token, host)
    // would freeze for every subsequent test. close() is a no-op if not enabled.
    PostHogSDK.shared.close()
    clearPostHogStorage()

    // Reset state
    state.reset()

    // Create PostHog configuration
    let config = PostHogConfig(projectToken: initReq.apiKey, host: host)

    // Configure for fast flushing in tests
    config.flushAt = initReq.flushAt ?? 1
    config.flushIntervalSeconds = TimeInterval(initReq.flushIntervalMs ?? 100) / 1000.0
    config.maxRetries = initReq.maxRetries ?? config.maxRetries

    // Disable features for testing
    config.captureApplicationLifecycleEvents = false
    config.captureScreenViews = false
    config.preloadFeatureFlags = false
    config.sendFeatureFlagEvent = false
    config.remoteConfig = false
    config.enableSwizzling = false

    #if os(iOS)
        config.sessionReplay = false
        if #available(iOS 15.0, *) {
            config.surveys = false
        }
    #endif

    // Configure custom URLSession with our RequestInterceptor
    let sessionConfig = URLSessionConfiguration.default
    sessionConfig.protocolClasses = [RequestInterceptor.self]
    config.urlSessionConfiguration = sessionConfig

    print("[ADAPTER] Config - flushAt: \(config.flushAt), flushInterval: \(config.flushIntervalSeconds)s")
    print("[ADAPTER] Configured URLSession with RequestInterceptor")

    // Initialize PostHog SDK
    PostHogSDK.shared.setup(config)
    state.posthogSDK = PostHogSDK.shared
    state.apiKey = initReq.apiKey
    state.host = host

    print("[ADAPTER] PostHog SDK initialized")

    let result = ["status": "ok"]
    return try await result.encodeResponse(for: req)
}

// Capture endpoint
app.post("capture") { req async throws -> Response in
    struct CaptureRequest: Content {
        let event: String
        let distinctId: String?
        let properties: [String: AnyCodable]?

        enum CodingKeys: String, CodingKey {
            case event
            case distinctId = "distinct_id"
            case properties
        }
    }

    let captureReq = try req.content.decode(CaptureRequest.self)
    print("[ADAPTER] POST /capture - event: \(captureReq.event), distinct_id: \(captureReq.distinctId ?? "nil")")

    guard let sdk = state.posthogSDK else {
        throw Abort(.badRequest, reason: "SDK not initialized. Call /init first.")
    }

    // Convert properties
    var props: [String: Any] = [:]
    if let properties = captureReq.properties {
        for (key, value) in properties {
            props[key] = value.value
        }
    }

    // Capture the event with distinct_id parameter (don't use identify())
    // This ensures the distinct_id is set for THIS event, not globally
    sdk.capture(captureReq.event, distinctId: captureReq.distinctId, properties: props)

    print("[ADAPTER] Event captured: \(captureReq.event)")
    print("[ADAPTER] SDK should flush immediately (flushAt=1)")

    let result = ["status": "ok"]
    return try await result.encodeResponse(for: req)
}

// Feature flag evaluation endpoint
app.post("get_feature_flag") { req async throws -> Response in
    struct FlagRequest: Content {
        let key: String
        let distinctId: String
        let personProperties: [String: AnyCodable]?
        let groups: [String: AnyCodable]?
        let groupProperties: [String: AnyCodable]?
        let disableGeoip: Bool?
        let forceRemote: Bool?

        enum CodingKeys: String, CodingKey {
            case key
            case distinctId = "distinct_id"
            case personProperties = "person_properties"
            case groups
            case groupProperties = "group_properties"
            case disableGeoip = "disable_geoip"
            case forceRemote = "force_remote"
        }
    }

    let flagReq = try req.content.decode(FlagRequest.self)
    print("[ADAPTER] POST /get_feature_flag - key: \(flagReq.key), distinct_id: \(flagReq.distinctId)")

    guard let sdk = state.posthogSDK else {
        throw Abort(.badRequest, reason: "SDK not initialized. Call /init first.")
    }

    guard let apiKey = state.apiKey, let host = state.host else {
        throw Abort(.badRequest, reason: "SDK not initialized. Call /init first.")
    }

    var personProperties: [String: Any] = ["distinct_id": flagReq.distinctId]
    if let requestedPersonProperties = flagReq.personProperties {
        for (key, value) in requestedPersonProperties {
            personProperties[key] = value.value
        }
    }

    var groups: [String: Any] = [:]
    if let requestedGroups = flagReq.groups {
        for (key, value) in requestedGroups {
            groups[key] = value.value
        }
    }

    var groupProperties: [String: Any] = [:]
    if let requestedGroupProperties = flagReq.groupProperties {
        for (key, value) in requestedGroupProperties {
            groupProperties[key] = value.value
        }
    }

    let flagsPayload: [String: Any] = [
        "api_key": apiKey,
        "distinct_id": flagReq.distinctId,
        "person_properties": personProperties,
        "groups": groups,
        "group_properties": groupProperties,
        "geoip_disable": flagReq.disableGeoip ?? false,
        "flag_keys_to_evaluate": [flagReq.key],
    ]

    guard let flagsURL = URL(string: host.trimmingCharacters(in: CharacterSet(charactersIn: "/")) + "/flags/?v=2") else {
        throw Abort(.internalServerError, reason: "Invalid host URL: \(host)")
    }
    var flagsRequest = URLRequest(url: flagsURL)
    flagsRequest.httpMethod = "POST"
    flagsRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
    flagsRequest.httpBody = try JSONSerialization.data(withJSONObject: flagsPayload)

    let (data, _) = try await URLSession.shared.data(for: flagsRequest)
    let decoded = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    let flags = decoded?["featureFlags"] as? [String: Any] ?? decoded?["flags"] as? [String: Any]
    let value = flags?[flagReq.key] ?? false
    print("[ADAPTER] Flag \(flagReq.key) resolved to: \(String(describing: value))")

    sdk.capture(
        "$feature_flag_called",
        distinctId: flagReq.distinctId,
        properties: [
            "$feature_flag": flagReq.key,
            "$feature_flag_response": value,
            "$feature/\(flagReq.key)": value,
        ]
    )
    sdk.flush()
    await RequestInterceptor.waitForFlushSettle()

    var result: [String: Any] = ["success": true]
    result["value"] = value

    return try await result.encodeResponse(for: req)
}

// Flush endpoint - critical for tests!
app.post("flush") { req async throws -> Response in
    print("[ADAPTER] POST /flush - forcing SDK flush")

    guard let sdk = state.posthogSDK else {
        throw Abort(.badRequest, reason: "SDK not initialized. Call /init first.")
    }

    sdk.flush()
    await RequestInterceptor.waitForFlushSettle()

    print("[ADAPTER] Flush complete, waited for network requests")

    let result = ["status": "ok"]
    return try await result.encodeResponse(for: req)
}

// State endpoint - returns internal state for test assertions
app.get("state") { req async throws -> Response in
    print("[ADAPTER] GET /state")

    let stateData: [String: Any] = [
        "total_events_sent": RequestInterceptor.totalEventsSent,
        "requests_made": RequestInterceptor.trackedRequests.map { request in
            [
                "timestamp_ms": request.timestampMs,
                "status_code": request.statusCode,
                "retry_attempt": request.retryAttempt,
                "event_count": request.eventCount,
                "uuid_list": request.uuidList,
            ]
        },
    ]

    print("[ADAPTER] State - total_events_sent: \(RequestInterceptor.totalEventsSent), requests: \(RequestInterceptor.trackedRequests.count)")

    return try await stateData.encodeResponse(for: req)
}

// Reset endpoint
app.post("reset") { req async throws -> Response in
    print("[ADAPTER] POST /reset")

    // Fully tear down the SDK (close, not reset). PostHogSDK.reset() correctly
    // reloads feature flags as the anonymous user — that's intended SDK behavior
    // for a real-app logout, since the flag cache would otherwise be stale. The
    // harness's per-test mock window just doesn't accommodate it: the reload
    // lands as an extra /flags in the next test ("Expected 0, got 1" lifecycle
    // failures). close() does no network I/O, which fits test teardown.
    state.posthogSDK?.close()
    state.posthogSDK = nil
    clearPostHogStorage()

    // Reset adapter state
    state.reset()

    print("[ADAPTER] Reset complete")

    let result = ["status": "ok"]
    return try await result.encodeResponse(for: req)
}

// Middleware for logging requests
struct RouteLoggingMiddleware: AsyncMiddleware {
    func respond(to request: Request, chainingTo next: AsyncResponder) async throws -> Response {
        print("[ADAPTER] \(request.method) \(request.url.path)")
        return try await next.respond(to: request)
    }
}

// Helper for encoding dictionaries as JSON
extension Dictionary where Key == String, Value == Any {
    func encodeResponse(for _: Request) async throws -> Response {
        let data = try JSONSerialization.data(withJSONObject: self)
        var headers = HTTPHeaders()
        headers.add(name: .contentType, value: "application/json")
        return Response(status: .ok, headers: headers, body: .init(data: data))
    }
}

// Helper for encoding arrays as JSON
extension Array where Element == [String: Any] {
    func encodeResponse(for _: Request) async throws -> Response {
        let data = try JSONSerialization.data(withJSONObject: self)
        var headers = HTTPHeaders()
        headers.add(name: .contentType, value: "application/json")
        return Response(status: .ok, headers: headers, body: .init(data: data))
    }
}

// Helper to decode dynamic JSON
struct AnyCodable: Codable {
    let value: Any

    init(_ value: Any) {
        self.value = value
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if let bool = try? container.decode(Bool.self) {
            value = bool
        } else if let int = try? container.decode(Int.self) {
            value = int
        } else if let double = try? container.decode(Double.self) {
            value = double
        } else if let string = try? container.decode(String.self) {
            value = string
        } else if let array = try? container.decode([AnyCodable].self) {
            value = array.map(\.value)
        } else if let dict = try? container.decode([String: AnyCodable].self) {
            value = dict.mapValues { $0.value }
        } else {
            value = NSNull()
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()

        switch value {
        case let bool as Bool:
            try container.encode(bool)
        case let int as Int:
            try container.encode(int)
        case let double as Double:
            try container.encode(double)
        case let string as String:
            try container.encode(string)
        case let array as [Any]:
            try container.encode(array.map { AnyCodable($0) })
        case let dict as [String: Any]:
            try container.encode(dict.mapValues { AnyCodable($0) })
        default:
            try container.encodeNil()
        }
    }
}

// Run the server
print("[ADAPTER] Starting server on port 8080...")
try await app.execute()
try await app.asyncShutdown()
