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

            dict["name"] = name

            dict["responseStatus"] = responseStatus

            dict["method"] = httpMethod

            dict["duration"] = duration

            dict["transferSize"] = decodedBodySize

            return dict
        }
    }
#endif
