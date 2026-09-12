import Foundation
import PostHog
import Vapor

// Set before any SDK storage lookup. Only this adapter-owned sandbox is removed on reset.
let adapterStorageHome = (NSTemporaryDirectory() as NSString).appendingPathComponent("posthog-ios-compliance-home")
setenv("CFFIXED_USER_HOME", adapterStorageHome, 1)
setenv("HOME", adapterStorageHome, 1)

class AdapterState {
    var posthogSDK: PostHogSDK?
    var tracker = RequestTracker()
    var identifiedId: String?

    func reset() {
        posthogSDK?.close()
        posthogSDK = nil
        identifiedId = nil
        try? FileManager.default.removeItem(atPath: adapterStorageHome)
        // In-flight callbacks retain their old tracker and cannot affect a later test.
        tracker = RequestTracker()
        RequestInterceptor.tracker = tracker
    }
}

let state = AdapterState()
var env = try Environment.detect()
try LoggingSystem.bootstrap(from: &env)
let app = try await Application.make(env)

app.get("health") { req async throws -> Response in
    let health: [String: Any] = [
        "sdk_name": postHogiOSSdkName,
        "sdk_version": postHogVersion,
        "adapter_version": "1.0.0",
        "capabilities": ["capture_v0", "encoding_gzip", "bootstrap_identity"],
        "runtime": "macOS shared core",
        "flags_mode": "initial identity bootstrap or identify; group + explicit reload + cached getter; preload disabled",
    ]
    return try await health.encodeResponse(for: req)
}

app.post("init") { req async throws -> Response in
    struct InitRequest: Content {
        let apiKey: String
        let host: String
        let flushAt: Int?
        let flushIntervalMs: Int?
        let maxRetries: Int?
        let distinctId: String?

        enum CodingKeys: String, CodingKey {
            case apiKey = "api_key"
            case host
            case flushAt = "flush_at"
            case flushIntervalMs = "flush_interval_ms"
            case maxRetries = "max_retries"
            case distinctId = "distinct_id"
        }
    }
    let input = try req.content.decode(InitRequest.self)
    guard !input.apiKey.isEmpty else {
        throw Abort(.badRequest, reason: "Empty project token")
    }
    if let distinctId = input.distinctId, distinctId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        throw Abort(.badRequest, reason: "Initial distinct ID must not be blank")
    }
    // The SDK runs on the host, while the CI mock runs in Docker.
    let host = input.host.replacingOccurrences(of: "host.docker.internal", with: "localhost")
    state.reset()
    let config = PostHogConfig(projectToken: input.apiKey, host: host)
    if let distinctId = input.distinctId {
        config.bootstrap = PostHogBootstrapConfig(distinctId: distinctId, isIdentifiedId: true)
    }
    config.flushAt = input.flushAt ?? 1
    let defaultIntervalMs = config.flushAt > 1 ? 5000 : 500
    config.flushIntervalSeconds = TimeInterval(input.flushIntervalMs ?? defaultIntervalMs) / 1000
    config.maxRetries = input.maxRetries ?? config.maxRetries

    // Isolate explicit actions, not the SDK's normal startup lifecycle. Keep the default
    // feature-flag-called event enabled so its payload and deduplication belong to the SDK.
    config.captureApplicationLifecycleEvents = false
    config.captureScreenViews = false
    config.preloadFeatureFlags = false
    config.enableSwizzling = false
    #if os(iOS)
        config.sessionReplay = false
        if #available(iOS 15.0, *) { config.surveys = false }
    #endif

    let tracker = state.tracker
    config.setBeforeSend { event in
        tracker.observeCapture(uuid: event.uuid.uuidString)
        return event
    }
    let sessionConfig = URLSessionConfiguration.default
    sessionConfig.protocolClasses = [RequestInterceptor.self]
    config.urlSessionConfiguration = sessionConfig
    PostHogSDK.shared.setup(config)
    state.posthogSDK = PostHogSDK.shared
    state.identifiedId = input.distinctId
    return try await["success": true].encodeResponse(for: req)
}

app.post("capture") { req async throws -> Response in
    struct CaptureRequest: Content {
        let event: String
        let distinctId: String?
        let properties: [String: AnyCodable]?
        let timestamp: String?

        enum CodingKeys: String, CodingKey {
            case event, properties, timestamp
            case distinctId = "distinct_id"
        }
    }
    let input = try req.content.decode(CaptureRequest.self)
    guard let sdk = state.posthogSDK else {
        throw Abort(.badRequest, reason: "Call /init first")
    }
    let timestamp = try parseCaptureTimestamp(input.timestamp)
    let tracker = state.tracker
    let observedUUID = tracker.trackCapture {
        sdk.capture(input.event, distinctId: input.distinctId,
                    properties: input.properties?.mapValues(\.value), timestamp: timestamp)
    }
    guard let uuid = observedUUID else {
        throw Abort(.internalServerError, reason: "Capture was not observed by beforeSend")
    }
    return try await["success": true, "uuid": uuid].encodeResponse(for: req)
}

app.post("get_feature_flag") { req async throws -> Response in
    struct FlagRequest: Content {
        let key: String
        let distinctId: String
        let personProperties: [String: AnyCodable]?
        let groups: [String: String]?
        let groupProperties: [String: [String: AnyCodable]]?
        let forceRemote: Bool?

        enum CodingKeys: String, CodingKey {
            case key, groups
            case distinctId = "distinct_id"
            case personProperties = "person_properties"
            case groupProperties = "group_properties"
            case forceRemote = "force_remote"
        }
    }
    let input = try req.content.decode(FlagRequest.self)
    guard let sdk = state.posthogSDK else {
        throw Abort(.badRequest, reason: "Call /init first")
    }
    guard !input.distinctId.isEmpty else {
        throw Abort(.badRequest, reason: "Empty distinct ID")
    }
    // An identified mobile client cannot switch directly to another identified user.
    // Do not reset its queue/cache behind a getter to impersonate a stateless server client.
    if let identifiedId = state.identifiedId, identifiedId != input.distinctId {
        throw Abort(.badRequest, reason: "Changing identified user requires a new /init")
    }
    sdk.resetPersonPropertiesForFlags(reloadFeatureFlags: false)
    sdk.setPersonPropertiesForFlags(input.personProperties?.mapValues(\.value) ?? [:], reloadFeatureFlags: false)
    sdk.resetGroupPropertiesForFlags(reloadFeatureFlags: false)
    for (type, properties) in input.groupProperties ?? [:] {
        sdk.setGroupPropertiesForFlags(type, properties: properties.mapValues(\.value), reloadFeatureFlags: false)
    }
    // Legacy callers can supply identity after initialization. Retain their SDK merge/reload.
    if state.identifiedId == nil {
        sdk.identify(input.distinctId)
        state.identifiedId = input.distinctId
    }
    for (type, key) in input.groups ?? [:] {
        sdk.group(type: type, key: key)
    }
    if input.forceRemote ?? true {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            sdk.reloadFeatureFlags { continuation.resume() }
        }
    }
    let value = sdk.getFeatureFlag(input.key)
    // Observe identity/group/called uploads before the next test resets its mock.
    sdk.flush()
    guard try await state.tracker.waitForAcknowledgments() else {
        throw Abort(.gatewayTimeout, reason: "Feature flag side effects remain unacknowledged")
    }
    return try await["success": true, "value": value ?? NSNull()].encodeResponse(for: req)
}

app.post("flush") { req async throws -> Response in
    guard let sdk = state.posthogSDK else {
        throw Abort(.badRequest, reason: "Call /init first")
    }
    let tracker = state.tracker
    let sentBefore = tracker.snapshot().sent
    sdk.flush()
    guard try await tracker.waitForAcknowledgments() else {
        throw Abort(.gatewayTimeout, reason: "Unacknowledged captures remain; SDK has no public queue-drain callback")
    }
    return try await["success": true, "events_flushed": tracker.snapshot().sent - sentBefore].encodeResponse(for: req)
}

app.get("state") { req async throws -> Response in
    let observation = state.tracker.snapshot()
    let result: [String: Any] = [
        "pending_events": observation.pending,
        "total_events_captured": observation.captured,
        "total_events_sent": observation.sent,
        "total_retries": observation.retries,
        "requests_made": observation.requests.map { request in
            [
                "timestamp_ms": request.timestampMs,
                "status_code": request.statusCode,
                "retry_attempt": request.retryAttempt,
                "event_count": request.eventCount,
                "uuid_list": request.uuidList,
            ] as [String: Any]
        },
    ]
    return try await result.encodeResponse(for: req)
}

app.post("reset") { req async throws -> Response in
    state.reset()
    return try await["success": true].encodeResponse(for: req)
}

extension Dictionary where Key == String, Value == Any {
    func encodeResponse(for _: Request) async throws -> Response {
        let data = try JSONSerialization.data(withJSONObject: self)
        var headers = HTTPHeaders()
        headers.add(name: .contentType, value: "application/json")
        return Response(status: .ok, headers: headers, body: .init(data: data))
    }
}

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
            value = dict.mapValues(\.value)
        } else {
            value = NSNull()
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch value {
        case let bool as Bool: try container.encode(bool)
        case let int as Int: try container.encode(int)
        case let double as Double: try container.encode(double)
        case let string as String: try container.encode(string)
        case let array as [Any]: try container.encode(array.map { AnyCodable($0) })
        case let dict as [String: Any]: try container.encode(dict.mapValues { AnyCodable($0) })
        default: try container.encodeNil()
        }
    }
}

try await app.execute()
try await app.asyncShutdown()
