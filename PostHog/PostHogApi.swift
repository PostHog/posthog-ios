//
//  PostHogApi.swift
//  PostHog
//
//  Created by Ben White on 06.02.23.
//

import Foundation

class PostHogApi {
    private let config: PostHogConfig

    // default is 60s but we do 10s
    private let defaultTimeout: TimeInterval = 10

    /// One `URLSession` instance shared by every request the SDK makes.
    /// Per-request `URLSession` is an anti-pattern — Apple's guidance (WWDC 2018
    /// session 714) is to reuse a single session so the connection pool stays
    /// warm, TLS handshakes amortise across requests, and HTTP/2 multiplexing
    /// can carry concurrent flushes (events / replay / logs / flags) over one
    /// TCP connection.
    private let session: URLSession

    init(_ config: PostHogConfig) {
        self.config = config

        let sessionConfig = config.urlSessionConfiguration ?? URLSessionConfiguration.default
        // Sends a conditional request (If-Modified-Since/If-None-Match) to the
        // server. Used by /array/<token>/config so we don't operate with stale
        // config or flags.
        sessionConfig.requestCachePolicy = .reloadRevalidatingCacheData
        sessionConfig.httpAdditionalHeaders = [
            "Content-Type": "application/json; charset=utf-8",
            "User-Agent": "\(postHogSdkName)/\(postHogVersion)",
            "Accept-Encoding": "gzip",
        ]
        session = URLSession(configuration: sessionConfig)
    }

    /// Builds a POST `URLRequest`. Pass `gzipped: true` for upload endpoints
    /// (/batch, /s/, /i/v1/logs) that send gzipped bodies — the
    /// `Content-Encoding: gzip` header tells the server to decompress.
    private func getURLRequest(_ url: URL, gzipped: Bool = false) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = defaultTimeout
        if gzipped {
            request.setValue("gzip", forHTTPHeaderField: "Content-Encoding")
        }
        return request
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

        let request = getURLRequest(url, gzipped: true)

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

        let gzippedPayload: Data
        do {
            gzippedPayload = try data.gzipped()
        } catch {
            hedgeLog("Error gzipping the batch body: \(error).")
            return completion(PostHogUploadInfo(statusCode: nil, error: error))
        }

        session.uploadTask(with: request, from: gzippedPayload) { data, response, error in
            if error != nil {
                hedgeLog("Error calling the batch API: \(String(describing: error)).")
                return completion(PostHogUploadInfo(statusCode: nil, error: error))
            }

            let httpResponse = response as! HTTPURLResponse

            if !(200 ... 299 ~= httpResponse.statusCode) {
                let jsonBody = data.flatMap { fromJSONData($0, options: .allowFragments) }
                let errorMessage = "Error sending events to batch API: status: \(httpResponse.statusCode), body: \(String(describing: jsonBody))."
                hedgeLog(errorMessage)
            } else {
                hedgeLog("Events sent successfully.")
            }

            return completion(PostHogUploadInfo(statusCode: httpResponse.statusCode, error: error))
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

        let request = getURLRequest(url, gzipped: true)

        let toSend = events.map { $0.toJSON() }

        guard let data = try? JSONSerialization.data(withJSONObject: toSend) else {
            hedgeLog("Error parsing the snapshot body")
            return completion(PostHogUploadInfo(statusCode: nil, error: nil))
        }

        let gzippedPayload: Data
        do {
            gzippedPayload = try data.gzipped()
        } catch {
            hedgeLog("Error gzipping the snapshot body: \(error).")
            return completion(PostHogUploadInfo(statusCode: nil, error: error))
        }

        session.uploadTask(with: request, from: gzippedPayload) { data, response, error in
            if error != nil {
                hedgeLog("Error calling the snapshot API: \(String(describing: error)).")
                return completion(PostHogUploadInfo(statusCode: nil, error: error))
            }

            let httpResponse = response as! HTTPURLResponse

            if !(200 ... 299 ~= httpResponse.statusCode) {
                let jsonBody = data.flatMap { fromJSONData($0, options: .allowFragments) }
                let errorMessage = "Error sending events to snapshot API: status: \(httpResponse.statusCode), body: \(String(describing: jsonBody))."
                hedgeLog(errorMessage)
            } else {
                hedgeLog("Snapshots sent successfully.")
            }

            return completion(PostHogUploadInfo(statusCode: httpResponse.statusCode, error: error))
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

        let request = getURLRequest(url, gzipped: true)

        guard let data = try? JSONSerialization.data(withJSONObject: payload) else {
            hedgeLog("Error parsing the logs body")
            return completion(PostHogUploadInfo(statusCode: nil, error: nil))
        }

        let gzippedPayload: Data
        do {
            gzippedPayload = try data.gzipped()
        } catch {
            hedgeLog("Error gzipping the logs body: \(error).")
            return completion(PostHogUploadInfo(statusCode: nil, error: error))
        }

        session.uploadTask(with: request, from: gzippedPayload) { data, response, error in
            if let error {
                hedgeLog("Error calling the logs API: \(error).")
                return completion(PostHogUploadInfo(statusCode: nil, error: error))
            }

            // Defensive guard: a nil error should normally come with a non-nil HTTP response,
            // but we never want a missing response to crash inside a customer process.
            guard let httpResponse = response as? HTTPURLResponse else {
                hedgeLog("Logs API returned no HTTP response")
                return completion(PostHogUploadInfo(statusCode: nil, error: nil))
            }

            if !(200 ... 299 ~= httpResponse.statusCode) {
                let jsonBody = data.flatMap { fromJSONData($0, options: .allowFragments) }
                hedgeLog("Error sending logs to /i/v1/logs: status: \(httpResponse.statusCode), body: \(String(describing: jsonBody)).")
            } else {
                hedgeLog("Logs sent successfully.")
            }

            return completion(PostHogUploadInfo(statusCode: httpResponse.statusCode, error: nil))
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

        session.uploadTask(with: request, from: data) { data, response, error in
            if error != nil {
                hedgeLog("Error calling the flags API: \(String(describing: error))")
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
