//
//  PostHogApi.swift
//  PostHog
//
//  Created by Ben White on 06.02.23.
//

import Foundation

/// Common URLSession upload-response handler shared by capture V1, `/snapshot`,
/// and `/i/v1/logs`. Routes through `as?` so a missing HTTP response can't
/// crash inside a customer process.
func processUploadResponse(
    endpointName: String,
    data: Data?,
    response: URLResponse?,
    error: Error?,
    completion: @escaping (PostHogUploadInfo) -> Void
) {
    let httpResponse = response as? HTTPURLResponse
    // Parsed before the error branch: URLSession can deliver headers and then fail the
    // transfer, and a rate-limited response still carries the delay the server asked for.
    let retryAfter = httpResponse.flatMap { $0.value(forHTTPHeaderField: "Retry-After") }.flatMap(parseRetryAfter)

    if let error {
        hedgeLog("Error calling the \(endpointName) API: \(error).")
        // A 3xx left on a failed task is the redirect URLSession was still following, not an
        // outcome for the payload, so it's reported as no status. Honoring it would let the
        // policies that treat 3xx as terminal (logs, push unregister) delete durable records
        // that never reached the final host.
        let status = httpResponse?.statusCode
        let delivered = status.flatMap { 300 ... 399 ~= $0 ? nil : $0 }
        return completion(PostHogUploadInfo(statusCode: delivered, error: error, retryAfter: retryAfter))
    }

    guard let httpResponse else {
        hedgeLog("\(endpointName) API returned no HTTP response")
        return completion(PostHogUploadInfo(statusCode: nil, error: nil))
    }

    if !(200 ... 299 ~= httpResponse.statusCode) {
        let jsonBody = data.flatMap { fromJSONData($0, options: .allowFragments) }
        hedgeLog("Error sending to \(endpointName) API: status: \(httpResponse.statusCode), body: \(String(describing: jsonBody)).")
    } else {
        hedgeLog("\(endpointName) sent successfully.")
    }

    completion(PostHogUploadInfo(statusCode: httpResponse.statusCode, error: nil, retryAfter: retryAfter))
}

class PostHogApi {
    static var gzipData: (Data) throws -> Data = { try $0.gzipped() }

    private let config: PostHogConfig

    /// Snapshot at init; treated as immutable after setup.
    private let customRequestHeaders: [String: String]

    // default is 60s but we do 10s
    private let defaultTimeout: TimeInterval = 10

    /// Shared so connection pool, TLS state, and HTTP/2 streams survive
    /// between calls instead of being torn down per request.
    private let session: URLSession

    static let flagsRetryDelay: TimeInterval = 0.3

    /// Guards the capture V1 state below. In memory only: a new request ID
    /// after an app restart is fine, since the server only logs it.
    private let captureV1Lock = NSLock()
    // Keyed by endpoint path, so analytics and AI retries keep separate identities.
    private var captureV1PendingRetry: [String: CaptureV1RequestIdentity] = [:]

    init(_ config: PostHogConfig) {
        self.config = config
        customRequestHeaders = config.requestHeaders ?? [:]

        // Copy first so SDK mutations don't leak back to the caller's object.
        let sessionConfig = (config.urlSessionConfiguration?.copy() as? URLSessionConfiguration)
            ?? URLSessionConfiguration.default
        // Conditional request (If-Modified-Since/If-None-Match): server returns
        // 304 → cache hit, otherwise fresh body. Needed for /array/<token>/config
        // so we don't operate on stale config or flags.
        sessionConfig.requestCachePolicy = .reloadRevalidatingCacheData
        // Merge over caller-supplied headers; SDK keys overwrite collisions.
        var headers = sessionConfig.httpAdditionalHeaders ?? [:]
        // Content-Encoding is set per request, so a session-level value can't label a plain body as gzip.
        for key in headers.keys where (key as? String)?.lowercased() == "content-encoding" {
            headers.removeValue(forKey: key)
        }
        headers["Content-Type"] = "application/json; charset=utf-8"
        headers["User-Agent"] = "\(postHogSdkName)/\(postHogVersion)"
        headers["Accept-Encoding"] = "gzip"
        sessionConfig.httpAdditionalHeaders = headers
        // Decides each redirect: capture V1 follows only the configured origin, and other
        // endpoints strip custom headers on cross-host redirects so they don't leak.
        let redirectHandler = PostHogRedirectHandler(host: config.host, headerKeys: Array(customRequestHeaders.keys))
        session = URLSession(configuration: sessionConfig, delegate: redirectHandler, delegateQueue: nil)
    }

    /// `gzipped: true` adds `Content-Encoding: gzip` for upload endpoints
    /// (capture V1, /s/, /i/v1/logs) whose bodies are gzipped.
    private func getURLRequest(_ url: URL, gzipped: Bool = false, httpMethod: String = "POST") -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = httpMethod
        request.timeoutInterval = defaultTimeout
        applyCustomHeaders(&request)
        if gzipped {
            request.setValue("gzip", forHTTPHeaderField: "Content-Encoding")
        }
        return request
    }

    /// Adds custom headers to requests for the configured host, skipping SDK-managed keys.
    private func applyCustomHeaders(_ request: inout URLRequest) {
        guard !customRequestHeaders.isEmpty, request.url?.host == config.host.host else { return }
        for (key, value) in customRequestHeaders
            where request.value(forHTTPHeaderField: key) == nil
            && !Self.reservedHeaderKeys.contains(key.lowercased())
        {
            request.setValue(value, forHTTPHeaderField: key)
        }
    }

    /// SDK-managed headers that custom values can't override (compared lowercase).
    /// `Authorization` stays overridable for proxies on other endpoints; capture
    /// V1 sets its Bearer token after custom headers, so it always wins there.
    private static let reservedHeaderKeys: Set<String> = [
        "content-type", "user-agent", "accept-encoding", "content-encoding",
        "posthog-sdk-info", "posthog-attempt", "posthog-request-id", "posthog-request-timestamp",
    ]

    private func requestAndPayload(url: URL, data: Data, endpointName: String, httpMethod: String = "POST") -> (URLRequest, Data) {
        guard config.compression == .gzip else {
            return (getURLRequest(url, httpMethod: httpMethod), data)
        }
        do {
            return (getURLRequest(url, gzipped: true, httpMethod: httpMethod), try Self.gzipData(data))
        } catch {
            hedgeLog("Error gzipping the \(endpointName) body, sending it uncompressed: \(error).")
            return (getURLRequest(url, httpMethod: httpMethod), data)
        }
    }

    private func getEndpointURL(
        _ endpoint: String,
        queryItems: URLQueryItem...,
        relativeTo baseUrl: URL
    ) -> URL? {
        guard var components = URLComponents(
            url: baseUrl,
            resolvingAgainstBaseURL: true
        ) else {
            return nil
        }
        let path = "\(components.path)/\(endpoint)"
            .replacingOccurrences(of: "/+", with: "/", options: .regularExpression)
        components.path = path
        components.queryItems = queryItems
        return components.url
    }

    private func getRemoteConfigRequest() -> URLRequest? {
        guard let baseUrl: URL = switch config.host.absoluteString {
        case "https://us.i.posthog.com":
            URL(string: "https://us-assets.i.posthog.com")
        case "https://eu.i.posthog.com":
            URL(string: "https://eu-assets.i.posthog.com")
        default:
            config.host
        } else {
            return nil
        }

        let url = baseUrl.appendingPathComponent("/array/\(config.projectToken)/config")

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = defaultTimeout
        applyCustomHeaders(&request)
        return request
    }

    /// POSTs analytics events to capture V1 (`/i/v1/analytics/events`).
    ///
    /// The completion's `retryRecordIds` holds the UUIDs of events a 200 asked
    /// to retry.
    func captureV1(events: [PostHogEvent], completion: @escaping (PostHogUploadInfo) -> Void) {
        postCaptureV1(path: Self.captureV1AnalyticsPath, events: events, completion: completion)
    }

    /// POSTs AI events to the capture V1 AI endpoint (`/i/v1/ai/events`).
    /// Same wire format, per-event results and retry policy as `captureV1`.
    func captureAi(events: [PostHogEvent], completion: @escaping (PostHogUploadInfo) -> Void) {
        postCaptureV1(path: Self.captureV1AiPath, events: events, completion: completion)
    }

    static let captureV1AnalyticsPath = "/i/v1/analytics/events"
    static let captureV1AiPath = "/i/v1/ai/events"

    private func postCaptureV1(path: String, events: [PostHogEvent], completion: @escaping (PostHogUploadInfo) -> Void) {
        guard let url = getEndpointURL(path, relativeTo: config.host) else {
            hedgeLog("Malformed capture URL error.")
            return completion(PostHogUploadInfo(statusCode: nil, error: nil))
        }

        // The server rejects the whole batch with 400 when a UUID repeats.
        var seenUuids = Set<String>()
        let uniqueEvents = events.filter { seenUuids.insert($0.uuid.postHogUuidString).inserted }
        let uuids = uniqueEvents.map(\.uuid.postHogUuidString)
        let identity = nextCaptureV1Identity(path: path, uuids: Set(uuids))

        let toSend: [String: Any] = [
            "created_at": identity.createdAt,
            "batch": uniqueEvents.map(Self.captureV1JSON),
        ]

        guard let data = try? JSONSerialization.data(withJSONObject: toSend) else {
            hedgeLog("Error parsing the capture body")
            return completion(PostHogUploadInfo(statusCode: nil, error: nil))
        }

        var (request, payload) = requestAndPayload(url: url, data: data, endpointName: "capture")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(config.projectToken)", forHTTPHeaderField: "Authorization")
        request.setValue("\(postHogSdkName)/\(postHogVersion)", forHTTPHeaderField: "PostHog-Sdk-Info")
        request.setValue(String(identity.attempt), forHTTPHeaderField: "PostHog-Attempt")
        request.setValue(identity.requestId, forHTTPHeaderField: "PostHog-Request-Id")
        request.setValue(toISO8601String(Date()), forHTTPHeaderField: "PostHog-Request-Timestamp")

        session.uploadTask(with: request, from: payload) { [weak self] data, response, error in
            processUploadResponse(endpointName: "capture", data: data, response: response, error: error) { info in
                guard let self else { return completion(info) }
                completion(self.captureV1Result(
                    info, path: path, data: data, uuids: uuids, identity: identity,
                    duplicates: events.count - uniqueEvents.count
                ))
            }
        }.resume()
    }

    /// Reuses the request ID with the next attempt number when `uuids` is the
    /// set of events the previous request left to retry. Otherwise starts a new
    /// request at attempt 1.
    private func nextCaptureV1Identity(path: String, uuids: Set<String>) -> CaptureV1RequestIdentity {
        captureV1Lock.withLock {
            if let pending = captureV1PendingRetry[path], pending.uuids == uuids {
                return CaptureV1RequestIdentity(
                    uuids: uuids, requestId: pending.requestId, attempt: pending.attempt + 1, createdAt: pending.createdAt
                )
            }
            return CaptureV1RequestIdentity(
                uuids: uuids, requestId: UUID().postHogUuidString, attempt: 1, createdAt: toISO8601String(Date())
            )
        }
    }

    /// Reads the per-event results of a 2xx and records which events, if any,
    /// the next request retries under the same identity.
    private func captureV1Result(
        _ info: PostHogUploadInfo,
        path: String,
        data: Data?,
        uuids: [String],
        identity: CaptureV1RequestIdentity,
        duplicates: Int
    ) -> PostHogUploadInfo {
        var retryUuids: Set<String> = []
        // Duplicate UUIDs are dropped before sending.
        var dropped = duplicates

        if let statusCode = info.statusCode, 200 ... 299 ~= statusCode {
            // A body without a readable results map counts as delivered, so a
            // broken success can't loop forever.
            let results = data.flatMap { fromJSONData($0) }?["results"] as? [String: Any]
            if results == nil {
                hedgeLog("Capture returned \(statusCode) without per-event results, treating the batch as delivered.")
            }
            // Events missing from the results count as delivered.
            for uuid in uuids {
                guard let entry = results?[uuid] as? [String: Any] else { continue }
                switch entry["result"] as? String {
                case "retry":
                    retryUuids.insert(uuid)
                case "drop":
                    dropped += 1
                default:
                    break
                }
            }
        } else if info.statusCode.map(isCaptureV1RetriableStatusCode) ?? true {
            // No response or a retriable status: the whole batch is resent.
            retryUuids = Set(uuids)
        }

        // Counts only: event UUIDs and server details can identify users.
        if dropped > 0 || !retryUuids.isEmpty {
            hedgeLog("Capture: \(dropped) dropped, \(retryUuids.count) to retry.")
        }

        captureV1Lock.withLock {
            captureV1PendingRetry[path] = retryUuids.isEmpty ? nil : CaptureV1RequestIdentity(
                uuids: retryUuids, requestId: identity.requestId, attempt: identity.attempt, createdAt: identity.createdAt
            )
        }

        return PostHogUploadInfo(
            statusCode: info.statusCode,
            error: info.error,
            retryAfter: info.retryAfter,
            retryRecordIds: info.statusCode.map { 200 ... 299 ~= $0 } == true ? retryUuids : nil
        )
    }

    /// Legacy properties and the capture V1 option each one fills, in the
    /// order posthog-python, posthog-go and posthog-rs use.
    static let legacyOptionProperties: [(property: String, option: String)] = [
        ("$cookieless_mode", "cookieless_mode"),
        ("$ignore_sent_at", "disable_skew_correction"),
        ("$product_tour_id", "product_tour_id"),
        ("$process_person_profile", "process_person_profile"),
    ]

    /// Shapes a stored event for capture V1. `$session_id` and `$window_id`
    /// move to the event root, and `$lib`/`$lib_version` are dropped because
    /// the server reads them from `PostHog-Sdk-Info`.
    ///
    /// Legacy option properties are hoisted here, after `beforeSend`, so events
    /// queued by older versions are hoisted too. Each is always removed from
    /// properties and fills its option only when the option is missing or null.
    /// Values aren't coerced: the server validates them.
    private static func captureV1JSON(_ event: PostHogEvent) -> [String: Any] {
        var properties = event.properties
        properties.removeValue(forKey: "$lib")
        properties.removeValue(forKey: "$lib_version")

        var options = event.options
        for (property, option) in legacyOptionProperties {
            guard let legacy = properties.removeValue(forKey: property) else { continue }
            if options[option] == nil || options[option] is NSNull {
                options[option] = legacy
            }
        }

        var json: [String: Any] = [
            "event": event.event,
            "uuid": event.uuid.postHogUuidString,
            "distinct_id": event.distinctId,
            "timestamp": toISO8601String(event.timestamp),
        ]
        // Always removed from properties; only a non-empty string is sent at the root.
        if let sessionId = properties.removeValue(forKey: "$session_id") as? String, !sessionId.isEmpty {
            json["session_id"] = sessionId
        }
        if let windowId = properties.removeValue(forKey: "$window_id") as? String, !windowId.isEmpty {
            json["window_id"] = windowId
        }
        json["options"] = options
        json["properties"] = properties
        return json
    }

    func snapshot(events: [PostHogEvent], completion: @escaping (PostHogUploadInfo) -> Void) {
        guard let url = getEndpointURL(config.snapshotEndpoint, relativeTo: config.host) else {
            hedgeLog("Malformed snapshot URL error.")
            return completion(PostHogUploadInfo(statusCode: nil, error: nil))
        }

        for event in events {
            event.projectToken = config.projectToken
        }

        // Options are an analytics capture field; replay doesn't send them.
        let toSend = events.map { event -> [String: Any] in
            var json = event.toJSON()
            json.removeValue(forKey: "options")
            return json
        }

        guard let data = try? JSONSerialization.data(withJSONObject: toSend) else {
            hedgeLog("Error parsing the snapshot body")
            return completion(PostHogUploadInfo(statusCode: nil, error: nil))
        }

        let (request, payload) = requestAndPayload(url: url, data: data, endpointName: "snapshot")

        session.uploadTask(with: request, from: payload) { data, response, error in
            processUploadResponse(endpointName: "snapshot", data: data, response: response, error: error, completion: completion)
        }.resume()
    }

    /// POSTs an OpenTelemetry log payload to `/i/v1/logs?token=<projectToken>`.
    /// The token is carried in the query string because the endpoint expects it
    /// there rather than in the body.
    ///
    /// - Parameter completion: Invoked exactly once on every code path (including
    ///   early-return errors) so the calling queue's `isFlushing` flag clears.
    func logs(payload: [String: Any], completion: @escaping (PostHogUploadInfo) -> Void) {
        let url = getEndpointURL(
            "/i/v1/logs",
            queryItems: URLQueryItem(name: "token", value: config.projectToken),
            relativeTo: config.host
        )
        guard let url else {
            hedgeLog("Malformed logs URL error.")
            return completion(PostHogUploadInfo(statusCode: nil, error: nil))
        }

        guard let data = try? JSONSerialization.data(withJSONObject: payload) else {
            hedgeLog("Error parsing the logs body")
            return completion(PostHogUploadInfo(statusCode: nil, error: nil))
        }

        let (request, uploadPayload) = requestAndPayload(url: url, data: data, endpointName: "logs")

        session.uploadTask(with: request, from: uploadPayload) { data, response, error in
            processUploadResponse(endpointName: "logs", data: data, response: response, error: error, completion: completion)
        }.resume()
    }

    /// Registers a device push token with PostHog so Workflows can deliver push notifications.
    /// `platform` is always `ios`: registration is iOS-only in v1 (the backend rejects `macos`).
    ///
    /// - Parameter completion: Invoked exactly once on every code path with the HTTP status and any
    ///   `Retry-After` header, so the caller can apply the shared retry/backoff policy.
    func pushSubscription(
        distinctId: String,
        deviceToken: String,
        appId: String,
        identityToken: String?,
        completion: @escaping (PostHogUploadInfo) -> Void
    ) {
        sendPushSubscription(
            httpMethod: "POST", endpointName: "push subscription",
            distinctId: distinctId, deviceToken: deviceToken, appId: appId,
            identityToken: identityToken, completion: completion
        )
    }

    /// Unregisters a device token: `DELETE /api/push_subscriptions/` with the same 5-field body as
    /// registration (the backend `$unset`s `$device_push_subscription_<app_id>`). This call itself
    /// fires once, but the caller persists a durable "delete" intent before calling it and retries
    /// passively on `flush()`/next launch (and once on a 401 identity re-mint) until it succeeds.
    func deletePushSubscription(
        distinctId: String,
        deviceToken: String,
        appId: String,
        identityToken: String?,
        completion: @escaping (PostHogUploadInfo) -> Void
    ) {
        sendPushSubscription(
            httpMethod: "DELETE", endpointName: "push unsubscription",
            distinctId: distinctId, deviceToken: deviceToken, appId: appId,
            identityToken: identityToken, completion: completion
        )
    }

    private func sendPushSubscription(
        httpMethod: String,
        endpointName: String,
        distinctId: String,
        deviceToken: String,
        appId: String,
        identityToken: String?,
        completion: @escaping (PostHogUploadInfo) -> Void
    ) {
        guard let url = getEndpointURL("/api/push_subscriptions/", relativeTo: config.host) else {
            hedgeLog("Malformed push subscriptions URL error.")
            return completion(PostHogUploadInfo(statusCode: nil, error: nil))
        }

        // The token key is omitted entirely when absent — the backend treats a missing key as
        // "unsigned"; an explicit null would fail its string check.
        var toSend: [String: Any] = [
            "api_key": config.projectToken,
            "distinct_id": distinctId,
            "device_token": deviceToken,
            "platform": "ios",
            "app_id": appId,
        ]
        if let identityToken {
            toSend["identity_token"] = identityToken
        }

        guard let data = try? JSONSerialization.data(withJSONObject: toSend) else {
            hedgeLog("Error parsing the \(endpointName) body")
            return completion(PostHogUploadInfo(statusCode: nil, error: nil))
        }

        let (request, payload) = requestAndPayload(url: url, data: data, endpointName: endpointName, httpMethod: httpMethod)

        session.uploadTask(with: request, from: payload) { data, response, error in
            processUploadResponse(endpointName: endpointName, data: data, response: response, error: error, completion: completion)
        }.resume()
    }

    func flags(
        distinctId: String,
        anonymousId: String?,
        deviceId: String? = nil,
        groups: [String: String],
        personProperties: [String: Any],
        groupProperties: [String: [String: Any]]? = nil,
        completion: @escaping ([String: Any]?, _ error: Error?) -> Void
    ) {
        let url = getEndpointURL(
            "/flags",
            queryItems: URLQueryItem(name: "v", value: "2"),
            relativeTo: config.host
        )

        guard let url else {
            hedgeLog("Malformed flags URL error.")
            return completion(nil, nil)
        }

        let request = getURLRequest(url)

        var toSend: [String: Any] = [
            // Wire field name remains api_key, but it carries the PostHog project token.
            "api_key": config.projectToken,
            "distinct_id": distinctId,
            "groups": groups,
            "timezone": TimeZone.current.identifier,
            "geoip_disable": config.disableGeoIp,
        ]

        if let anonymousId {
            toSend["$anon_distinct_id"] = anonymousId
        }

        if let deviceId {
            toSend["$device_id"] = deviceId
        }

        if !personProperties.isEmpty {
            toSend["person_properties"] = personProperties
        }

        if let groupProperties, !groupProperties.isEmpty {
            toSend["group_properties"] = groupProperties
        }

        if let evaluationContexts = config.evaluationContexts, !evaluationContexts.isEmpty {
            toSend["evaluation_contexts"] = evaluationContexts
        }

        guard let data = try? JSONSerialization.data(withJSONObject: toSend) else {
            hedgeLog("Error parsing the flags body")
            return completion(nil, nil)
        }

        uploadFlagsRequest(request, payload: data, retryCount: 0, completion: completion)
    }

    private func uploadFlagsRequest(
        _ request: URLRequest,
        payload: Data,
        retryCount: Int,
        completion: @escaping ([String: Any]?, _ error: Error?) -> Void
    ) {
        session.uploadTask(with: request, from: payload) { data, response, error in
            if let error {
                if Self.isRetryableFlagsError(error), retryCount < self.config.featureFlagRequestMaxRetries {
                    self.retryFlagsRequest(
                        request,
                        payload: payload,
                        retryCount: retryCount,
                        reason: String(describing: error),
                        completion: completion
                    )
                    return
                }

                hedgeLog("Error calling the flags API: \(error)")
                return completion(nil, error)
            }

            guard let data else {
                hedgeLog("Error parsing the flags response: no data")
                return completion(nil, nil)
            }

            guard let httpResponse = response as? HTTPURLResponse else {
                hedgeLog("Error parsing the flags response: unexpected response type")
                return completion(nil, nil)
            }

            if !(200 ... 299 ~= httpResponse.statusCode) {
                let jsonBody = fromJSONData(data, options: .allowFragments)
                let retryReason = "status: \(httpResponse.statusCode), body: \(String(describing: jsonBody))"
                let errorMessage = "Error calling flags API: \(retryReason)."

                if Self.isRetryableFlagsStatusCode(httpResponse.statusCode), retryCount < self.config.featureFlagRequestMaxRetries {
                    self.retryFlagsRequest(
                        request,
                        payload: payload,
                        retryCount: retryCount,
                        reason: retryReason,
                        completion: completion
                    )
                    return
                }

                hedgeLog(errorMessage)
                return completion(nil,
                                  InternalPostHogError(description: errorMessage))
            } else {
                hedgeLog("Flags called successfully.")
            }

            do {
                let jsonData = try JSONSerialization.jsonObject(with: data, options: .allowFragments) as? [String: Any]
                completion(jsonData, nil)
            } catch {
                hedgeLog("Error parsing the flags response: \(error)")
                completion(nil, error)
            }
        }.resume()
    }

    private func retryFlagsRequest(
        _ request: URLRequest,
        payload: Data,
        retryCount: Int,
        reason: String,
        completion: @escaping ([String: Any]?, _ error: Error?) -> Void
    ) {
        let nextRetryCount = retryCount + 1
        let delay = Self.featureFlagsRetryDelay(forFailedAttempt: nextRetryCount)
        hedgeLog(
            "Error calling the flags API: \(reason). Retrying in \(delay) seconds (attempt \(nextRetryCount)/\(config.featureFlagRequestMaxRetries))."
        )
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + delay) {
            self.uploadFlagsRequest(request, payload: payload, retryCount: nextRetryCount, completion: completion)
        }
    }

    static func featureFlagsRetryDelay(forFailedAttempt failedAttempt: Int) -> TimeInterval {
        min(flagsRetryDelay * pow(2.0, TimeInterval(failedAttempt - 1)), maxRetryDelay)
    }

    private static func isRetryableFlagsError(_ error: Error) -> Bool {
        let nsError = error as NSError
        guard nsError.domain == NSURLErrorDomain else {
            return false
        }
        return nsError.code == NSURLErrorTimedOut || nsError.code == NSURLErrorNetworkConnectionLost
    }

    private static func isRetryableFlagsStatusCode(_ statusCode: Int) -> Bool {
        statusCode == 502 || statusCode == 504
    }

    func remoteConfig(
        completion: @escaping ([String: Any]?, _ error: Error?) -> Void
    ) {
        guard let request = getRemoteConfigRequest() else {
            hedgeLog("Error calling the remote config API: unable to create request")
            return
        }

        let task = session.dataTask(with: request) { data, response, error in
            if let error {
                hedgeLog("Error calling the remote config API: \(error.localizedDescription)")
                return completion(nil, error)
            }

            guard let data else {
                hedgeLog("Error parsing the remote config response: no data")
                return completion(nil, nil)
            }

            guard let httpResponse = response as? HTTPURLResponse else {
                hedgeLog("Error parsing the remote config response: unexpected response type")
                return completion(nil, nil)
            }

            if !(200 ... 299 ~= httpResponse.statusCode) {
                let jsonBody = fromJSONData(data, options: .allowFragments)
                let errorMessage = "Error calling the remote config API: status: \(httpResponse.statusCode), body: \(String(describing: jsonBody))."
                hedgeLog(errorMessage)

                return completion(nil,
                                  InternalPostHogError(description: errorMessage))
            } else {
                hedgeLog("Remote config called successfully.")
            }

            do {
                let jsonData = try JSONSerialization.jsonObject(with: data, options: .allowFragments) as? [String: Any]
                completion(jsonData, nil)
            } catch {
                hedgeLog("Error parsing the remote config response: \(error)")
                completion(nil, error)
            }
        }

        task.resume()
    }
}

extension PostHogApi {
    static var jsonDecoder: JSONDecoder = {
        let decoder = JSONDecoder()

        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let dateString = try container.decode(String.self)
            guard let date = apiDateFormatter.date(from: dateString) else {
                throw DecodingError.dataCorruptedError(
                    in: container, debugDescription: "Invalid date format"
                )
            }
            return date
        }
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }()
}

/// Session delegate that decides every redirect.
///
/// Capture V1 requests follow only a 307 or 308 to the origin of `config.host`, at most
/// `maxCaptureV1Redirects` times, with the original headers re-set. URLSession would otherwise
/// drop `Authorization`, resend the batch to another host, or turn a 302 into a body-less GET.
/// Any other redirect is not followed, so its 3xx is the response. Other requests follow
/// redirects but lose the custom headers when they leave the configured host.
final class PostHogRedirectHandler: NSObject, URLSessionTaskDelegate {
    static let maxCaptureV1Redirects = 5

    private let host: URL
    private let headerKeys: [String]
    private let lock = NSLock()
    // Redirects followed per capture task. Weak keys drop finished tasks.
    private let captureV1Hops = NSMapTable<URLSessionTask, NSNumber>.weakToStrongObjects()

    init(host: URL, headerKeys: [String]) {
        self.host = host
        self.headerKeys = headerKeys
    }

    func urlSession(
        _: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        if let original = task.originalRequest, Self.isCaptureV1(original) {
            let hop = lock.withLock { () -> Int in
                let hop = (captureV1Hops.object(forKey: task)?.intValue ?? 0) + 1
                captureV1Hops.setObject(NSNumber(value: hop), forKey: task)
                return hop
            }
            completionHandler(Self.captureV1Redirect(
                original: original, statusCode: response.statusCode, newRequest: request, host: host, hop: hop
            ))
            return
        }

        guard request.url?.host != host.host else {
            completionHandler(request)
            return
        }
        var redirected = request
        for key in headerKeys {
            redirected.setValue(nil, forHTTPHeaderField: key)
        }
        completionHandler(redirected)
    }

    /// Capture V1 requests are the only ones that carry `PostHog-Request-Id`,
    /// which custom headers can't set.
    static func isCaptureV1(_ request: URLRequest) -> Bool {
        request.value(forHTTPHeaderField: "PostHog-Request-Id") != nil
    }

    /// The request to follow for the `hop`th redirect of a capture V1 request, or `nil` to stop
    /// and return the 3xx.
    static func captureV1Redirect(
        original: URLRequest,
        statusCode: Int,
        newRequest: URLRequest,
        host: URL,
        hop: Int
    ) -> URLRequest? {
        guard [307, 308].contains(statusCode),
              hop <= maxCaptureV1Redirects,
              let target = newRequest.url,
              let targetOrigin = origin(target),
              targetOrigin == origin(host)
        else {
            hedgeLog("Capture did not follow a \(statusCode) redirect.")
            return nil
        }
        var redirected = newRequest
        redirected.httpMethod = original.httpMethod
        // Same origin, so every original header is safe to resend.
        for (key, value) in original.allHTTPHeaderFields ?? [:] {
            redirected.setValue(value, forHTTPHeaderField: key)
        }
        return redirected
    }

    private static func origin(_ url: URL) -> String? {
        guard let scheme = url.scheme?.lowercased(), let host = url.host?.lowercased() else { return nil }
        let port = url.port ?? (scheme == "https" ? 443 : 80)
        return "\(scheme)://\(host):\(port)"
    }
}

/// Identity of a capture V1 request, kept so a retry of the same events reuses
/// `PostHog-Request-Id` and `created_at` with an incremented `PostHog-Attempt`.
private struct CaptureV1RequestIdentity {
    let uuids: Set<String>
    let requestId: String
    let attempt: Int
    let createdAt: String
}
