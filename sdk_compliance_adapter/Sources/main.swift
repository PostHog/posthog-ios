import Foundation
import PostHog
import Vapor

// Global state for the adapter
class AdapterState {
    var posthogSDK: PostHogSDK?
    var capturedEvents: [[String: Any]] = []

    func reset() {
        capturedEvents = []
        RequestInterceptor.reset()
    }
}

let state = AdapterState()

// Configure and create the Vapor application
var env = try Environment.detect()
try LoggingSystem.bootstrap(from: &env)
let app = try await Application.make(env)

// Middleware to log all requests
app.middleware.use(RouteLoggingMiddleware())

// Health endpoint
app.get("health") { req async throws -> Response in
    let packageVersion = "3.0.0" // TODO: Read from Package.swift or version file
    let health = [
        "sdk_name": "posthog-ios",
        "sdk_version": packageVersion,
        "adapter_version": "1.0.0",
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

        enum CodingKeys: String, CodingKey {
            case apiKey = "api_key"
            case host
            case flushAt = "flush_at"
            case flushIntervalMs = "flush_interval_ms"
        }
    }

    let initReq = try req.content.decode(InitRequest.self)

    // Rewrite host.docker.internal to localhost since adapter runs on macOS host
    let host = initReq.host.replacingOccurrences(of: "host.docker.internal", with: "localhost")

    print("[ADAPTER] POST /init - api_key: \(initReq.apiKey), host: \(host) (original: \(initReq.host))")

    // Reset state
    state.reset()

    // Create PostHog configuration
    let config = PostHogConfig(apiKey: initReq.apiKey, host: host)

    // Configure for fast flushing in tests
    config.flushAt = initReq.flushAt ?? 1
    config.flushIntervalSeconds = TimeInterval(initReq.flushIntervalMs ?? 100) / 1000.0

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

// Flush endpoint - critical for tests!
app.post("flush") { req async throws -> Response in
    print("[ADAPTER] POST /flush - forcing SDK flush")

    guard let sdk = state.posthogSDK else {
        throw Abort(.badRequest, reason: "SDK not initialized. Call /init first.")
    }

    // Flush the SDK
    sdk.flush()

    // CRITICAL: Wait for the flush to complete
    // The SDK uses async network requests, so we need to wait for them to finish
    // Based on browser SDK experience, 2000ms should be enough
    try await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds

    print("[ADAPTER] Flush complete, waited 2s for network requests")

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

    // Reset the SDK
    state.posthogSDK?.reset()

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
