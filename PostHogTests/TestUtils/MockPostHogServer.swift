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

    init(port _: Int = 9001) {
        stub(condition: isPath("/decide")) { _ in
            let obj: [String: Any] = [
                "featureFlags": [
                    "bool-value": true,
                    "string-value": "test",
                ],
                "featureFlagPayloads": [
                    "payload-bool": "true",
                    "payload-number": "2",
                    "payload-string": "\"string-value\"",
                    "payload-json": "{ \"foo\": \"bar\" }",
                ],
            ]

            return HTTPStubsResponse(jsonObject: obj, statusCode: 200, headers: nil)
        }

        stub(condition: isPath("/batch")) { _ in
            HTTPStubsResponse(jsonObject: ["status": "ok"], statusCode: 200, headers: nil)
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

    var posthogConfig: PostHogConfig {
        let config = PostHogConfig(apiKey: "test-123", host: "http://localhost:9001")

        return config
    }

    func parseBatchRequest(_ context: URLRequest) -> [String: Any]? {
        let data = NSData(data: context.body()!)
        let unzippedData = data.posthog_gunzipped()

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
