//
//  PostHogApi.swift
//  PostHog
//
//  Created by Ben White on 06.02.23.
//

import Foundation

/// Common URLSession upload-response handler shared by `/batch`, `/snapshot`,
/// and `/i/v1/logs`. Routes through `as?` so a missing HTTP response can't
/// crash inside a customer process.
private func processUploadResponse(
    endpointName: String,
    data: Data?,
    response: URLResponse?,
    error: Error?,
    completion: @escaping (PostHogUploadInfo) -> Void
) {
    if let error {
        hedgeLog("Error calling the \(endpointName) API: \(error).")
        return completion(PostHogUploadInfo(statusCode: nil, error: error))
    }

    guard let httpResponse = response as? HTTPURLResponse else {
        hedgeLog("\(endpointName) API returned no HTTP response")
        return completion(PostHogUploadInfo(statusCode: nil, error: nil))
    }

    if !(200 ... 299 ~= httpResponse.statusCode) {
        let jsonBody = data.flatMap { fromJSONData($0, options: .allowFragments) }
        hedgeLog("Error sending to \(endpointName) API: status: \(httpResponse.statusCode), body: \(String(describing: jsonBody)).")
    } else {
        hedgeLog("\(endpointName) sent successfully.")
    }

    let retryAfter = httpResponse.value(forHTTPHeaderField: "Retry-After").flatMap(parseRetryAfter)
    completion(PostHogUploadInfo(statusCode: httpResponse.statusCode, error: nil, retryAfter: retryAfter))
}

private func parseRetryAfter(_ value: String) -> TimeInterval? {
    if let seconds = TimeInterval(value), seconds >= 0 {
        return seconds
    }

    if let date = HTTPDateFormatter.shared.date(from: value) {
        return max(0, date.timeIntervalSinceNow)
    }

    return nil
}

private enum HTTPDateFormatter {
    static let shared: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "EEE',' dd MMM yyyy HH':'mm':'ss z"
        return formatter
    }()
}

class PostHogApi {
    static var gzipData: (Data) throws -> Data = { try $0.gzipped() }

    private let config: PostHogConfig

    // default is 60s but we do 10s
    private let defaultTimeout: TimeInterval = 10

    /// Shared so connection pool, TLS state, and HTTP/2 streams survive
    /// between calls instead of being torn down per request.
    private let session: URLSession

    static let flagsRetryDelay: TimeInterval = 0.3

    init(_ config: PostHogConfig) {
        self.config = config

        // Copy first so SDK mutations don't leak back to the caller's object.
        let sessionConfig = (config.urlSessionConfiguration?.copy() as? URLSessionConfiguration)
            ?? URLSessionConfiguration.default
        // Conditional request (If-Modified-Since/If-None-Match): server returns
        // 304 → cache hit, otherwise fresh body. Needed for /array/<token>/config
        // so we don't operate on stale config or flags.
        sessionConfig.requestCachePolicy = .reloadRevalidatingCacheData
        // Merge over caller-supplied headers; SDK keys overwrite collisions.
        var headers = sessionConfig.httpAdditionalHeaders ?? [:]
        headers["Content-Type"] = "application/json; charset=utf-8"
        headers["User-Agent"] = "\(postHogSdkName)/\(postHogVersion)"
        headers["Accept-Encoding"] = "gzip"
        sessionConfig.httpAdditionalHeaders = headers
        session = URLSession(configuration: sessionConfig)
    }

    /// `gzipped: true` adds `Content-Encoding: gzip` for upload endpoints
    /// (/batch, /s/, /i/v1/logs) whose bodies are gzipped.
    private func getURLRequest(_ url: URL, gzipped: Bool = false) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = defaultTimeout
        if gzipped {
            request.setValue("gzip", forHTTPHeaderField: "Content-Encoding")
        }
        return request
    }

    private func requestAndPayload(url: URL, data: Data, endpointName: String) -> (URLRequest, Data) {
        do {
            return (getURLRequest(url, gzipped: true), try Self.gzipData(data))
        } catch {
            hedgeLog("Error gzipping the \(endpointName) body, sending it uncompressed: \(error).")
            return (getURLRequest(url), data)
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
        return request
    }

    func batch(events: [PostHogEvent], completion: @escaping (PostHogUploadInfo) -> Void) {
        guard let url = getEndpointURL("/batch", relativeTo: config.host) else {
            hedgeLog("Malformed batch URL error.")
            return completion(PostHogUploadInfo(statusCode: nil, error: nil))
        }

        let toSend: [String: Any] = [
            // Wire field name remains api_key, but it carries the PostHog project token.
            "api_key": config.projectToken,
            "batch": events.map { $0.toJSON() },
            "sent_at": toISO8601String(Date()),
        ]

        guard let data = try? JSONSerialization.data(withJSONObject: toSend) else {
            hedgeLog("Error parsing the batch body")
            return completion(PostHogUploadInfo(statusCode: nil, error: nil))
        }

        let (request, payload) = requestAndPayload(url: url, data: data, endpointName: "batch")

        session.uploadTask(with: request, from: payload) { data, response, error in
            processUploadResponse(endpointName: "batch", data: data, response: response, error: error, completion: completion)
        }.resume()
    }

    func snapshot(events: [PostHogEvent], completion: @escaping (PostHogUploadInfo) -> Void) {
        guard let url = getEndpointURL(config.snapshotEndpoint, relativeTo: config.host) else {
            hedgeLog("Malformed snapshot URL error.")
            return completion(PostHogUploadInfo(statusCode: nil, error: nil))
        }

        for event in events {
            event.apiKey = config.projectToken
        }

        let toSend = events.map { $0.toJSON() }

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
                    let nextRetryCount = retryCount + 1
                    let delay = Self.featureFlagsRetryDelay(forFailedAttempt: nextRetryCount)
                    hedgeLog(
                        "Error calling the flags API: \(error). Retrying in \(delay) seconds (attempt \(nextRetryCount)/\(self.config.featureFlagRequestMaxRetries))."
                    )
                    DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + delay) {
                        self.uploadFlagsRequest(request, payload: payload, retryCount: nextRetryCount, completion: completion)
                    }
                    return
                }

                hedgeLog("Error calling the flags API: \(error)")
                return completion(nil, error)
            }

            guard let data else {
                hedgeLog("Error parsing the flags response: no data")
                return completion(nil, nil)
            }

            let httpResponse = response as! HTTPURLResponse

            if !(200 ... 299 ~= httpResponse.statusCode) {
                let jsonBody = fromJSONData(data, options: .allowFragments)
                let errorMessage = "Error calling flags API: status: \(httpResponse.statusCode), body: \(String(describing: jsonBody))."
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

            let httpResponse = response as! HTTPURLResponse

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
