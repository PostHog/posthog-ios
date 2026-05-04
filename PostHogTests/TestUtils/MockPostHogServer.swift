//
//  MockPostHogServer.swift
//  PostHogTests
//
//  Created by Ben White on 21.03.23.
//

import Foundation
import OHHTTPStubs
import OHHTTPStubsSwift
@testable import PostHog
import XCTest

class MockPostHogServer {
    var batchRequests = [URLRequest]()
    var snapshotRequests = [URLRequest]()
    var logsRequests = [URLRequest]()
    var batchExpectation: XCTestExpectation?
    var snapshotExpectation: XCTestExpectation?
    var logsExpectation: XCTestExpectation?
    var flagsExpectation: XCTestExpectation?
    var batchExpectationCount: Int?
    var snapshotExpectationCount: Int?
    var logsExpectationCount: Int?
    var flagsExpectationCount: Int?
    var flagsRequests = [URLRequest]()
    private var stubDescriptors = [HTTPStubsDescriptor]()
    var flagsResponseDelay: TimeInterval = 0
    var flagsResponseHandler: ((URLRequest) -> HTTPStubsResponse)?
    /// If set, the closure is invoked for each `/i/v1/logs` request (with the
    /// 1-based request number) and returns the stub response. If `nil`, the
    /// server replies with `200 OK`. Errors thrown inside this closure are
    /// surfaced as test failures by OHHTTPStubs.
    var logsResponseHandler: ((URLRequest, Int) -> HTTPStubsResponse)?
    var version: Int = 3

    func trackBatchRequest(_ request: URLRequest) {
        batchRequests.append(request)

        if batchRequests.count >= (batchExpectationCount ?? 0) {
            batchExpectation?.fulfill()
        }
    }

    func trackSnapshotRequest(_ request: URLRequest) {
        snapshotRequests.append(request)

        if snapshotRequests.count >= (snapshotExpectationCount ?? 0) {
            snapshotExpectation?.fulfill()
        }
    }

    func trackLogsRequest(_ request: URLRequest) {
        logsRequests.append(request)

        if logsRequests.count >= (logsExpectationCount ?? 0) {
            logsExpectation?.fulfill()
        }
    }

    func trackFlags(_ request: URLRequest) {
        flagsRequests.append(request)

        if let count = flagsExpectationCount {
            if flagsRequests.count >= count {
                flagsExpectation?.fulfill()
            }
        } else {
            flagsExpectation?.fulfill()
        }
    }

    var errorsWhileComputingFlags = false
    var return500 = false
    var returnReplay = false
    var returnReplayWithVariant = false
    var returnReplayWithMultiVariant = false
    var replayVariantName = "myBooleanRecordingFlag"
    var flagsSkipReplayVariantName = false
    var replayVariantValue: Any = true
    var quotaLimitFeatureFlags: Bool = false
    var remoteConfigSurveys: String?
    var hasFeatureFlags: Bool? = true
    var featureFlags: [String: Any]?
    var disabledFlag: Bool = false
    var sessionRecordingSampleRate: String?
    var sessionRecordingEventTriggers: [String]?
    var remoteConfigErrorTracking: Any? = ["autocaptureExceptions": true]

    // version is the version of the response we want to return regardless of the request version
    init(version: Int = 3) {
        self.version = version

        stubDescriptors.append(stub(condition: pathEndsWith("/flags")) { request in
            if let handler = self.flagsResponseHandler {
                let response = handler(request)
                if self.flagsResponseDelay > 0 {
                    response.responseTime = self.flagsResponseDelay
                }
                return response
            }

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
                "flag-with-tags": "control",
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
                    "enabled": self.disabledFlag,
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
                "flag-with-tags": [
                    "key": "flag-with-tags",
                    "enabled": true,
                    "variant": "control",
                    "evaluation_tags": ["tag1", "tag2", "experiment"],
                    "reason": [
                        "type": "condition_match",
                        "description": "Matched condition set 1",
                        "condition_index": 0,
                    ],
                    "metadata": [
                        "id": 8,
                        "version": 1,
                        "payload": nil,
                        "description": "Flag with evaluation tags",
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
                    "evaluatedAt": 1234567890,
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
                    "evaluatedAt": 1234567890,
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

                if let sampleRate = self.sessionRecordingSampleRate {
                    sessionRecording["sampleRate"] = sampleRate
                }

                if let eventTriggers = self.sessionRecordingEventTriggers {
                    sessionRecording["eventTriggers"] = eventTriggers
                }

                obj["sessionRecording"] = sessionRecording
            } else {
                obj["sessionRecording"] = false
            }

            let response = HTTPStubsResponse(jsonObject: obj, statusCode: 200, headers: nil)
            if self.flagsResponseDelay > 0 {
                response.responseTime = self.flagsResponseDelay
            }
            return response
        })

        stubDescriptors.append(stub(condition: pathEndsWith("/batch")) { _ in
            if self.return500 {
                HTTPStubsResponse(jsonObject: [], statusCode: 500, headers: nil)
            } else {
                HTTPStubsResponse(jsonObject: ["status": "ok"], statusCode: 200, headers: nil)
            }
        })

        stubDescriptors.append(stub(condition: pathEndsWith("/s")) { _ in
            if self.return500 {
                HTTPStubsResponse(jsonObject: [], statusCode: 500, headers: nil)
            } else {
                HTTPStubsResponse(jsonObject: ["status": "ok"], statusCode: 200, headers: nil)
            }
        })

        stubDescriptors.append(stub(condition: pathEndsWith("/i/v1/logs")) { request in
            // Default: 200 OK. Tests can install `logsResponseHandler` to vary
            // the response per request (e.g. 413 then 200 for backpressure tests).
            if let handler = self.logsResponseHandler {
                return handler(request, self.logsRequests.count + 1)
            }
            return HTTPStubsResponse(jsonObject: ["status": "ok"], statusCode: 200, headers: nil)
        })

        stubDescriptors.append(stub(condition: pathEndsWith("/config")) { _ in
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

            let errorTrackingPayload: String = {
                if let dict = self.remoteConfigErrorTracking as? [String: Any] {
                    let jsonData = try? JSONSerialization.data(withJSONObject: dict)
                    return "\"errorTracking\": \(String(data: jsonData ?? Data(), encoding: .utf8) ?? "false"),"
                } else if let boolVal = self.remoteConfigErrorTracking as? Bool {
                    return "\"errorTracking\": \(boolVal),"
                } else {
                    return ""
                }
            }()

            // Build sessionRecording payload
            let sessionRecordingPayload: String = {
                if self.returnReplay {
                    var sessionRecording: [String: Any] = ["endpoint": "/s/"]
                    if let sampleRate = self.sessionRecordingSampleRate {
                        sessionRecording["sampleRate"] = sampleRate
                    }
                    if let eventTriggers = self.sessionRecordingEventTriggers {
                        sessionRecording["eventTriggers"] = eventTriggers
                    }
                    if let data = try? JSONSerialization.data(withJSONObject: sessionRecording),
                       let jsonString = String(data: data, encoding: .utf8)
                    {
                        return jsonString
                    }
                    return "{\"endpoint\": \"/s/\"}"
                }
                return "false"
            }()

            let configData =
                """
                {
                    "token": "test_project_token",
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
                    \(errorTrackingPayload)
                    "analytics": {
                        "endpoint": "/i/v0/e/"
                    },
                    "elementsChainAsString": true,
                    "sessionRecording": \(sessionRecordingPayload),
                    "heatmaps": true,
                    "surveys": \(self.remoteConfigSurveys ?? "false"),
                    "defaultIdentifiedOnly": true,
                    "siteApps": []
                }
                """.data(using: .utf8)!

            return HTTPStubsResponse(data: configData, statusCode: 200, headers: nil)
        })

        HTTPStubs.onStubActivation { request, _, _ in
            if request.url?.lastPathComponent == "batch" {
                self.trackBatchRequest(request)
            } else if request.url?.lastPathComponent == "s" {
                self.trackSnapshotRequest(request)
            } else if request.url?.lastPathComponent == "logs" {
                self.trackLogsRequest(request)
            } else if request.url?.lastPathComponent == "flags" {
                self.trackFlags(request)
            }
        }
    }

    func start(batchCount: Int = 1, snapshotCount: Int = 0, logsCount: Int = 0) {
        reset(batchCount: batchCount, snapshotCount: snapshotCount, logsCount: logsCount)

        HTTPStubs.setEnabled(true)
    }

    func stop() {
        reset()

        for descriptor in stubDescriptors {
            HTTPStubs.removeStub(descriptor)
        }
        stubDescriptors.removeAll()
    }

    func reset(batchCount: Int = 1, snapshotCount: Int = 0, flagsCount: Int? = nil, logsCount: Int = 0) {
        batchRequests = []
        snapshotRequests = []
        logsRequests = []
        flagsRequests = []
        batchExpectation = XCTestExpectation(description: "\(batchCount) batch requests to occur")
        snapshotExpectation = XCTestExpectation(description: "\(snapshotCount) snapshot requests to occur")
        logsExpectation = XCTestExpectation(description: "\(logsCount) logs requests to occur")
        flagsExpectation = XCTestExpectation(description: "\(flagsCount ?? 1) flag requests to occur")
        batchExpectationCount = batchCount
        snapshotExpectationCount = snapshotCount
        logsExpectationCount = logsCount
        flagsExpectationCount = flagsCount
        flagsResponseDelay = 0
        flagsResponseHandler = nil
        logsResponseHandler = nil
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
