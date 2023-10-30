//
//  MockPostHogServer.swift
//  PostHogTests
//
//  Created by Ben White on 21.03.23.
//

import Foundation
import XCTest

import OHHTTPStubs
import OHHTTPStubsSwift

@testable import PostHog

class MockPostHogServer {
    var requests = [URLRequest]()
    var expectation: XCTestExpectation?
    var expectationCount: Int?

    func trackRequest(_ request: URLRequest) {
        requests.append(request)

        if requests.count >= (expectationCount ?? 0) {
            expectation?.fulfill()
        }
    }

    public var errorsWhileComputingFlags = false
    public var return500 = false

    init(port _: Int = 9001) {
        stub(condition: isPath("/decide")) { _ in
            var flags = [
                "bool-value": true,
                "string-value": "test",
                "disabled-flag": false,
                "number-value": true,
            ]

            if self.errorsWhileComputingFlags {
                flags["new-flag"] = true
                flags.removeValue(forKey: "bool-value")
            }

            let obj: [String: Any] = [
                "featureFlags": flags,
                "featureFlagPayloads": [
                    "payload-bool": "true",
                    "number-value": "2",
                    "payload-string": "\"string-value\"",
                    "payload-json": "{ \"foo\": \"bar\" }",
                ],
                "errorsWhileComputingFlags": self.errorsWhileComputingFlags,
            ]

            return HTTPStubsResponse(jsonObject: obj, statusCode: 200, headers: nil)
        }

        stub(condition: isPath("/batch")) { _ in
            if self.return500 {
                HTTPStubsResponse(jsonObject: [], statusCode: 500, headers: nil)
            } else {
                HTTPStubsResponse(jsonObject: ["status": "ok"], statusCode: 200, headers: nil)
            }
        }

        HTTPStubs.onStubActivation { request, _, _ in
            if request.url?.path == "/batch" {
                self.trackRequest(request)
            }
        }
    }

    func start() {
        HTTPStubs.setEnabled(true)
    }

    func stop() {
        requests = []
        HTTPStubs.removeAllStubs()
    }

    func expectation(_ requestCount: Int) -> XCTestExpectation {
        expectation = XCTestExpectation(description: "\(requestCount) requests to occur")
        expectationCount = requestCount

        return expectation!
    }

    func getPosthogConfig(preloadFeatureFlags: Bool = false) -> PostHogConfig {
        let config = PostHogConfig(apiKey: "test-123", host: "http://localhost:9001")
        config.flushAt = 1
        config.preloadFeatureFlags = preloadFeatureFlags

        return config
    }

    func parseBatchRequest(_ context: URLRequest) -> [String: Any]? {
        var unzippedData: Data?
        do {
            unzippedData = try context.body()!.gunzipped()
        } catch {
            // its ok
        }

        return try? JSONSerialization.jsonObject(with: unzippedData!, options: []) as? [String: Any]
    }

    func parsePostHogEvents(_ context: URLRequest) -> [PostHogEvent] {
        let data = parseBatchRequest(context)
        guard let batchEvents = data?["batch"] as? [[String: Any]] else {
            return []
        }

        var events = [PostHogEvent]()

        for event in batchEvents {
            guard let posthogEvent = PostHogEvent.fromJSON(event) else { continue }
            events.append(posthogEvent)
        }

        return events
    }
}
