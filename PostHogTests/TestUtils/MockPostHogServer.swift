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
    var batchRequests = [URLRequest]()
    var batchExpectation: XCTestExpectation?
    var decideExpectation: XCTestExpectation?
    var batchExpectationCount: Int?
    var decideRequests = [URLRequest]()

    func trackBatchRequest(_ request: URLRequest) {
        batchRequests.append(request)

        if batchRequests.count >= (batchExpectationCount ?? 0) {
            batchExpectation?.fulfill()
        }
    }

    func trackDecide(_ request: URLRequest) {
        decideRequests.append(request)

        decideExpectation?.fulfill()
    }

    public var errorsWhileComputingFlags = false
    public var return500 = false
    public var returnReplay = false
    public var returnReplayWithVariant = false
    public var returnReplayWithMultiVariant = false
    public var replayVariantName = "myBooleanRecordingFlag"
    public var replayVariantValue: Any = true
    public var quotaLimitFeatureFlags: Bool = false

    init() {
        stub(condition: pathEndsWith("/decide")) { _ in
            if self.quotaLimitFeatureFlags {
                return HTTPStubsResponse(
                    jsonObject: ["quotaLimited": ["feature_flags"]], 
                    statusCode: 200, 
                    headers: nil
                )
            }

            var flags = [
                "bool-value": true,
                "string-value": "test",
                "disabled-flag": false,
                "number-value": true,
                "recording-platform-check": "web",
                self.replayVariantName: self.replayVariantValue,
            ]

            if self.errorsWhileComputingFlags {
                flags["new-flag"] = true
                flags.removeValue(forKey: "bool-value")
            }

            var obj: [String: Any] = [
                "featureFlags": flags,
                "featureFlagPayloads": [
                    "payload-bool": "true",
                    "number-value": "2",
                    "payload-string": "\"string-value\"",
                    "payload-json": "{ \"foo\": \"bar\" }",
                ],
                "errorsWhileComputingFlags": self.errorsWhileComputingFlags,
            ]

            if self.returnReplay {
                var sessionRecording: [String: Any] = [
                    "endpoint": "/newS/",
                ]

                if self.returnReplayWithVariant {
                    if self.returnReplayWithMultiVariant {
                        sessionRecording["linkedFlag"] = self.replayVariantValue
                    } else {
                        sessionRecording["linkedFlag"] = self.replayVariantName
                    }
                }

                obj["sessionRecording"] = sessionRecording
            } else {
                obj["sessionRecording"] = false
            }

            return HTTPStubsResponse(jsonObject: obj, statusCode: 200, headers: nil)
        }

        stub(condition: pathEndsWith("/batch")) { _ in
            if self.return500 {
                HTTPStubsResponse(jsonObject: [], statusCode: 500, headers: nil)
            } else {
                HTTPStubsResponse(jsonObject: ["status": "ok"], statusCode: 200, headers: nil)
            }
        }

        stub(condition: pathEndsWith("/s")) { _ in
            if self.return500 {
                HTTPStubsResponse(jsonObject: [], statusCode: 500, headers: nil)
            } else {
                HTTPStubsResponse(jsonObject: ["status": "ok"], statusCode: 200, headers: nil)
            }
        }

        HTTPStubs.onStubActivation { request, _, _ in
            if request.url?.lastPathComponent == "batch" {
                self.trackBatchRequest(request)
            } else if request.url?.lastPathComponent == "decide" {
                self.trackDecide(request)
            }
        }
    }

    func start(batchCount: Int = 1) {
        reset(batchCount: batchCount)

        HTTPStubs.setEnabled(true)
    }

    func stop() {
        reset()

        HTTPStubs.removeAllStubs()
    }

    func reset(batchCount: Int = 1) {
        batchRequests = []
        decideRequests = []
        batchExpectation = XCTestExpectation(description: "\(batchCount) batch requests to occur")
        decideExpectation = XCTestExpectation(description: "1 decide requests to occur")
        batchExpectationCount = batchCount
        errorsWhileComputingFlags = false
        return500 = false
    }

    func parseRequest(_ context: URLRequest, gzip: Bool = true) -> [String: Any]? {
        var unzippedData: Data?
        do {
            if gzip {
                unzippedData = try context.body()!.gunzipped()
            } else {
                unzippedData = context.body()!
            }
        } catch {
            // its ok
        }

        return try? JSONSerialization.jsonObject(with: unzippedData!, options: []) as? [String: Any]
    }

    func parsePostHogEvents(_ context: URLRequest) -> [PostHogEvent] {
        let data = parseRequest(context)
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
