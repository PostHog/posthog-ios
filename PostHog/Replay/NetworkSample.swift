//
//  NetworkSample.swift
//  PostHog
//
//  Created by Manoel Aranda Neto on 26.03.24.
//

#if os(iOS)
    import Foundation

    struct NetworkSample {
        let sessionId: String
        let timeOrigin: Date
        let entryType = "resource"
        var name: String?
        var responseStatus: Int?
        var initiatorType = "fetch"
        var httpMethod: String?
        var duration: Int64?
        var decodedBodySize: Int64?

        init(sessionId: String, timeOrigin: Date, url: String? = nil) {
            self.timeOrigin = timeOrigin
            self.sessionId = sessionId
            name = url
        }

        func toDict() -> [String: Any] {
            var dict: [String: Any] = [
                "timestamp": timeOrigin.toMillis(),
                "entryType": entryType,
                "initiatorType": initiatorType,
            ]

            if let name = name {
                dict["name"] = name
            }

            if let responseStatus = responseStatus {
                dict["responseStatus"] = responseStatus
            }

            if let httpMethod = httpMethod {
                dict["method"] = httpMethod
            }

            if let duration = duration {
                dict["duration"] = duration
            }

            if let decodedBodySize = decodedBodySize {
                dict["transferSize"] = decodedBodySize
            }

            return dict
        }
    }
#endif
