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

    init(_ config: PostHogConfig) {
        self.config = config
    }

    func sessionConfig() -> URLSessionConfiguration {
        let config = URLSessionConfiguration.default

        config.httpAdditionalHeaders = [
            "Content-Type": "application/json; charset=utf-8",
            "User-Agent": "\(postHogSdkName)/\(postHogVersion)",
        ]

        return config
    }

    private func getURLRequest(_ url: URL) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = defaultTimeout
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

    func batch(events: [PostHogEvent], completion: @escaping (PostHogBatchUploadInfo) -> Void) {
        guard let url = getEndpointURL("/batch", relativeTo: config.host) else {
            hedgeLog("Malformed batch URL error.")
            return completion(PostHogBatchUploadInfo(statusCode: nil, error: nil))
        }

        let config = sessionConfig()
        var headers = config.httpAdditionalHeaders ?? [:]
        headers["Accept-Encoding"] = "gzip"
        headers["Content-Encoding"] = "gzip"
        config.httpAdditionalHeaders = headers

        let request = getURLRequest(url)

        let toSend: [String: Any] = [
            "api_key": self.config.apiKey,
            "batch": events.map { $0.toJSON() },
            "sent_at": toISO8601String(Date()),
        ]

        var data: Data?

        do {
            data = try JSONSerialization.data(withJSONObject: toSend)
        } catch {
            hedgeLog("Error parsing the batch body: \(error)")
            return completion(PostHogBatchUploadInfo(statusCode: nil, error: error))
        }

        var gzippedPayload: Data?
        do {
            gzippedPayload = try data!.gzipped()
        } catch {
            hedgeLog("Error gzipping the batch body: \(error).")
            return completion(PostHogBatchUploadInfo(statusCode: nil, error: error))
        }

        URLSession(configuration: config).uploadTask(with: request, from: gzippedPayload!) { data, response, error in
            if error != nil {
                hedgeLog("Error calling the batch API: \(String(describing: error)).")
                return completion(PostHogBatchUploadInfo(statusCode: nil, error: error))
            }

            let httpResponse = response as! HTTPURLResponse

            if !(200 ... 299 ~= httpResponse.statusCode) {
                let jsonBody = String(describing: try? JSONSerialization.jsonObject(with: data!, options: .allowFragments) as? [String: Any])
                let errorMessage = "Error sending events to batch API: status: \(jsonBody)."
                hedgeLog(errorMessage)
            } else {
                hedgeLog("Events sent successfully.")
            }

            return completion(PostHogBatchUploadInfo(statusCode: httpResponse.statusCode, error: error))
        }.resume()
    }

    func snapshot(events: [PostHogEvent], completion: @escaping (PostHogBatchUploadInfo) -> Void) {
        guard let url = getEndpointURL(config.snapshotEndpoint, relativeTo: config.host) else {
            hedgeLog("Malformed snapshot URL error.")
            return completion(PostHogBatchUploadInfo(statusCode: nil, error: nil))
        }

        for event in events {
            event.apiKey = self.config.apiKey
        }

        let config = sessionConfig()
        var headers = config.httpAdditionalHeaders ?? [:]
        headers["Accept-Encoding"] = "gzip"
        headers["Content-Encoding"] = "gzip"
        config.httpAdditionalHeaders = headers

        let request = getURLRequest(url)

        let toSend = events.map { $0.toJSON() }

        var data: Data?

        do {
            data = try JSONSerialization.data(withJSONObject: toSend)
//            remove it only for debugging
//            if let newData = data {
//                let convertedString = String(data: newData, encoding: .utf8)
//                hedgeLog("snapshot body: \(convertedString ?? "")")
//            }
        } catch {
            hedgeLog("Error parsing the snapshot body: \(error)")
            return completion(PostHogBatchUploadInfo(statusCode: nil, error: error))
        }

        var gzippedPayload: Data?
        do {
            gzippedPayload = try data!.gzipped()
        } catch {
            hedgeLog("Error gzipping the snapshot body: \(error).")
            return completion(PostHogBatchUploadInfo(statusCode: nil, error: error))
        }

        URLSession(configuration: config).uploadTask(with: request, from: gzippedPayload!) { data, response, error in
            if error != nil {
                hedgeLog("Error calling the snapshot API: \(String(describing: error)).")
                return completion(PostHogBatchUploadInfo(statusCode: nil, error: error))
            }

            let httpResponse = response as! HTTPURLResponse

            if !(200 ... 299 ~= httpResponse.statusCode) {
                let jsonBody = String(describing: try? JSONSerialization.jsonObject(with: data!, options: .allowFragments) as? [String: Any])
                let errorMessage = "Error sending events to snapshot API: status: \(httpResponse.statusCode), body: \(jsonBody)."
                hedgeLog(errorMessage)
            } else {
                hedgeLog("Snapshots sent successfully.")
            }

            return completion(PostHogBatchUploadInfo(statusCode: httpResponse.statusCode, error: error))
        }.resume()
    }

    func decide(
        distinctId: String,
        anonymousId: String,
        groups: [String: String],
        completion: @escaping ([String: Any]?, _ error: Error?) -> Void
    ) {
        guard let url = getEndpointURL(
            "/decide",
            queryItems: URLQueryItem(name: "v", value: "3"),
            relativeTo: config.host
        ) else {
            hedgeLog("Malformed decide URL error.")
            return completion(nil, nil)
        }

        let config = sessionConfig()

        let request = getURLRequest(url)

        let toSend: [String: Any] = [
            "api_key": self.config.apiKey,
            "distinct_id": distinctId,
            "$anon_distinct_id": anonymousId,
            "$groups": groups,
        ]

        var data: Data?

        do {
            data = try JSONSerialization.data(withJSONObject: toSend)
        } catch {
            hedgeLog("Error parsing the decide body: \(error)")
            return completion(nil, error)
        }

        URLSession(configuration: config).uploadTask(with: request, from: data!) { data, response, error in
            if error != nil {
                hedgeLog("Error calling the decide API: \(String(describing: error))")
                return completion(nil, error)
            }

            let httpResponse = response as! HTTPURLResponse

            if !(200 ... 299 ~= httpResponse.statusCode) {
                let jsonBody = String(describing: try? JSONSerialization.jsonObject(with: data!, options: .allowFragments) as? [String: Any])
                let errorMessage = "Error calling decide API: status: \(httpResponse.statusCode), body: \(jsonBody)."
                hedgeLog(errorMessage)

                return completion(nil,
                                  InternalPostHogError(description: errorMessage))
            } else {
                hedgeLog("Decide called successfully.")
            }

            do {
                let jsonData = try JSONSerialization.jsonObject(with: data!, options: .allowFragments) as? [String: Any]
                completion(jsonData, nil)
            } catch {
                hedgeLog("Error parsing the decide response: \(error)")
                completion(nil, error)
            }
        }.resume()
    }
}
