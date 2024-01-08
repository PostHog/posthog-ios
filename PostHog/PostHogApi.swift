//
//  PostHogApi.swift
//  PostHog
//
//  Created by Ben White on 06.02.23.
//

import Foundation

class PostHogApi {
    private let config: PostHogConfig

    init(_ config: PostHogConfig) {
        self.config = config
    }

    func sessionConfig() -> URLSessionConfiguration {
        let config = URLSessionConfiguration.default

        config.httpAdditionalHeaders = [
            "Content-Type": "application/json; charset=utf-8",
            "User-Agent": "\(PostHogVersion.postHogSdkName)/\(PostHogVersion.postHogVersion)",
        ]

        return config
    }

    func batch(events: [PostHogEvent], completion: @escaping (PostHogBatchUploadInfo) -> Void) {
        guard let url = URL(string: "batch", relativeTo: config.host) else {
            return completion(PostHogBatchUploadInfo(statusCode: nil, error: nil))
        }

        let config = sessionConfig()
        var headers = config.httpAdditionalHeaders ?? [:]
        headers["Accept-Encoding"] = "gzip"
        headers["Content-Encoding"] = "gzip"
        config.httpAdditionalHeaders = headers

        var request = URLRequest(url: url)
        request.httpMethod = "POST"

        let toSend: [String: Any] = [
            "api_key": self.config.apiKey,
            "batch": events.map { $0.toJSON() },
            "sent_at": toISO8601String(Date()),
        ]

        var data: Data?

        do {
            data = try JSONSerialization.data(withJSONObject: toSend)
        } catch {
            return completion(PostHogBatchUploadInfo(statusCode: nil, error: error))
        }

        var gzippedPayload: Data?
        do {
            gzippedPayload = try data!.gzipped()
        } catch {
            return completion(PostHogBatchUploadInfo(statusCode: nil, error: error))
        }

        URLSession(configuration: config).uploadTask(with: request, from: gzippedPayload!) { data, response, error in
            if error != nil {
                return completion(PostHogBatchUploadInfo(statusCode: nil, error: error))
            }

            let httpResponse = response as! HTTPURLResponse

            if !(200 ... 299 ~= httpResponse.statusCode) {
                do {
                    try hedgeLog("Error sending events to PostHog: \(JSONSerialization.jsonObject(with: data!, options: .allowFragments) as? [String: Any])")
                } catch {
                    hedgeLog("Error sending events to PostHog")
                }
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
        var urlComps = URLComponents()
        urlComps.path = "/decide"
        urlComps.queryItems = [URLQueryItem(name: "v", value: "3")]

        guard let url = urlComps.url(relativeTo: config.host) else {
            return completion(nil, nil)
        }

        let config = sessionConfig()

        var request = URLRequest(url: url)
        request.httpMethod = "POST"

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
            return completion(nil, error)
        }

        URLSession(configuration: config).uploadTask(with: request, from: data!) { data, response, error in
            if error != nil {
                return completion(nil, error)
            }

            let httpResponse = response as! HTTPURLResponse

            if !(200 ... 299 ~= httpResponse.statusCode) {
                return completion(nil,
                                  InternalPostHogError(description: "/decide returned a non 2xx status: \(httpResponse.statusCode)"))
            }

            do {
                let jsonData = try JSONSerialization.jsonObject(with: data!, options: .allowFragments) as? [String: Any]
                completion(jsonData, nil)
            } catch {
                completion(nil, error)
            }
        }.resume()
    }
}
