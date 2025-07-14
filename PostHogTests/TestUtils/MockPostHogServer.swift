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
    var flagsExpectation: XCTestExpectation?
    var batchExpectationCount: Int?
    var flagsRequests = [URLRequest]()
    var version: Int = 3

    func trackBatchRequest(_ request: URLRequest) {
        batchRequests.append(request)

        if batchRequests.count >= (batchExpectationCount ?? 0) {
            batchExpectation?.fulfill()
        }
    }

    func trackFlags(_ request: URLRequest) {
        flagsRequests.append(request)

        flagsExpectation?.fulfill()
    }

    public var errorsWhileComputingFlags = false
    public var return500 = false
    public var returnReplay = false
    public var returnReplayWithVariant = false
    public var returnReplayWithMultiVariant = false
    public var replayVariantName = "myBooleanRecordingFlag"
    public var flagsSkipReplayVariantName = false
    public var replayVariantValue: Any = true
    public var quotaLimitFeatureFlags: Bool = false
    public var remoteConfigSurveys: String?
    public var hasFeatureFlags: Bool? = true
    public var featureFlags: [String: Any]?

    // version is the version of the response we want to return regardless of the request version
    init(version: Int = 3) {
        self.version = version

        stub(condition: pathEndsWith("/flags")) { _ in
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
                "payload-json": true,
            ]

            if let additionalFlags = self.featureFlags {
                flags.merge(additionalFlags, uniquingKeysWith: { _, new in new })
            }

            if !self.flagsSkipReplayVariantName {
                flags[self.replayVariantName] = self.replayVariantValue
            }

            var flagsV4 = [
                "bool-value": [
                    "key": "bool-value",
                    "enabled": true,
                    "variant": nil,
                    "reason": [
                        "type": "condition_match",
                        "description": "Matched condition set 3",
                        "condition_index": 2,
                    ],
                    "metadata": [
                        "id": 2,
                        "version": 23,
                        "payload": "true",
                        "description": "This is an enabled flag",
                    ],
                ],
                "string-value": [
                    "key": "string-value",
                    "enabled": true,
                    "variant": "test",
                    "reason": [
                        "type": "condition_match",
                        "description": "Matched condition set 1",
                        "condition_index": 0,
                    ],
                    "metadata": [
                        "id": 3,
                        "version": 1,
                        "payload": "\"string-value\"",
                        "description": "",
                    ],
                ],
                "disabled-flag": [
                    "key": "disabled-flag",
                    "enabled": false,
                    "variant": nil,
                    "reason": [
                        "type": "no_condition_match",
                        "description": "No matching condition set",
                        "condition_index": nil,
                    ],
                    "metadata": [
                        "id": 4,
                        "version": 1,
                        "payload": nil,
                        "description": "This is a disabled flag",
                    ],
                ],
                "number-value": [
                    "key": "number-value",
                    "enabled": true,
                    "variant": nil,
                    "reason": [
                        "type": "condition_match",
                        "description": "Matched condition set 2",
                        "condition_index": 1,
                    ],
                    "metadata": [
                        "id": 5,
                        "version": 14,
                        "payload": "2",
                        "description": "This is a number flag",
                    ],
                ],
                "recording-platform-check": [
                    "key": "recording-platform-check",
                    "enabled": true,
                    "variant": "web",
                    "reason": [
                        "type": "condition_match",
                        "description": "Matched condition set 4",
                        "condition_index": 3,
                    ],
                    "metadata": [
                        "id": 6,
                        "version": 1,
                        "payload": nil,
                        "description": "This is a recording platform check flag",
                    ],
                ],
                "payload-json": [
                    "key": "payload-json",
                    "enabled": true,
                    "variant": nil,
                    "reason": [
                        "type": "condition_match",
                        "description": "Matched condition set 5",
                        "condition_index": 4,
                    ],
                    "metadata": [
                        "id": 7,
                        "version": 1,
                        "payload": "{ \"foo\": \"bar\" }",
                        "description": "This is a payload json flag",
                    ],
                ],
            ]

            if self.errorsWhileComputingFlags {
                flags["new-flag"] = true
                flags.removeValue(forKey: "bool-value")

                flagsV4["new-flag"] = [
                    "key": "new-flag",
                    "enabled": true,
                    "variant": nil,
                    "reason": [
                        "type": "condition_match",
                        "description": "Matched condition set 6",
                        "condition_index": 5,
                    ],
                    "metadata": [
                        "id": 8,
                        "version": 1,
                        "payload": nil,
                        "description": "This is a new flag",
                    ],
                ]
                flagsV4.removeValue(forKey: "bool-value")
            }

            var obj: [String: Any] = [:]

            if self.version == 4 {
                obj = [
                    "flags": flagsV4,
                    "errorsWhileComputingFlags": self.errorsWhileComputingFlags,
                    "requestId": "0f801b5b-0776-42ca-b0f7-8375c95730bf",
                ]
            } else {
                obj = [
                    "featureFlags": flags,
                    "featureFlagPayloads": [
                        "bool-value": "true",
                        "number-value": "2",
                        "string-value": "\"string-value\"",
                        "payload-json": "{ \"foo\": \"bar\" }",
                    ],
                    "errorsWhileComputingFlags": self.errorsWhileComputingFlags,
                    "requestId": "0f801b5b-0776-42ca-b0f7-8375c95730bf",
                ]
            }

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

        stub(condition: pathEndsWith("/config")) { _ in
            if self.return500 {
                return HTTPStubsResponse(jsonObject: [], statusCode: 500, headers: nil)
            }

            // conditionally include hasFeatureFlags key
            let hasFeatureFlagsPayload: String = {
                if let hasFeatureFlags = self.hasFeatureFlags {
                    return "\"hasFeatureFlags\": \(hasFeatureFlags),"
                }
                return ""
            }()

            let configData =
                """
                {
                    "token": "test_api_key",
                    "supportedCompression": [
                        "gzip",
                        "gzip-js"
                    ],
                    \(hasFeatureFlagsPayload)
                    "captureDeadClicks": true,
                    "capturePerformance": {
                        "network_timing": true,
                        "web_vitals": true,
                        "web_vitals_allowed_metrics": null
                    },
                    "autocapture_opt_out": false,
                    "autocaptureExceptions": {
                        "endpoint": "/e/"
                    },
                    "analytics": {
                        "endpoint": "/i/v0/e/"
                    },
                    "elementsChainAsString": true,
                    "sessionRecording": false,
                    "heatmaps": true,
                    "surveys": \(self.remoteConfigSurveys ?? "false"),
                    "defaultIdentifiedOnly": true,
                    "siteApps": []
                }
                """.data(using: .utf8)!

            return HTTPStubsResponse(data: configData, statusCode: 200, headers: nil)
        }

        HTTPStubs.onStubActivation { request, _, _ in
            if request.url?.lastPathComponent == "batch" {
                self.trackBatchRequest(request)
            } else if request.url?.lastPathComponent == "flags" {
                self.trackFlags(request)
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
        flagsRequests = []
        batchExpectation = XCTestExpectation(description: "\(batchCount) batch requests to occur")
        flagsExpectation = XCTestExpectation(description: "1 flag requests to occur")
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
