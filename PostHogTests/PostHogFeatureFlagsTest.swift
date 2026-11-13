//
//  PostHogFeatureFlagsTest.swift
//  PostHog
//
//  Created by Yiannis Josephides on 20/01/2025.
//

import OHHTTPStubs
@testable import PostHog
import Testing
import XCTest

/// Sample struct for testing payload decoding
private struct TestPayload: Decodable, Equatable {
    let name: String
    let count: Int
}

@Suite("Test Feature Flags", .serialized)
enum PostHogFeatureFlagsTest {
    class BaseTestClass {
        let config: PostHogConfig = {
            let c = PostHogConfig(projectToken: "test_project_token", host: "http://localhost:9001")
            c.preloadFeatureFlags = false
            c.disableReachabilityForTesting = true
            c.disableQueueTimerForTesting = true
            c.disableFlushOnBackgroundForTesting = true
            return c
        }()

        var server: MockPostHogServer!

        // SDKs created per test, closed in deinit so their queues/timers/observers don't leak
        // across the run and starve the background thread pool. close() is idempotent.
        var trackedSuts: [PostHogSDK] = []
        func track(_ sut: PostHogSDK) -> PostHogSDK {
            trackedSuts.append(sut)
            return sut
        }

        init() {
            server = MockPostHogServer(version: 4)
            server.start()
            // important!
            let storage = PostHogStorage(config)
            storage.reset()
        }

        deinit {
            trackedSuts.forEach { $0.close() }
            server.stop()
            server = nil
        }

        func getSut(
            storage: PostHogStorage? = nil,
            config: PostHogConfig? = nil
        ) -> PostHogRemoteConfig {
            let theConfig = config ?? self.config
            let theStorage = storage ?? PostHogStorage(theConfig)
            let api = PostHogApi(theConfig)
            return PostHogRemoteConfig(theConfig, theStorage, api) { [:] }
        }
    }

    @Suite("Test failed detailed flag records")
    class TestFailedFlagRecords: BaseTestClass {
        private func stubFlags(_ flags: [String: Any], errors: Bool?, minimal: Bool = false) {
            var response: [String: Any] = [
                "flags": flags,
                "minimalFlagCalledEvents": minimal,
                // Detailed records are authoritative even when flat mirrors accompany them.
                "featureFlags": ["failed-boolean": false, "failed-variant": "placeholder"],
                "featureFlagPayloads": ["failed-variant": "\"placeholder\""],
            ]
            if let errors { response["errorsWhileComputingFlags"] = errors }
            server.flagsResponseHandler = { _ in
                HTTPStubsResponse(jsonObject: response, statusCode: 200, headers: nil)
            }
        }

        private func failedFlags() -> [String: Any] {
            [
                "failed-boolean": ["enabled": false, "failed": true],
                "failed-variant": [
                    "enabled": true, "variant": "placeholder", "failed": true,
                    "reason": ["description": "Evaluation failed"],
                    "metadata": ["id": 123, "version": 7, "payload": "\"placeholder\"", "has_experiment": false],
                ],
                "healthy-false": ["enabled": false, "failed": false],
                "healthy-false-absent": ["enabled": false],
                "healthy-true": ["enabled": true],
                "healthy-variant": ["enabled": true, "variant": "blue", "metadata": ["payload": "\"healthy\""]],
            ]
        }

        private func reload(_ sut: PostHogSDK) async {
            await withCheckedContinuation { continuation in
                sut.reloadFeatureFlags { continuation.resume() }
            }
        }

        @Test("Failed records supply neither values nor payloads regardless of the global bit", arguments: [nil, false, true] as [Bool?])
        func failedRecordsDoNotSupplyValues(errors: Bool?) async throws {
            stubFlags(failedFlags(), errors: errors)
            let sut = track(PostHogSDK.with(config))
            await reload(sut)

            for key in ["failed-boolean", "failed-variant"] {
                #expect(sut.getFeatureFlagResult(key, sendFeatureFlagEvent: false) == nil)
                #expect(sut.getFeatureFlag(key, sendFeatureFlagEvent: false) == nil)
                #expect(sut.isFeatureEnabled(key, sendFeatureFlagEvent: false) == false)
                #expect(sut.remoteConfig?.getFeatureFlagPayload(key) == nil)
            }
            #expect(sut.getFeatureFlagResult("healthy-false", sendFeatureFlagEvent: false)?.enabled == false)
            let results = try #require(sut.getAllFeatureFlags())
            #expect(Set(results.map(\.key)) == ["healthy-false", "healthy-false-absent", "healthy-true", "healthy-variant"])
            #expect(results.first { $0.key == "healthy-false-absent" }?.enabled == false)
            #expect(results.first { $0.key == "healthy-variant" }?.payload as? String == "healthy")

            server.reset(batchCount: 1)
            sut.capture("filtered-enrichment")
            sut.flush()
            let events = try await getServerEvents(server)
            let event = try #require(events.first { $0.event == "filtered-enrichment" })
            #expect(event.properties["$feature/failed-boolean"] == nil)
            #expect(event.properties["$feature/failed-variant"] == nil)
            #expect(event.properties["$feature/healthy-true"] as? Bool == true)
            #expect(events.allSatisfy { $0.event != "$feature_flag_called" })
        }

        @Test("Failed reads report failure with a null response and preserve controls", arguments: [nil, false, true] as [Bool?], [false, true])
        func failedReadEvents(errors: Bool?, minimal: Bool) async throws {
            stubFlags(failedFlags(), errors: errors, minimal: minimal)
            let sut = track(PostHogSDK.with(config))
            await reload(sut)
            server.reset(batchCount: 1)

            _ = sut.getFeatureFlagResult("failed-variant", sendFeatureFlagEvent: false)
            _ = sut.getFeatureFlagResult("failed-variant")
            _ = sut.getFeatureFlag("failed-variant")
            _ = sut.isFeatureEnabled("failed-variant")
            _ = sut.getFeatureFlagResult("healthy-false")
            _ = sut.getFeatureFlagResult("failed-boolean", sendFeatureFlagEvent: false)
            sut.capture("flush-marker")
            sut.flush()

            let events = try await getServerEvents(server)
            let calls = events.filter { $0.event == "$feature_flag_called" }
            #expect(calls.count == 2)
            let failed = try #require(calls.first { $0.properties["$feature_flag"] as? String == "failed-variant" })
            #expect(failed.properties["$feature_flag_response"] is NSNull)
            let error = failed.properties["$feature_flag_error"] as? String
            #expect(error == (errors == true ? "evaluation_failed,errors_while_computing_flags" : "evaluation_failed"))
            #expect(failed.properties["$feature_flag_reason"] as? String == "Evaluation failed")
            #expect(failed.properties["$feature_flag_id"] as? Int == 123)
            #expect(failed.properties["$feature_flag_version"] as? Int == 7)
            let healthy = try #require(calls.first { $0.properties["$feature_flag"] as? String == "healthy-false" })
            #expect(healthy.properties["$feature_flag_response"] as? Bool == false)
            #expect(healthy.properties["$feature_flag_error"] as? String == (errors == true ? "errors_while_computing_flags" : nil))
        }

        @Test("Only response-wide errors retain prior successful values and payloads", arguments: [nil, false, true] as [Bool?])
        func refreshRetainsOnlyOnResponseWideErrors(errors: Bool?) async throws {
            let previous: [String: Any] = [
                "enabled": ["enabled": true, "metadata": ["payload": "\"local-true\""]],
                "disabled": ["enabled": false],
                "variant": ["enabled": true, "variant": "blue", "metadata": ["payload": "\"local-variant\""]],
            ]
            stubFlags(previous, errors: false)
            let sut = track(PostHogSDK.with(config))
            await reload(sut)

            let failed = ["enabled": false, "variant": "placeholder", "failed": true, "metadata": ["payload": "\"remote\""]] as [String: Any]
            stubFlags(["enabled": failed, "disabled": failed, "variant": failed, "fresh": failed], errors: errors)
            await reload(sut)

            let results = try #require(sut.getAllFeatureFlags())
            if errors == true {
                #expect(Set(results.map(\.key)) == ["enabled", "disabled", "variant"])
                #expect(sut.getFeatureFlagResult("enabled", sendFeatureFlagEvent: false)?.enabled == true)
                #expect(sut.getFeatureFlagResult("enabled", sendFeatureFlagEvent: false)?.payload as? String == "local-true")
                #expect(sut.getFeatureFlagResult("disabled", sendFeatureFlagEvent: false)?.enabled == false)
                #expect(sut.getFeatureFlagResult("variant", sendFeatureFlagEvent: false)?.variant == "blue")
                #expect(sut.getFeatureFlagResult("variant", sendFeatureFlagEvent: false)?.payload as? String == "local-variant")
            } else {
                #expect(results.isEmpty)
            }
            #expect(sut.getFeatureFlagResult("fresh", sendFeatureFlagEvent: false) == nil)

            server.reset(batchCount: 1)
            _ = sut.getFeatureFlagResult("enabled")
            sut.flush()
            let events = try await getServerEvents(server)
            let call = try #require(events.first { $0.event == "$feature_flag_called" })
            #expect(call.properties["$feature_flag_error"] as? String == (errors == true ? "errors_while_computing_flags" : "evaluation_failed"))
            if errors == true {
                #expect(call.properties["$feature_flag_response"] as? Bool == true)
            } else {
                #expect(call.properties["$feature_flag_response"] is NSNull)
            }
        }

        @Test("A complete legacy response clears prior failure diagnostics without changing flat values")
        func legacyRefreshClearsFailureDiagnostics() async throws {
            stubFlags(failedFlags(), errors: true)
            let sut = track(PostHogSDK.with(config))
            await reload(sut)
            server.flagsResponseHandler = { _ in
                HTTPStubsResponse(jsonObject: [
                    "featureFlags": ["legacy-disabled": false, "legacy-variant": "blue"],
                    "featureFlagPayloads": ["legacy-variant": "\"legacy\""],
                ], statusCode: 200, headers: nil)
            }
            await reload(sut)
            #expect(sut.getFeatureFlagResult("legacy-disabled", sendFeatureFlagEvent: false)?.enabled == false)
            #expect(sut.getFeatureFlagResult("legacy-variant", sendFeatureFlagEvent: false)?.variant == "blue")
            #expect(sut.getFeatureFlagResult("legacy-variant", sendFeatureFlagEvent: false)?.payload as? String == "legacy")
            server.reset(batchCount: 1)
            #expect(sut.getFeatureFlagResult("failed-variant") == nil)
            sut.flush()
            let events = try await getServerEvents(server)
            let call = try #require(events.first { $0.event == "$feature_flag_called" })
            #expect(call.properties["$feature_flag_response"] is NSNull)
            #expect(call.properties["$feature_flag_error"] == nil)
        }

        @Test("Reset clears both per-record and response-wide failure diagnostics")
        func resetClearsFailureDiagnostics() async throws {
            stubFlags(failedFlags(), errors: true)
            let sut = track(PostHogSDK.with(config))
            await reload(sut)
            sut.remoteConfig?.canReloadFlagsForTesting = false
            sut.reset()
            server.reset(batchCount: 1)
            #expect(sut.getFeatureFlagResult("failed-variant") == nil)
            sut.flush()
            let events = try await getServerEvents(server)
            let call = try #require(events.first { $0.event == "$feature_flag_called" })
            #expect(call.properties["$feature_flag_response"] is NSNull)
            #expect(call.properties["$feature_flag_error"] == nil)
        }

        @Test("Persisted failed placeholders from older SDKs are removed before offline reads")
        func persistedFailedPlaceholdersAreNotServed() async throws {
            config.disableRemoteConfigForTesting = true
            let storage = PostHogStorage(config)
            storage.setDictionary(forKey: .flags, contents: [
                "failed-variant": ["enabled": true, "variant": "placeholder", "failed": true, "metadata": ["payload": "\"placeholder\""]],
                "failed-boolean": ["enabled": false, "failed": true],
                "healthy-false": ["enabled": false, "failed": false],
                "healthy-variant": ["enabled": true, "variant": "blue"],
            ])
            storage.setDictionary(forKey: .enabledFeatureFlags, contents: [
                "failed-variant": "placeholder", "failed-boolean": false,
                "healthy-false": false, "healthy-variant": "blue", "legacy": true,
            ])
            storage.setDictionary(forKey: .enabledFeatureFlagPayloads, contents: [
                "failed-variant": "\"placeholder\"", "failed-boolean": "\"placeholder\"",
                "healthy-variant": "\"healthy\"", "legacy": "\"legacy\"",
            ])
            let sut = track(PostHogSDK.with(config))
            for key in ["failed-variant", "failed-boolean"] {
                #expect(sut.getFeatureFlagResult(key, sendFeatureFlagEvent: false) == nil)
                #expect(sut.getFeatureFlag(key, sendFeatureFlagEvent: false) == nil)
                #expect(sut.remoteConfig?.getFeatureFlagPayload(key) == nil)
                let persisted = PostHogStorage(config)
                #expect(persisted.getDictionary(forKey: .enabledFeatureFlags)?[key] == nil)
                #expect(persisted.getDictionary(forKey: .enabledFeatureFlagPayloads)?[key] == nil)
            }
            #expect(Set((sut.getAllFeatureFlags() ?? []).map(\.key)) == ["healthy-false", "healthy-variant", "legacy"])
            #expect(sut.getFeatureFlagResult("healthy-false", sendFeatureFlagEvent: false)?.enabled == false)
            #expect(sut.getFeatureFlagResult("healthy-variant", sendFeatureFlagEvent: false)?.payload as? String == "healthy")
            #expect(sut.getFeatureFlagResult("legacy", sendFeatureFlagEvent: false)?.payload as? String == "legacy")

            server.reset(batchCount: 1)
            _ = sut.getFeatureFlagResult("failed-variant")
            sut.flush()
            let events = try await getServerEvents(server)
            let call = try #require(events.first { $0.event == "$feature_flag_called" })
            #expect(call.properties["$feature_flag_response"] is NSNull)
            #expect(call.properties["$feature_flag_error"] as? String == "evaluation_failed")
        }

        @Test("Reopening a failed cache preserves both causes until a complete refresh", arguments: [nil, false] as [Bool?])
        func persistedResponseWideErrorsSurviveReopen(refreshErrors: Bool?) async throws {
            config.disableRemoteConfigForTesting = true
            stubFlags(failedFlags(), errors: true)
            let first = track(PostHogSDK.with(config))
            await reload(first)
            first.close()
            let reopened = track(PostHogSDK.with(config))
            server.reset(batchCount: 1)
            #expect(reopened.getFeatureFlagResult("failed-variant") == nil)
            reopened.flush()
            let events = try await getServerEvents(server)
            let call = try #require(events.first { $0.event == "$feature_flag_called" })
            #expect(call.properties["$feature_flag_response"] is NSNull)
            #expect(call.properties["$feature_flag_error"] as? String == "evaluation_failed,errors_while_computing_flags")

            stubFlags(failedFlags(), errors: refreshErrors)
            await reload(reopened)
            reopened.close()
            let refreshed = track(PostHogSDK.with(config))
            #expect(refreshed.remoteConfig?.getFeatureFlagErrors("failed-variant") == ["evaluation_failed"])
            stubFlags(failedFlags(), errors: true)
            await reload(refreshed)
            refreshed.remoteConfig?.canReloadFlagsForTesting = false
            refreshed.reset()
            refreshed.close()
            let reset = track(PostHogSDK.with(config))
            #expect(reset.remoteConfig?.getFeatureFlagErrors("failed-variant").isEmpty == true)
        }

        @Test("Reopening an errored cache preserves successful retained values and payloads")
        func persistedRetainedSuccessesSurviveReopen() async throws {
            config.disableRemoteConfigForTesting = true
            stubFlags([
                "enabled": ["enabled": true, "metadata": ["payload": "\"true-payload\""]],
                "disabled": ["enabled": false],
                "variant": ["enabled": true, "variant": "blue", "metadata": ["payload": "\"variant-payload\""]],
            ], errors: false)
            let first = track(PostHogSDK.with(config))
            await reload(first)
            let failed: [String: Any] = ["enabled": false, "failed": true]
            stubFlags(["enabled": failed, "disabled": failed, "variant": failed, "fresh": failed], errors: true)
            await reload(first)
            first.close()
            let reopened = track(PostHogSDK.with(config))
            #expect(reopened.getFeatureFlagResult("enabled", sendFeatureFlagEvent: false)?.enabled == true)
            #expect(reopened.getFeatureFlagResult("enabled", sendFeatureFlagEvent: false)?.payload as? String == "true-payload")
            #expect(reopened.getFeatureFlagResult("disabled", sendFeatureFlagEvent: false)?.enabled == false)
            #expect(reopened.getFeatureFlagResult("variant", sendFeatureFlagEvent: false)?.variant == "blue")
            #expect(reopened.getFeatureFlagResult("variant", sendFeatureFlagEvent: false)?.payload as? String == "variant-payload")
            #expect(reopened.getFeatureFlagResult("fresh", sendFeatureFlagEvent: false) == nil)
            #expect(reopened.remoteConfig?.getFeatureFlagErrors("enabled") == ["errors_while_computing_flags"])
        }

        @Test("Only fresh bootstrap values clear prior-session errors across restart", arguments: ["absent", "empty", "success"])
        func bootstrapClearsPreviousSessionResponseErrors(source: String) async throws {
            config.disableRemoteConfigForTesting = true
            stubFlags(failedFlags(), errors: true)
            let first = track(PostHogSDK.with(config))
            await reload(first)
            #expect(first.remoteConfig?.getFeatureFlagErrors("failed-variant") == ["evaluation_failed", "errors_while_computing_flags"])
            first.capture("first-session-marker")
            first.flush()
            let firstEvents = try await getServerEvents(server)
            #expect(firstEvents.contains { $0.event == "first-session-marker" })
            first.close()

            if source == "success" {
                config.bootstrap = PostHogBootstrapConfig(featureFlags: ["failed-variant": "blue"], featureFlagPayloads: ["failed-variant": "successful"])
            } else if source == "empty" {
                config.bootstrap = PostHogBootstrapConfig(featureFlags: [:], featureFlagPayloads: nil)
            }
            server.reset(batchCount: 1)
            let second = track(PostHogSDK.with(config))
            let expectedErrors = source == "success" ? [] : ["evaluation_failed", "errors_while_computing_flags"]
            #expect(second.remoteConfig?.getFeatureFlagErrors("failed-variant") == expectedErrors)
            let result = second.getFeatureFlagResult("failed-variant")
            if source == "success" {
                #expect(result?.variant == "blue")
                #expect(result?.payload as? String == "successful")
            } else {
                #expect(result == nil)
            }
            second.flush()
            let events = try await getServerEvents(server)
            let call = try #require(events.first { $0.event == "$feature_flag_called" && $0.properties["$feature_flag"] as? String == "failed-variant" })
            #expect(call.properties["$feature_flag_error"] as? String == (expectedErrors.isEmpty ? nil : expectedErrors.joined(separator: ",")))
            if source == "success" {
                #expect(call.properties["$feature_flag_response"] as? String == "blue")
            } else {
                #expect(call.properties["$feature_flag_response"] is NSNull)
            }
            #expect(server.flagsRequests.isEmpty)
            second.close()

            config.bootstrap = nil
            let reopened = track(PostHogSDK.with(config))
            #expect(reopened.remoteConfig?.getFeatureFlagErrors("failed-variant") == expectedErrors)
            let persistedResult = reopened.getFeatureFlagResult("failed-variant", sendFeatureFlagEvent: false)
            if source == "success" {
                #expect(persistedResult?.variant == "blue")
                #expect(persistedResult?.payload as? String == "successful")
            } else {
                #expect(persistedResult == nil)
            }
            #expect(server.flagsRequests.isEmpty)
        }

        @Test("Successful bootstrap and legacy values supersede stale failed details across restart", arguments: ["bootstrap", "bootstrap-errored", "legacy"])
        func successfulFallbackSurvivesSanitizer(source: String) async throws {
            config.disableRemoteConfigForTesting = true
            let failed: [String: Any] = [
                "enabled": false, "failed": true,
                "metadata": ["id": 123], "reason": ["description": "Failed evaluation"],
            ]
            stubFlags([
                "flag": failed,
                "retained": [
                    "enabled": true, "metadata": ["id": 456, "version": 7],
                    "reason": ["description": "Successful evaluation"],
                ],
            ], errors: false)
            let first = track(PostHogSDK.with(config))
            await reload(first)
            first.close()

            if source.hasPrefix("bootstrap") {
                config.bootstrap = PostHogBootstrapConfig(featureFlags: ["flag": "blue"], featureFlagPayloads: ["flag": "successful"])
                stubFlags(["flag": failed], errors: true)
            } else {
                server.flagsResponseHandler = { _ in
                    HTTPStubsResponse(jsonObject: [
                        "featureFlags": ["flag": "blue"],
                        "featureFlagPayloads": ["flag": "\"successful\""],
                        "errorsWhileComputingFlags": true,
                    ], statusCode: 200, headers: nil)
                }
            }
            let second = track(PostHogSDK.with(config))
            if source != "bootstrap" {
                await reload(second)
            }
            #expect(second.getFeatureFlagResult("flag", sendFeatureFlagEvent: false)?.variant == "blue")
            #expect(second.getFeatureFlagResult("flag", sendFeatureFlagEvent: false)?.payload as? String == "successful")
            #expect(second.remoteConfig?.getFeatureFlagDetails("flag") == nil)
            second.close()

            config.bootstrap = nil
            let reopened = track(PostHogSDK.with(config))
            #expect(reopened.getFeatureFlagResult("flag", sendFeatureFlagEvent: false)?.variant == "blue")
            #expect(reopened.getFeatureFlagResult("flag", sendFeatureFlagEvent: false)?.payload as? String == "successful")
            let expectedErrors = source == "bootstrap" ? [] : ["errors_while_computing_flags"]
            #expect(reopened.remoteConfig?.getFeatureFlagErrors("flag") == expectedErrors)
            #expect(reopened.remoteConfig?.getFeatureFlagDetails("flag") == nil)

            server.reset(batchCount: 1)
            _ = reopened.getFeatureFlagResult("flag")
            if source == "legacy" {
                #expect(reopened.getFeatureFlagResult("retained")?.enabled == true)
            }
            reopened.flush()
            let events = try await getServerEvents(server)
            let call = try #require(events.first { $0.event == "$feature_flag_called" && $0.properties["$feature_flag"] as? String == "flag" })
            #expect(call.properties["$feature_flag_response"] as? String == "blue")
            #expect(call.properties["$feature_flag_error"] as? String == expectedErrors.first)
            #expect(call.properties["$feature_flag_id"] == nil)
            #expect(call.properties["$feature_flag_reason"] == nil)
            if source == "legacy" {
                let retained = try #require(events.first { $0.event == "$feature_flag_called" && $0.properties["$feature_flag"] as? String == "retained" })
                #expect(retained.properties["$feature_flag_id"] as? Int == 456)
                #expect(retained.properties["$feature_flag_version"] as? Int == 7)
                #expect(retained.properties["$feature_flag_reason"] as? String == "Successful evaluation")
            }
        }

        @Test("The instance event setting also suppresses failed reads")
        func instanceEventSuppression() async throws {
            config.sendFeatureFlagEvent = false
            stubFlags(failedFlags(), errors: true)
            let sut = track(PostHogSDK.with(config))
            await reload(sut)
            server.reset(batchCount: 1)
            _ = sut.getFeatureFlagResult("failed-variant")
            sut.capture("flush-marker")
            sut.flush()
            let events = try await getServerEvents(server)
            #expect(events.allSatisfy { $0.event != "$feature_flag_called" })
        }
    }

    @Suite("Test getFeatureFlag")
    class TestGetFeatureFlagValue: BaseTestClass {
        @Test("Returns true for enabled Bool flag")
        func returnsTrueBoolean() async {
            let sut = getSut()

            await withCheckedContinuation { continuation in
                sut.loadFeatureFlags(distinctId: "distinctId", anonymousId: "anonymousId", groups: ["group": "value"], callback: { _ in
                    continuation.resume()
                })
            }

            #expect(sut.getFeatureFlag("bool-value") as? Bool == true)
        }

        @Test("Returns true for enabled String flag")
        func returnsTrueString() async {
            let sut = getSut()

            await withCheckedContinuation { continuation in
                sut.loadFeatureFlags(distinctId: "distinctId", anonymousId: "anonymousId", groups: ["group": "value"], callback: { _ in
                    continuation.resume()
                })
            }

            #expect(sut.getFeatureFlag("string-value") as? String == "test")
        }

        @Test("Returns false for disabled flag")
        func returnsFalseDisabled() async {
            let sut = getSut()

            await withCheckedContinuation { continuation in
                sut.loadFeatureFlags(distinctId: "distinctId", anonymousId: "anonymousId", groups: ["group": "value"], callback: { _ in
                    continuation.resume()
                })
            }

            #expect(sut.getFeatureFlag("disabled-flag") as? Bool == false)
        }

        @Test("returns feature flag value")
        func getFeatureFlagValue() async {
            let sut = getSut()

            await withCheckedContinuation { continuation in
                sut.loadFeatureFlags(distinctId: "distinctId", anonymousId: "anonymousId", groups: ["group": "value"], callback: { _ in
                    continuation.resume()
                })
            }

            #expect(sut.getFeatureFlag("string-value") as? String == "test")
        }
    }

    @Suite("Test getFeatureFlagPayload")
    class TestGetFeatureFlagPayload: BaseTestClass {
        @Test("returns feature flag payload as Int")
        func getFeatureFlagPayloadInt() async {
            let sut = getSut()

            await withCheckedContinuation { continuation in
                sut.loadFeatureFlags(distinctId: "distinctId", anonymousId: "anonymousId", groups: ["group": "value"], callback: { _ in
                    continuation.resume()
                })
            }

            #expect(sut.getFeatureFlagPayload("number-value") as? Int == 2)
        }

        @Test("returns feature flag payload as Dictionary")
        func getFeatureFlagPayloadDictionary() async {
            let sut = getSut()

            await withCheckedContinuation { continuation in
                sut.loadFeatureFlags(distinctId: "distinctId", anonymousId: "anonymousId", groups: ["group": "value"], callback: { _ in
                    continuation.resume()
                })
            }

            #expect(sut.getFeatureFlagPayload("payload-json") as? [String: String] == ["foo": "bar"])
        }
    }

    @Suite("Test feature flags loading")
    class TestLoadFeatureFlagsLoading: BaseTestClass {
        @Test("loads cached feature flags")
        func loadsCachedFeatureFlags() {
            let storage = PostHogStorage(config)
            defer { storage.reset() }

            storage.setDictionary(forKey: .enabledFeatureFlags, contents: ["foo": "bar"])

            let sut = getSut(storage: storage)

            #expect(sut.getFeatureFlags() as? [String: String] == ["foo": "bar"])
        }

        @Test("merge flags if computed errors")
        func mergeFlagsIfComputedErrors() async {
            let sut = getSut()

            await withCheckedContinuation { continuation in
                sut.loadFeatureFlags(distinctId: "distinctId", anonymousId: "anonymousId", groups: ["group": "value"], callback: { _ in
                    continuation.resume()
                })
            }

            server.errorsWhileComputingFlags = true

            await withCheckedContinuation { continuation in
                sut.loadFeatureFlags(distinctId: "distinctId", anonymousId: "anonymousId", groups: ["group": "value"], callback: { _ in
                    continuation.resume()
                })
            }

            #expect(sut.getFeatureFlag("new-flag") as? Bool == true)
            #expect(sut.getFeatureFlag("bool-value") as? Bool == true)
        }

        @Test("retains feature flags when quota limited")
        func retainsFeatureFlagsWhenQuotaLimited() async {
            let sut = getSut()

            // First load some feature flags normally
            await withCheckedContinuation { continuation in
                sut.loadFeatureFlags(distinctId: "distinctId", anonymousId: "anonymousId", groups: ["group": "value"], callback: { _ in
                    continuation.resume()
                })
            }

            // Verify flags are loaded
            #expect(sut.getFeatureFlag("bool-value") as? Bool == true)
            #expect(sut.getFeatureFlag("string-value") as? String == "test")

            // Now set the server to return quota limited response
            server.quotaLimitFeatureFlags = true

            // Load flags again, this time with quota limiting
            await withCheckedContinuation { continuation in
                sut.loadFeatureFlags(distinctId: "distinctId", anonymousId: "anonymousId", groups: ["group": "value"], callback: { _ in
                    continuation.resume()
                })
            }

            // Verify flags are retained (not cleared)
            #expect(sut.getFeatureFlag("bool-value") as? Bool == true)
            #expect(sut.getFeatureFlag("string-value") as? String == "test")
        }

        @Test("clear() removes in-memory feature flags")
        func clearRemovesInMemoryFeatureFlags() async {
            let sut = getSut()

            // First load some feature flags
            await withCheckedContinuation { continuation in
                sut.loadFeatureFlags(distinctId: "distinctId", anonymousId: "anonymousId", groups: ["group": "value"], callback: { _ in
                    continuation.resume()
                })
            }

            // Verify flags are loaded in memory
            #expect(sut.getFeatureFlag("bool-value") as? Bool == true)
            #expect(sut.getFeatureFlag("string-value") as? String == "test")

            // Call clear()
            sut.clear()

            // Verify flags are cleared from memory
            #expect(sut.getFeatureFlag("bool-value") == nil)
            #expect(sut.getFeatureFlag("string-value") == nil)
            #expect(sut.getFeatureFlags() == nil || sut.getFeatureFlags()?.isEmpty == true)
        }

        @Test("clear() clears person and group properties for flags")
        func clearClearsPersonAndGroupProperties() async {
            let storage = PostHogStorage(config)
            defer { storage.reset() }

            let sut = getSut(storage: storage)

            // Set person and group properties
            sut.setPersonPropertiesForFlags(["plan": "premium"])
            sut.setGroupPropertiesForFlags("company", properties: ["name": "Acme"])

            // Verify they are stored in disk
            let personProps = storage.getDictionary(forKey: .personPropertiesForFlags) as? [String: Any]
            #expect(personProps?["plan"] as? String == "premium")

            let groupProps = storage.getDictionary(forKey: .groupPropertiesForFlags) as? [String: [String: Any]]
            #expect(groupProps?["company"]?["name"] as? String == "Acme")

            // Call clear()
            sut.clear()

            // Verify person and group properties are cleared from disk
            let clearedPersonProps = storage.getDictionary(forKey: .personPropertiesForFlags) as? [String: Any]
            #expect(clearedPersonProps?.isEmpty == true || clearedPersonProps == nil)

            let clearedGroupProps = storage.getDictionary(forKey: .groupPropertiesForFlags) as? [String: [String: Any]]
            #expect(clearedGroupProps?.isEmpty == true || clearedGroupProps == nil)

            // Verify in-memory values are cleared by reloading flags and checking request
            await withCheckedContinuation { continuation in
                sut.loadFeatureFlags(distinctId: "distinctId", anonymousId: "anonymousId", groups: [:], callback: { _ in
                    continuation.resume()
                })
            }

            // Check the request doesn't contain the old person properties
            guard let lastRequest = server.flagsRequests.last,
                  let requestBody = server.parseRequest(lastRequest, gzip: false)
            else {
                #expect(Bool(false), "Failed to parse request body")
                return
            }

            // Person properties should be empty or only contain default properties (not "plan")
            let requestPersonProps = requestBody["person_properties"] as? [String: Any]
            #expect(requestPersonProps?["plan"] == nil, "Expected 'plan' to be cleared from person properties")
            let requestGroupProps = requestBody["group_properties"] as? [String: [String: Any]]
            #expect(requestGroupProps?["company"]?["name"] == nil)
        }
    }

    @Suite("Test Person and Group Properties for Flags")
    class TestPersonAndGroupPropertiesForFlags: BaseTestClass {
        @Test("Person properties are stored and retrieved correctly")
        func storeAndRetrievePersonProperties() async {
            let sut = track(PostHogSDK.with(config))

            // Enable person processing by identifying
            sut.identify("test_user")

            let properties = [
                "test_property": "test_value",
                "plan": "premium",
                "age": 25,
            ] as [String: Any]

            // Set properties
            sut.setPersonPropertiesForFlags(properties)

            // Verify they can be retrieved by testing the internal state
            // Since getPersonPropertiesForFlags is private, we'll test via flag loading
            await withCheckedContinuation { continuation in
                sut.reloadFeatureFlags {
                    continuation.resume()
                }
            }

            // Verify the request included person properties by checking server received data
            #expect(server.flagsRequests.count > 0, "Expected at least one flags request to be made")

            guard let lastRequest = server.flagsRequests.last else {
                #expect(Bool(false), "No flags request found in server.flagsRequests")
                return
            }

            guard let requestBody = server.parseRequest(lastRequest, gzip: false) else {
                #expect(Bool(false), "Failed to parse request body from flags request")
                return
            }

            guard let personProperties = requestBody["person_properties"] as? [String: Any] else {
                #expect(Bool(false), "Person properties not found in request body: \(requestBody)")
                return
            }

            #expect(personProperties["test_property"] as? String == "test_value", "Expected test_property to be 'test_value'")
            #expect(personProperties["plan"] as? String == "premium", "Expected plan to be 'premium'")
            #expect(personProperties["age"] as? Int == 25, "Expected age to be 25")
        }

        @Test("Person properties are additive")
        func personPropertiesAreAdditive() async {
            let sut = track(PostHogSDK.with(config))

            // Set first batch of properties
            sut.setPersonPropertiesForFlags(["property1": "value1", "shared": "original"])

            // Set second batch that overlaps
            sut.setPersonPropertiesForFlags(["property2": "value2", "shared": "updated"])

            await withCheckedContinuation { continuation in
                sut.reloadFeatureFlags {
                    continuation.resume()
                }
            }

            #expect(server.flagsRequests.count > 0, "Expected at least one flags request to be made")

            guard let lastRequest = server.flagsRequests.last else {
                #expect(Bool(false), "No flags request found in server.flagsRequests")
                return
            }

            guard let requestBody = server.parseRequest(lastRequest, gzip: false) else {
                #expect(Bool(false), "Failed to parse request body from flags request")
                return
            }

            guard let personProperties = requestBody["person_properties"] as? [String: Any] else {
                #expect(Bool(false), "Person properties not found in request body: \(requestBody)")
                return
            }

            #expect(personProperties["property1"] as? String == "value1", "Expected property1 to be 'value1'")
            #expect(personProperties["property2"] as? String == "value2", "Expected property2 to be 'value2'")
            #expect(personProperties["shared"] as? String == "updated", "Expected shared property to be 'updated' (latest value)")
        }

        @Test("Reset person properties clears all properties")
        func resetPersonPropertiesClearsAll() async throws {
            let sut = track(PostHogSDK.with(config))

            // Set some properties
            sut.setPersonPropertiesForFlags(["property1": "value1", "property2": "value2"])

            // Reset them
            sut.resetPersonPropertiesForFlags()

            await withCheckedContinuation { continuation in
                sut.reloadFeatureFlags {
                    continuation.resume()
                }
            }

            #expect(server.flagsRequests.count > 0, "Expected at least one flags request to be made")

            guard let lastRequest = server.flagsRequests.last else {
                #expect(Bool(false), "No flags request found in server.flagsRequests")
                return
            }

            guard let requestBody = server.parseRequest(lastRequest, gzip: false) else {
                #expect(Bool(false), "Failed to parse request body from flags request")
                return
            }

            // After reset, person_properties should only contain default device properties, not the custom ones
            let personProperties = try #require(requestBody["person_properties"] as? [String: Any])
            #expect(personProperties["property1"] == nil, "Expected property1 to be removed after reset")
            #expect(personProperties["property2"] == nil, "Expected property2 to be removed after reset")
        }

        @Test("Group properties are stored and retrieved correctly")
        func storeAndRetrieveGroupProperties() async {
            let sut = track(PostHogSDK.with(config))

            let properties = [
                "plan": "enterprise",
                "seats": 50,
                "industry": "technology",
            ] as [String: Any]

            // Set group properties
            sut.setGroupPropertiesForFlags("organization", properties: properties)

            await withCheckedContinuation { continuation in
                sut.reloadFeatureFlags {
                    continuation.resume()
                }
            }

            #expect(server.flagsRequests.count > 0, "Expected at least one flags request to be made")

            guard let lastRequest = server.flagsRequests.last else {
                #expect(Bool(false), "No flags request found in server.flagsRequests")
                return
            }

            guard let requestBody = server.parseRequest(lastRequest, gzip: false) else {
                #expect(Bool(false), "Failed to parse request body from flags request")
                return
            }

            guard let groupProperties = requestBody["group_properties"] as? [String: [String: Any]] else {
                #expect(Bool(false), "Group properties not found in request body: \(requestBody)")
                return
            }

            guard let orgProperties = groupProperties["organization"] else {
                #expect(Bool(false), "Organization group properties not found: \(groupProperties)")
                return
            }

            #expect(orgProperties["plan"] as? String == "enterprise", "Expected organization plan to be 'enterprise'")
            #expect(orgProperties["seats"] as? Int == 50, "Expected organization seats to be 50")
            #expect(orgProperties["industry"] as? String == "technology", "Expected organization industry to be 'technology'")
        }

        @Test("Multiple group types are handled correctly")
        func multipleGroupTypesHandled() async {
            let sut = track(PostHogSDK.with(config))

            // Set properties for different group types
            sut.setGroupPropertiesForFlags("organization", properties: ["plan": "enterprise"])
            sut.setGroupPropertiesForFlags("team", properties: ["role": "engineering"])

            await withCheckedContinuation { continuation in
                sut.reloadFeatureFlags {
                    continuation.resume()
                }
            }

            #expect(server.flagsRequests.count > 0, "Expected at least one flags request to be made")

            guard let lastRequest = server.flagsRequests.last else {
                #expect(Bool(false), "No flags request found in server.flagsRequests")
                return
            }

            guard let requestBody = server.parseRequest(lastRequest, gzip: false) else {
                #expect(Bool(false), "Failed to parse request body from flags request")
                return
            }

            guard let groupProperties = requestBody["group_properties"] as? [String: [String: Any]] else {
                #expect(Bool(false), "Group properties not found in request body: \(requestBody)")
                return
            }

            #expect(groupProperties["organization"]?["plan"] as? String == "enterprise", "Expected organization plan to be 'enterprise'")
            #expect(groupProperties["team"]?["role"] as? String == "engineering", "Expected team role to be 'engineering'")
        }

        @Test("Reset group properties for specific type")
        func resetGroupPropertiesSpecificType() async {
            let sut = track(PostHogSDK.with(config))

            // Set properties for multiple group types
            sut.setGroupPropertiesForFlags("organization", properties: ["plan": "enterprise"])
            sut.setGroupPropertiesForFlags("team", properties: ["role": "engineering"])

            // Reset only organization properties
            sut.resetGroupPropertiesForFlags("organization")

            await withCheckedContinuation { continuation in
                sut.reloadFeatureFlags {
                    continuation.resume()
                }
            }

            #expect(server.flagsRequests.count > 0, "Expected at least one flags request to be made")

            guard let lastRequest = server.flagsRequests.last else {
                #expect(Bool(false), "No flags request found in server.flagsRequests")
                return
            }

            guard let requestBody = server.parseRequest(lastRequest, gzip: false) else {
                #expect(Bool(false), "Failed to parse request body from flags request")
                return
            }

            guard let groupProperties = requestBody["group_properties"] as? [String: [String: Any]] else {
                #expect(Bool(false), "Group properties not found in request body: \(requestBody)")
                return
            }

            #expect(groupProperties["organization"] == nil, "Expected organization properties to be cleared")
            #expect(groupProperties["team"]?["role"] as? String == "engineering", "Expected team role to still be 'engineering'")
        }

        @Test("Reset all group properties")
        func resetAllGroupProperties() async {
            let sut = track(PostHogSDK.with(config))

            // Set properties for multiple group types
            sut.setGroupPropertiesForFlags("organization", properties: ["plan": "enterprise"])
            sut.setGroupPropertiesForFlags("team", properties: ["role": "engineering"])

            // Reset all group properties
            sut.resetGroupPropertiesForFlags()

            await withCheckedContinuation { continuation in
                sut.reloadFeatureFlags {
                    continuation.resume()
                }
            }

            #expect(server.flagsRequests.count > 0, "Expected at least one flags request to be made")

            guard let lastRequest = server.flagsRequests.last else {
                #expect(Bool(false), "No flags request found in server.flagsRequests")
                return
            }

            guard let requestBody = server.parseRequest(lastRequest, gzip: false) else {
                #expect(Bool(false), "Failed to parse request body from flags request")
                return
            }

            #expect(requestBody["group_properties"] == nil, "Expected group_properties to be nil after reset")
        }

        @Test("Both person and group properties sent together")
        func bothPersonAndGroupPropertiesSent() async {
            let sut = track(PostHogSDK.with(config))

            // Set both types of properties
            sut.setPersonPropertiesForFlags(["user_plan": "premium"])
            sut.setGroupPropertiesForFlags("organization", properties: ["org_plan": "enterprise"])

            await withCheckedContinuation { continuation in
                sut.reloadFeatureFlags {
                    continuation.resume()
                }
            }

            #expect(server.flagsRequests.count > 0, "Expected at least one flags request to be made")

            guard let lastRequest = server.flagsRequests.last else {
                #expect(Bool(false), "No flags request found in server.flagsRequests")
                return
            }

            guard let requestBody = server.parseRequest(lastRequest, gzip: false) else {
                #expect(Bool(false), "Failed to parse request body from flags request")
                return
            }

            // Check person properties
            guard let personProperties = requestBody["person_properties"] as? [String: Any] else {
                #expect(Bool(false), "Person properties not found in request body: \(requestBody)")
                return
            }

            #expect(personProperties["user_plan"] as? String == "premium", "Expected user_plan to be 'premium'")

            // Check group properties
            guard let groupProperties = requestBody["group_properties"] as? [String: [String: Any]] else {
                #expect(Bool(false), "Group properties not found in request body: \(requestBody)")
                return
            }

            #expect(groupProperties["organization"]?["org_plan"] as? String == "enterprise", "Expected organization org_plan to be 'enterprise'")
        }

        @Test("Capture with userProperties automatically sets person properties for flags")
        func captureWithUserPropertiesAutomaticallySetsPersonPropertiesForFlags() async {
            let sut = track(PostHogSDK.with(config))

            // Enable person processing
            sut.identify("test_user")

            // Capture event with user properties
            sut.capture("test_event", properties: ["event_prop": "value"], userProperties: ["user_plan": "premium"])

            await withCheckedContinuation { continuation in
                sut.reloadFeatureFlags {
                    continuation.resume()
                }
            }

            #expect(server.flagsRequests.count > 0, "Expected at least one flags request to be made")

            guard let lastRequest = server.flagsRequests.last else {
                #expect(Bool(false), "No flags request found in server.flagsRequests")
                return
            }

            guard let requestBody = server.parseRequest(lastRequest, gzip: false) else {
                #expect(Bool(false), "Failed to parse request body from flags request")
                return
            }

            // Check that person properties from capture were included
            guard let personProperties = requestBody["person_properties"] as? [String: Any] else {
                #expect(Bool(false), "Person properties not found in request body: \(requestBody)")
                return
            }

            #expect(personProperties["user_plan"] as? String == "premium", "Expected user_plan to be 'premium' from capture call")
        }

        @Test("Capture whose beforeSend resets keeps its userProperties out of the next user's flags")
        func captureWithBeforeSendResetKeepsUserPropertiesFromNextUser() {
            var sdk: PostHogSDK?
            config.setBeforeSend { event in
                if event.event == "test_event" {
                    sdk?.reset()
                }
                return event
            }
            let sut = track(PostHogSDK.with(config))
            sdk = sut
            sut.identify("test_user")

            sut.capture("test_event", userProperties: ["user_plan": "premium"])

            #expect(sut.getDistinctId() != "test_user")
            #expect(sut.remoteConfig?.getPersonPropertiesForFlags()["user_plan"] == nil)
        }

        @Test("Group with groupProperties automatically sets group properties for flags")
        func groupWithGroupPropertiesAutomaticallySetsGroupPropertiesForFlags() async {
            let sut = track(PostHogSDK.with(config))

            // Enable person processing
            sut.identify("test_user")

            // Call group with properties
            sut.group(type: "organization", key: "org123", groupProperties: ["org_plan": "enterprise"])

            await withCheckedContinuation { continuation in
                sut.reloadFeatureFlags {
                    continuation.resume()
                }
            }

            #expect(server.flagsRequests.count > 0, "Expected at least one flags request to be made")

            guard let lastRequest = server.flagsRequests.last else {
                #expect(Bool(false), "No flags request found in server.flagsRequests")
                return
            }

            guard let requestBody = server.parseRequest(lastRequest, gzip: false) else {
                #expect(Bool(false), "Failed to parse request body from flags request")
                return
            }

            // Check that group properties from group call were included
            guard let groupProperties = requestBody["group_properties"] as? [String: [String: Any]] else {
                #expect(Bool(false), "Group properties not found in request body: \(requestBody)")
                return
            }

            #expect(groupProperties["organization"]?["org_plan"] as? String == "enterprise", "Expected organization org_plan to be 'enterprise' from group call")
        }
    }

    @Suite("Test getFeatureFlagResult")
    class TestGetFeatureFlagResult: BaseTestClass {
        @Test("returns result for enabled boolean flag")
        func returnsResultForEnabledBoolFlag() async {
            let sut = track(PostHogSDK.with(config))

            await withCheckedContinuation { continuation in
                sut.reloadFeatureFlags {
                    continuation.resume()
                }
            }

            let result = sut.getFeatureFlagResult("bool-value", sendFeatureFlagEvent: false)
            #expect(result != nil)
            #expect(result?.key == "bool-value")
            #expect(result?.enabled == true)
            #expect(result?.variant == nil)
            sut.close()
        }

        @Test("returns result for string variant flag")
        func returnsResultForVariantFlag() async {
            let sut = track(PostHogSDK.with(config))

            await withCheckedContinuation { continuation in
                sut.reloadFeatureFlags {
                    continuation.resume()
                }
            }

            let result = sut.getFeatureFlagResult("string-value", sendFeatureFlagEvent: false)
            #expect(result != nil)
            #expect(result?.key == "string-value")
            #expect(result?.enabled == true)
            #expect(result?.variant == "test")
            sut.close()
        }

        @Test("returns result for disabled flag")
        func returnsResultForDisabledFlag() async {
            let sut = track(PostHogSDK.with(config))

            await withCheckedContinuation { continuation in
                sut.reloadFeatureFlags {
                    continuation.resume()
                }
            }

            let result = sut.getFeatureFlagResult("disabled-flag", sendFeatureFlagEvent: false)
            #expect(result != nil)
            #expect(result?.key == "disabled-flag")
            #expect(result?.enabled == false)
            #expect(result?.variant == nil)
            sut.close()
        }

        @Test("returns nil for non-existent flag")
        func returnsNilForNonExistentFlag() async {
            let sut = track(PostHogSDK.with(config))

            await withCheckedContinuation { continuation in
                sut.reloadFeatureFlags {
                    continuation.resume()
                }
            }

            let result = sut.getFeatureFlagResult("non-existent-flag", sendFeatureFlagEvent: false)
            #expect(result == nil)
            sut.close()
        }

        @Test("includes payload in result")
        func includesPayloadInResult() async {
            let sut = track(PostHogSDK.with(config))

            await withCheckedContinuation { continuation in
                sut.reloadFeatureFlags {
                    continuation.resume()
                }
            }

            let resultInt = sut.getFeatureFlagResult("number-value", sendFeatureFlagEvent: false)
            #expect(resultInt?.payload as? Int == 2)

            let resultJson = sut.getFeatureFlagResult("payload-json", sendFeatureFlagEvent: false)
            #expect(resultJson?.payload as? [String: String] == ["foo": "bar"])
            sut.close()
        }
    }

    @Suite("Test getFeatureFlagResult event sending")
    class TestGetFeatureFlagResultEventSending: BaseTestClass {
        @Test("sends feature flag called event by default")
        func sendsEventByDefault() async throws {
            config.sendFeatureFlagEvent = true
            config.flushAt = 1
            let sut = track(PostHogSDK.with(config))

            await withCheckedContinuation { continuation in
                sut.reloadFeatureFlags {
                    continuation.resume()
                }
            }

            server.reset(batchCount: 1)

            let result = sut.getFeatureFlagResult("bool-value")
            #expect(result != nil)

            sut.flush()
            let events = try await getServerEvents(server)

            let featureFlagEvent = events.first { $0.event == "$feature_flag_called" }
            #expect(featureFlagEvent != nil, "Expected $feature_flag_called event to be sent")
            #expect(featureFlagEvent?.properties["$feature_flag"] as? String == "bool-value")

            sut.close()
        }

        @Test("respects sendFeatureFlagEvent parameter when false")
        func respectsSendEventParameterFalse() async {
            config.sendFeatureFlagEvent = true
            config.flushAt = 1
            let sut = track(PostHogSDK.with(config))

            await withCheckedContinuation { continuation in
                sut.reloadFeatureFlags {
                    continuation.resume()
                }
            }

            server.reset(batchCount: 1)

            let result = sut.getFeatureFlagResult("bool-value", sendFeatureFlagEvent: false)
            #expect(result != nil)

            sut.flush()

            let events = getBatchedEvents(server, timeout: 0.5, failIfNotCompleted: false)
            let featureFlagEvent = events.first { $0.event == "$feature_flag_called" }
            #expect(
                featureFlagEvent == nil,
                "Expected NO $feature_flag_called event when sendFeatureFlagEvent is false"
            )

            sut.close()
        }

        @Test("getFeatureFlag returns consistent values with getFeatureFlagResult")
        func getFeatureFlagReturnsSameValue() async throws {
            let sut = track(PostHogSDK.with(config))

            await withCheckedContinuation { continuation in
                sut.reloadFeatureFlags {
                    continuation.resume()
                }
            }

            // Boolean flag: getFeatureFlag returns Bool, getFeatureFlagResult has enabled
            let boolResult = try #require(sut.getFeatureFlagResult("bool-value", sendFeatureFlagEvent: false))
            let boolValue = try #require(sut.getFeatureFlag("bool-value", sendFeatureFlagEvent: false) as? Bool)
            #expect(boolResult.enabled == boolValue)
            #expect(boolValue)

            // Variant flag: getFeatureFlag returns variant String, getFeatureFlagResult has variant
            let stringResult = try #require(sut.getFeatureFlagResult("string-value", sendFeatureFlagEvent: false))
            let stringValue = try #require(sut.getFeatureFlag("string-value", sendFeatureFlagEvent: false) as? String)
            #expect(stringResult.variant == stringValue)
            #expect(!stringValue.isEmpty)

            sut.close()
        }
    }

    @Suite("Test getAllFeatureFlags")
    class TestGetAllFeatureFlags: BaseTestClass {
        @Test("returns nil before flags are loaded")
        func returnsNilBeforeLoad() {
            let sut = track(PostHogSDK.with(config))
            #expect(sut.getAllFeatureFlags() == nil)
            sut.close()
        }

        @Test("returns all loaded flags, including disabled ones")
        func returnsAllFlagsIncludingDisabled() async {
            let sut = track(PostHogSDK.with(config))
            await withCheckedContinuation { continuation in
                sut.reloadFeatureFlags { continuation.resume() }
            }

            let all = sut.getAllFeatureFlags()
            #expect(all != nil)

            // Order is not guaranteed, so key by flag key.
            let byKey = Dictionary(uniqueKeysWithValues: (all ?? []).map { ($0.key, $0) })

            // Enabled boolean flag
            #expect(byKey["bool-value"]?.enabled == true)
            #expect(byKey["bool-value"]?.variant == nil)

            // Multivariate flag carries its variant
            #expect(byKey["string-value"]?.enabled == true)
            #expect(byKey["string-value"]?.variant == "test")

            // Disabled flag is INCLUDED as enabled=false (not filtered out) — matches Android.
            #expect(byKey["disabled-flag"] != nil, "disabled flags should be included in the result")
            #expect(byKey["disabled-flag"]?.enabled == false)
            #expect(byKey["disabled-flag"]?.variant == nil)

            sut.close()
        }

        @Test("decodes payloads (object and scalar)")
        func decodesPayloads() async {
            let sut = track(PostHogSDK.with(config))
            await withCheckedContinuation { continuation in
                sut.reloadFeatureFlags { continuation.resume() }
            }

            let byKey = Dictionary(uniqueKeysWithValues: (sut.getAllFeatureFlags() ?? []).map { ($0.key, $0) })

            // Scalar payload parsed via .fragmentsAllowed
            #expect(byKey["number-value"]?.payload as? Int == 2)
            // Object payload parsed to a dictionary
            #expect(byKey["payload-json"]?.payload as? [String: String] == ["foo": "bar"])

            sut.close()
        }

        @Test("each result matches getFeatureFlagResult for that key")
        func matchesSingleKeyResult() async throws {
            let sut = track(PostHogSDK.with(config))
            await withCheckedContinuation { continuation in
                sut.reloadFeatureFlags { continuation.resume() }
            }

            let flags = try #require(sut.getAllFeatureFlags())
            try #require(flags.contains { $0.key == "bool-value" })
            try #require(flags.contains { $0.key == "string-value" })
            for flag in flags {
                let single = sut.getFeatureFlagResult(flag.key, sendFeatureFlagEvent: false)
                #expect(flag.enabled == single?.enabled, "enabled mismatch for \(flag.key)")
                #expect(flag.variant == single?.variant, "variant mismatch for \(flag.key)")
            }

            sut.close()
        }

        @Test("does not send $feature_flag_called")
        func doesNotSendEvent() async {
            config.sendFeatureFlagEvent = true
            config.flushAt = 1
            let sut = track(PostHogSDK.with(config))
            await withCheckedContinuation { continuation in
                sut.reloadFeatureFlags { continuation.resume() }
            }

            server.reset(batchCount: 1)

            _ = sut.getAllFeatureFlags()

            sut.flush()
            let events = getBatchedEvents(server, timeout: 0.5, failIfNotCompleted: false)
            let ffEvent = events.first { $0.event == "$feature_flag_called" }
            #expect(ffEvent == nil, "getAllFeatureFlags must not emit $feature_flag_called")

            sut.close()
        }
    }

    @Suite("Test PostHogFeatureFlagResult payload methods")
    final class TestFeatureFlagResultPayloadMethods {
        @Test("payloadAs returns nil for nil payload")
        func payloadAsNil() {
            let result = PostHogFeatureFlagResult(
                key: "test", enabled: true, variant: nil, payload: nil
            )
            let decoded: TestPayload? = result.payloadAs(TestPayload.self)
            #expect(decoded == nil)
        }

        @Test("payloadAs returns direct type match for String")
        func payloadAsDirectMatchString() {
            let result = PostHogFeatureFlagResult(
                key: "test", enabled: true, variant: nil, payload: "hello"
            )
            let decoded: String? = result.payloadAs(String.self)
            #expect(decoded == "hello")
        }

        @Test("payloadAs returns direct type match for Int")
        func payloadAsDirectMatchInt() {
            let result = PostHogFeatureFlagResult(
                key: "test", enabled: true, variant: nil, payload: 42
            )
            let decoded: Int? = result.payloadAs(Int.self)
            #expect(decoded == 42)
        }

        @Test("payloadAs returns direct type match for Dictionary")
        func payloadAsDirectMatchDict() {
            let payload = ["foo": "bar"]
            let result = PostHogFeatureFlagResult(
                key: "test", enabled: true, variant: nil, payload: payload
            )
            let decoded: [String: String]? = result.payloadAs([String: String].self)
            #expect(decoded == ["foo": "bar"])
        }

        @Test("payloadAs decodes dictionary to Decodable struct")
        func payloadAsDecodable() {
            let payload: [String: Any] = ["name": "Test", "count": 5]
            let result = PostHogFeatureFlagResult(
                key: "test", enabled: true, variant: nil, payload: payload
            )
            let decoded: TestPayload? = result.payloadAs(TestPayload.self)
            #expect(decoded?.name == "Test")
            #expect(decoded?.count == 5)
        }

        @Test("payloadAs returns nil for invalid JSON structure")
        func payloadAsInvalidType() {
            // A Date is not a valid JSON object
            let result = PostHogFeatureFlagResult(
                key: "test", enabled: true, variant: nil, payload: Date()
            )
            let decoded: TestPayload? = result.payloadAs(TestPayload.self)
            #expect(decoded == nil)
        }

        @Test("payloadAs returns nil when decoding fails")
        func payloadAsDecodingFails() {
            // Payload structure doesn't match TestPayload
            let payload: [String: Any] = ["wrongKey": "wrongValue"]
            let result = PostHogFeatureFlagResult(
                key: "test", enabled: true, variant: nil, payload: payload
            )
            let decoded: TestPayload? = result.payloadAs(TestPayload.self)
            #expect(decoded == nil)
        }
    }

    @Suite("Test Evaluation Contexts")
    class TestEvaluationContexts: BaseTestClass {
        @Test("Evaluation contexts are included in flags request")
        func evaluationContextsIncludedInRequest() async {
            // Configure evaluation contexts
            config.evaluationContexts = ["production", "web", "checkout"]
            let sut = track(PostHogSDK.with(config))

            // Enable person processing
            sut.identify("test_user")

            // Load feature flags
            await withCheckedContinuation { continuation in
                sut.reloadFeatureFlags {
                    continuation.resume()
                }
            }

            // Verify the request included evaluation contexts
            #expect(server.flagsRequests.count > 0, "Expected at least one flags request to be made")

            guard let lastRequest = server.flagsRequests.last else {
                #expect(Bool(false), "No flags request found")
                return
            }

            guard let requestBody = server.parseRequest(lastRequest, gzip: false) else {
                #expect(Bool(false), "Failed to parse request body")
                return
            }

            guard let evaluationContexts = requestBody["evaluation_contexts"] as? [String] else {
                #expect(Bool(false), "Evaluation contexts not found in request body: \(requestBody)")
                return
            }

            #expect(evaluationContexts.count == 3, "Expected 3 evaluation contexts")
            #expect(evaluationContexts.contains("production"), "Expected 'production' in evaluation contexts")
            #expect(evaluationContexts.contains("web"), "Expected 'web' in evaluation contexts")
            #expect(evaluationContexts.contains("checkout"), "Expected 'checkout' in evaluation contexts")
        }

        @Test("Empty evaluation contexts not included in request")
        func emptyEvaluationContextsNotIncluded() async {
            // Configure with empty evaluation contexts
            config.evaluationContexts = []
            let sut = track(PostHogSDK.with(config))

            // Enable person processing
            sut.identify("test_user")

            // Load feature flags
            await withCheckedContinuation { continuation in
                sut.reloadFeatureFlags {
                    continuation.resume()
                }
            }

            // Verify the request did NOT include evaluation contexts
            #expect(server.flagsRequests.count > 0, "Expected at least one flags request to be made")

            guard let lastRequest = server.flagsRequests.last else {
                #expect(Bool(false), "No flags request found")
                return
            }

            guard let requestBody = server.parseRequest(lastRequest, gzip: false) else {
                #expect(Bool(false), "Failed to parse request body")
                return
            }

            #expect(requestBody["evaluation_contexts"] == nil, "Expected evaluation_contexts to NOT be present when empty")
        }

        @Test("Nil evaluation contexts not included in request")
        func nilEvaluationContextsNotIncluded() async {
            // Don't set evaluation contexts (leave as nil)
            let sut = track(PostHogSDK.with(config))

            // Enable person processing
            sut.identify("test_user")

            // Load feature flags
            await withCheckedContinuation { continuation in
                sut.reloadFeatureFlags {
                    continuation.resume()
                }
            }

            // Verify the request did NOT include evaluation contexts
            #expect(server.flagsRequests.count > 0, "Expected at least one flags request to be made")

            guard let lastRequest = server.flagsRequests.last else {
                #expect(Bool(false), "No flags request found")
                return
            }

            guard let requestBody = server.parseRequest(lastRequest, gzip: false) else {
                #expect(Bool(false), "Failed to parse request body")
                return
            }

            #expect(requestBody["evaluation_contexts"] == nil, "Expected evaluation_contexts to NOT be present when nil")
        }

        @Test("Can update evaluation contexts after initialization")
        func canUpdateEvaluationContexts() async {
            let sut = track(PostHogSDK.with(config))

            // Enable person processing
            sut.identify("test_user")

            // Initially no evaluation contexts
            await withCheckedContinuation { continuation in
                sut.reloadFeatureFlags {
                    continuation.resume()
                }
            }

            guard let firstRequest = server.flagsRequests.last,
                  let firstRequestBody = server.parseRequest(firstRequest, gzip: false)
            else {
                #expect(Bool(false), "Failed to parse first request")
                return
            }

            #expect(firstRequestBody["evaluation_contexts"] == nil, "Expected no evaluation_contexts in first request")

            // Update evaluation contexts
            config.evaluationContexts = ["staging", "mobile"]

            // Reload flags
            await withCheckedContinuation { continuation in
                sut.reloadFeatureFlags {
                    continuation.resume()
                }
            }

            guard let secondRequest = server.flagsRequests.last,
                  let secondRequestBody = server.parseRequest(secondRequest, gzip: false)
            else {
                #expect(Bool(false), "Failed to parse second request")
                return
            }

            guard let evaluationContexts = secondRequestBody["evaluation_contexts"] as? [String] else {
                #expect(Bool(false), "Evaluation contexts not found in second request")
                return
            }

            #expect(evaluationContexts.count == 2, "Expected 2 evaluation contexts in second request")
            #expect(evaluationContexts.contains("staging"), "Expected 'staging' in evaluation contexts")
            #expect(evaluationContexts.contains("mobile"), "Expected 'mobile' in evaluation contexts")
        }

        @Test("Deprecated evaluationEnvironments property still works")
        func deprecatedEvaluationEnvironmentsStillWorks() async {
            // Use the deprecated property
            config.evaluationEnvironments = ["production", "api"]
            let sut = track(PostHogSDK.with(config))

            // Verify the deprecated property maps to evaluationContexts
            #expect(config.evaluationContexts?.count == 2, "Expected evaluationContexts to be set via deprecated property")
            #expect(config.evaluationContexts?.contains("production") == true, "Expected 'production' in evaluationContexts")
            #expect(config.evaluationContexts?.contains("api") == true, "Expected 'api' in evaluationContexts")

            // Verify reading from deprecated property returns same values
            #expect(config.evaluationEnvironments?.count == 2, "Expected evaluationEnvironments getter to return same values")
            #expect(config.evaluationEnvironments?.contains("production") == true, "Expected 'production' from evaluationEnvironments getter")
            #expect(config.evaluationEnvironments?.contains("api") == true, "Expected 'api' from evaluationEnvironments getter")

            // Enable person processing
            sut.identify("test_user")

            // Load feature flags
            await withCheckedContinuation { continuation in
                sut.reloadFeatureFlags {
                    continuation.resume()
                }
            }

            // Verify the request included evaluation contexts (set via deprecated property)
            #expect(server.flagsRequests.count > 0, "Expected at least one flags request to be made")

            guard let lastRequest = server.flagsRequests.last else {
                #expect(Bool(false), "No flags request found")
                return
            }

            guard let requestBody = server.parseRequest(lastRequest, gzip: false) else {
                #expect(Bool(false), "Failed to parse request body")
                return
            }

            guard let evaluationContexts = requestBody["evaluation_contexts"] as? [String] else {
                #expect(Bool(false), "Evaluation contexts not found in request body: \(requestBody)")
                return
            }

            #expect(evaluationContexts.count == 2, "Expected 2 evaluation contexts")
            #expect(evaluationContexts.contains("production"), "Expected 'production' in evaluation contexts")
            #expect(evaluationContexts.contains("api"), "Expected 'api' in evaluation contexts")
        }
    }

    @Suite("Test Bootstrap Feature Flags")
    class TestBootstrapFeatureFlags: BaseTestClass {
        private func bootstrapConfig(
            featureFlags: [String: Any],
            featureFlagPayloads: [String: Any]? = nil
        ) -> PostHogConfig {
            let c = PostHogConfig(projectToken: "test_project_token", host: "http://localhost:9001")
            c.preloadFeatureFlags = false
            c.disableReachabilityForTesting = true
            c.disableQueueTimerForTesting = true
            c.disableFlushOnBackgroundForTesting = true
            c.disableRemoteConfigForTesting = true
            c.bootstrap = PostHogBootstrapConfig(
                featureFlags: featureFlags,
                featureFlagPayloads: featureFlagPayloads
            )
            return c
        }

        private func freshStorage(_ config: PostHogConfig) -> PostHogStorage {
            let storage = PostHogStorage(config)
            storage.reset()
            return storage
        }

        @Test("Bootstrapped flags are readable immediately after setup")
        func servesBootstrappedFlagsBeforeLoad() {
            let config = bootstrapConfig(featureFlags: ["beta-ui": true])
            let sut = getSut(storage: freshStorage(config), config: config)

            #expect(sut.getFeatureFlag("beta-ui") as? Bool == true)
        }

        @Test("Non-serializable bootstrapped values are dropped, not crashed on")
        func sanitizesInvalidBootstrappedValues() {
            // A non-JSON-serializable value (NaN) reaching the flag cache would raise an
            // uncatchable NSException in JSONSerialization; setup must drop it, not crash.
            let config = bootstrapConfig(
                featureFlags: ["good": true, "bad": Double.nan],
                featureFlagPayloads: ["good": ["k": "v"], "bad": ["n": Double.infinity]]
            )
            let sut = getSut(storage: freshStorage(config), config: config)

            #expect(sut.getFeatureFlag("good") as? Bool == true)
            #expect(sut.getFeatureFlag("bad") == nil)
            #expect(sut.getFeatureFlagPayload("bad") == nil)
        }

        @Test("Bootstrapped payload is served with its flag")
        func servesBootstrappedPayload() {
            let config = bootstrapConfig(
                featureFlags: ["beta-ui": "variant-a"],
                featureFlagPayloads: ["beta-ui": ["color": "blue"]]
            )
            let sut = getSut(storage: freshStorage(config), config: config)

            #expect(sut.getFeatureFlag("beta-ui") as? String == "variant-a")
            #expect(sut.getFeatureFlagPayload("beta-ui") as? [String: String] == ["color": "blue"])
        }

        @Test("Loaded flags override bootstrapped values")
        func loadedFlagsOverrideBootstrap() async {
            let config = bootstrapConfig(featureFlags: ["bool-value": "bootstrapped-variant"])
            let sut = getSut(storage: freshStorage(config), config: config)

            // Before load: the bootstrapped value wins
            #expect(sut.getFeatureFlag("bool-value") as? String == "bootstrapped-variant")

            await withCheckedContinuation { continuation in
                sut.loadFeatureFlags(distinctId: "distinctId", anonymousId: "anonymousId", groups: [:], callback: { _ in
                    continuation.resume()
                })
            }

            // After load: the server value (true) replaces the bootstrapped one
            #expect(sut.getFeatureFlag("bool-value") as? Bool == true)
        }

        @Test("A disabled (false) bootstrap flag is not served")
        func disabledBootstrapFlagNotServed() {
            let config = bootstrapConfig(featureFlags: ["enabled": true, "disabled": false, "variant": "v1"])
            let sut = getSut(storage: freshStorage(config), config: config)

            // Only enabled flags (truthy values) are served, matching posthog-js.
            #expect(sut.getFeatureFlag("enabled") as? Bool == true)
            #expect(sut.getFeatureFlag("variant") as? String == "v1")
            #expect(sut.getFeatureFlag("disabled") == nil)
        }

        @Test("A payload for a disabled bootstrap flag is not served")
        func disabledBootstrapPayloadNotServed() {
            let config = bootstrapConfig(
                featureFlags: ["enabled": "v1", "disabled": false],
                featureFlagPayloads: ["enabled": ["k": "v"], "disabled": ["k": "x"]]
            )
            let sut = getSut(storage: freshStorage(config), config: config)

            #expect(sut.getFeatureFlagPayload("enabled") as? [String: String] == ["k": "v"])
            #expect(sut.getFeatureFlagPayload("disabled") == nil)
        }

        @Test("A complete flags load drops bootstrapped-only keys")
        func completeLoadDropsBootstrappedOnlyKeys() async {
            let config = bootstrapConfig(featureFlags: ["bool-value": true, "legacy": true])
            let sut = getSut(storage: freshStorage(config), config: config)

            // Before load: both bootstrapped keys are served
            #expect(sut.getFeatureFlag("legacy") as? Bool == true)

            await withCheckedContinuation { continuation in
                sut.loadFeatureFlags(distinctId: "distinctId", anonymousId: "anonymousId", groups: [:], callback: { _ in
                    continuation.resume()
                })
            }

            // A complete /flags response replaces the served flags: bootstrapped-only "legacy" is
            // dropped, and the overlapping key reflects the loaded value.
            #expect(sut.getFeatureFlag("legacy") == nil)
            #expect(sut.getFeatureFlag("bool-value") as? Bool == true)
        }

        @Test("Bootstrap is first-session only: not resurrected after reset")
        func bootstrapNotReappliedAfterReset() async {
            let config = bootstrapConfig(featureFlags: ["legacy": true])
            let sut = getSut(storage: freshStorage(config), config: config)

            func load() async {
                await withCheckedContinuation { continuation in
                    sut.loadFeatureFlags(distinctId: "distinctId", anonymousId: "anonymousId", groups: [:], callback: { _ in
                        continuation.resume()
                    })
                }
            }

            // Bootstrap serves "legacy" before any load
            #expect(sut.getFeatureFlag("legacy") as? Bool == true)

            await load()
            #expect(sut.hasLoadedFeatureFlagsFromRemote() == true)

            // reset() clears the retained bootstrap and the loaded-from-remote latch
            sut.clear()
            #expect(sut.hasLoadedFeatureFlagsFromRemote() == false)

            // A reload for the new (post-reset) user must NOT re-inject the bootstrapped-only key
            await load()
            #expect(sut.getFeatureFlag("legacy") == nil)
        }

        @Test("Bootstrap seed fires the flags-loaded notification")
        @MainActor
        func bootstrapSeedFiresFlagsLoaded() async {
            let config = bootstrapConfig(featureFlags: ["beta-ui": true])
            let flagsLoaded = AsyncLatch()
            var receivedFlags: [String: Any]?

            // The SDK fires the bootstrap notification after subscribing its listeners; mirror that here.
            let sut = getSut(storage: freshStorage(config), config: config)
            let token = sut.onFeatureFlagsLoaded.subscribe { flags in
                receivedFlags = flags
                flagsLoaded.signal()
            }
            sut.notifyBootstrappedFlagsIfSeeded()

            await flagsLoaded.wait()

            #expect(receivedFlags?["beta-ui"] as? Bool == true)
            _ = token
        }
    }

    @Suite("Test Bootstrap Feature Flag Reporting")
    class TestBootstrapFeatureFlagReporting: BaseTestClass {
        private func enrichmentConfig(
            featureFlags: [String: Any],
            featureFlagPayloads: [String: Any]? = nil
        ) -> PostHogConfig {
            let c = PostHogConfig(projectToken: "test_project_token", host: "http://localhost:9001")
            c.preloadFeatureFlags = false
            c.disableReachabilityForTesting = true
            c.disableQueueTimerForTesting = true
            c.disableFlushOnBackgroundForTesting = true
            c.disableRemoteConfigForTesting = true
            c.captureApplicationLifecycleEvents = false
            c.captureScreenViews = false
            c.sendFeatureFlagEvent = true
            c.flushAt = 1
            c.bootstrap = PostHogBootstrapConfig(
                featureFlags: featureFlags,
                featureFlagPayloads: featureFlagPayloads
            )
            return c
        }

        @Test("$feature_flag_called reports bootstrap use before a flags response")
        func reportsUsedBootstrapTrueBeforeLoad() async throws {
            let config = enrichmentConfig(
                featureFlags: ["beta-ui": true],
                featureFlagPayloads: ["beta-ui": ["color": "blue"]]
            )
            let sut = track(PostHogSDK.with(config))

            server.reset(batchCount: 1)

            _ = sut.getFeatureFlag("beta-ui")
            sut.flush()

            let events = try await getServerEvents(server)
            let event = events.first {
                $0.event == "$feature_flag_called" && $0.properties["$feature_flag"] as? String == "beta-ui"
            }
            #expect(event != nil)
            #expect(event?.properties["$used_bootstrap_value"] as? Bool == true)
            #expect(event?.properties["$feature_flag_bootstrapped_response"] as? Bool == true)
            #expect(event?.properties["$feature_flag_bootstrapped_payload"] as? [String: String] == ["color": "blue"])

            sut.close()
        }

        @Test("$feature_flag_called reports bootstrap not used after a flags response")
        func reportsUsedBootstrapFalseAfterLoad() async throws {
            let config = enrichmentConfig(featureFlags: ["beta-ui": true])
            let sut = track(PostHogSDK.with(config))

            // Receive a /flags response first
            await withCheckedContinuation { continuation in
                sut.reloadFeatureFlags {
                    continuation.resume()
                }
            }

            server.reset(batchCount: 1)

            _ = sut.getFeatureFlag("beta-ui")
            sut.flush()

            let events = try await getServerEvents(server)
            let event = events.first {
                $0.event == "$feature_flag_called" && $0.properties["$feature_flag"] as? String == "beta-ui"
            }
            #expect(event != nil)
            #expect(event?.properties["$used_bootstrap_value"] as? Bool == false)
            // still reports the originally-bootstrapped response for the key
            #expect(event?.properties["$feature_flag_bootstrapped_response"] as? Bool == true)

            sut.close()
        }
    }

    #if SWIFT_PACKAGE
        @Suite("Test concurrent flag reload coalescing", .timeLimit(.minutes(1)))
    #else
        @Suite("Test concurrent flag reload coalescing")
    #endif
    class TestConcurrentFlagReloads: BaseTestClass {
        /// Held by the first `/flags` response until the test has issued the reloads that must
        /// coalesce behind it. Wall-clock delays leave that window to chance; this makes it certain.
        private let firstResponseGate = DispatchSemaphore(value: 0)

        /// Stubs `/flags` so that `override-flag` is only enabled when the request body actually
        /// carried `app_version_semver`. That makes a callback resolved against a real response
        /// distinguishable from one resolved against disk-cached, pre-override values.
        private func stubFlagsRequiringOverride(delay: TimeInterval, gateFirstResponse: Bool = false) {
            server.flagsResponseDelay = delay
            let gate = firstResponseGate
            nonisolated(unsafe) var gated = gateFirstResponse
            server.flagsResponseHandler = { request in
                if gated {
                    gated = false
                    gate.wait()
                }
                var personProperties: [String: Any]?
                if let data = request.body(),
                   let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
                {
                    personProperties = json["person_properties"] as? [String: Any]
                }
                let carriedOverride = personProperties?["app_version_semver"] as? String == "3.09.0"

                let body: [String: Any] = [
                    "featureFlags": ["override-flag": carriedOverride],
                    "featureFlagPayloads": [String: Any](),
                    "errorsWhileComputingFlags": false,
                ]
                return HTTPStubsResponse(jsonObject: body, statusCode: 200, headers: nil)
            }
        }

        @Test("a reload displaced from the pending slot resolves against a request that went out")
        func displacedReloadResolvesAgainstRealResponse() async {
            let sut = getSut()
            stubFlagsRequiringOverride(delay: 0, gateFirstResponse: true)

            sut.loadFeatureFlags(distinctId: "distinctId", anonymousId: nil, groups: [:], callback: { _ in })
            sut.setPersonPropertiesForFlags(["app_version_semver": "3.09.0"])

            let flags = await withCheckedContinuation { (continuation: CheckedContinuation<[String: Any]?, Never>) in
                sut.loadFeatureFlags(distinctId: "distinctId", anonymousId: nil, groups: [:], callback: { flags in
                    continuation.resume(returning: flags)
                })

                // displaces the reload above out of the pending slot
                sut.loadFeatureFlags(distinctId: "distinctId", anonymousId: nil, groups: [:], callback: { _ in })
                firstResponseGate.signal()
            }

            #expect(flags?["override-flag"] as? Bool == true)
            let sent = server.flagsRequests.compactMap { server.parseRequest($0, gzip: false) }
            #expect(sent.count == 2, "the two displaced reloads should coalesce into one request")
            let lastOverride = (sent.last?["person_properties"] as? [String: Any])?["app_version_semver"] as? String
            #expect(lastOverride == "3.09.0", "the coalesced request must carry the override")
        }

        @Test("setup -> set properties -> identify -> reload reads flags evaluated with the overrides")
        func startupSequenceReadsFlagsWithOverrides() async {
            let config = PostHogConfig(projectToken: "test_project_token", host: "http://localhost:9001")
            config.preloadFeatureFlags = true
            config.disableReachabilityForTesting = true
            config.disableQueueTimerForTesting = true
            config.disableFlushOnBackgroundForTesting = true
            config.captureApplicationLifecycleEvents = false
            config.captureScreenViews = false
            config.sendFeatureFlagEvent = false

            // /config resolves while the first /flags request is still in flight, so the automatic
            // preload it kicks off competes with the app's own reloads.
            stubFlagsRequiringOverride(delay: 0.3)
            server.configResponseDelay = 0.15

            let sut = track(PostHogSDK.with(config))

            await withCheckedContinuation { continuation in
                sut.setPersonPropertiesForFlags(["app_version_semver": "3.09.0"])
                sut.identify("test_user")
                sut.reloadFeatureFlags {
                    continuation.resume()
                }
            }

            #expect(sut.getFeatureFlag("override-flag") as? Bool == true)
        }

        @Test("setting properties then reloading resolves after a response carrying them")
        func setPropertiesThenReloadResolvesWithProperties() async {
            let sut = track(PostHogSDK.with(makeIsolatedConfig()))
            stubFlagsRequiringOverride(delay: 0)

            await withCheckedContinuation { continuation in
                sut.setPersonPropertiesForFlags(["app_version_semver": "3.09.0"], reloadFeatureFlags: false)
                sut.reloadFeatureFlags { continuation.resume() }
            }

            #expect(sut.getFeatureFlag("override-flag") as? Bool == true)
        }

        @Test("a queued reload carries person properties set while it waits")
        func queuedReloadCarriesLatePersonProperties() async {
            let sut = track(PostHogSDK.with(makeIsolatedConfig()))
            stubFlagsRequiringOverride(delay: 0.2)

            await withCheckedContinuation { continuation in
                sut.reloadFeatureFlags()
                sut.reloadFeatureFlags { continuation.resume() }
                sut.setPersonPropertiesForFlags(["app_version_semver": "3.09.0"], reloadFeatureFlags: false)
            }

            #expect(sut.getFeatureFlag("override-flag") as? Bool == true)
            let lastOverride = server.flagsRequests.last
                .flatMap { server.parseRequest($0, gzip: false) }
                .flatMap { $0["person_properties"] as? [String: Any] }?["app_version_semver"] as? String
            #expect(lastOverride == "3.09.0", "the queued reload must send properties set while it waited")
        }

        @Test("a failed reload resolves the completion and keeps the cached flags")
        func completionResolvesOnFailedReload() async {
            let sut = track(PostHogSDK.with(makeIsolatedConfig()))
            stubFlagsRequiringOverride(delay: 0)
            await withCheckedContinuation { continuation in
                sut.setPersonPropertiesForFlags(["app_version_semver": "3.09.0"], reloadFeatureFlags: false)
                sut.reloadFeatureFlags { continuation.resume() }
            }
            #expect(sut.getFeatureFlag("override-flag") as? Bool == true)

            server.flagsResponseHandler = { _ in
                HTTPStubsResponse(jsonObject: ["error": "nope"], statusCode: 400, headers: nil)
            }
            await withCheckedContinuation { continuation in
                sut.reloadFeatureFlags { continuation.resume() }
            }

            #expect(sut.getFeatureFlag("override-flag") as? Bool == true, "a failed reload must not clear cached flags")
        }

        private func makeIsolatedConfig() -> PostHogConfig {
            let config = PostHogConfig(projectToken: "test_project_token", host: "http://localhost:9001")
            config.preloadFeatureFlags = false
            config.disableReachabilityForTesting = true
            config.disableQueueTimerForTesting = true
            config.disableFlushOnBackgroundForTesting = true
            config.disableRemoteConfigForTesting = true
            config.captureApplicationLifecycleEvents = false
            config.captureScreenViews = false
            config.sendFeatureFlagEvent = false
            return config
        }
    }

    @Suite("Test onFeatureFlags")
    class TestOnFeatureFlags: BaseTestClass {
        /// Waits for the main-queue delivery that follows a completed reload.
        private func reload(_ sut: PostHogSDK) async {
            await withCheckedContinuation { continuation in
                sut.reloadFeatureFlags { continuation.resume() }
            }
            await MainActor.run {}
        }

        @Test("passes enabled flags and variants when flags load")
        func invokedOnLoad() async {
            let sut = track(PostHogSDK.with(config))
            var received: [PostHogFeatureFlagsLoaded] = []
            sut.onFeatureFlags { received.append($0) }

            await reload(sut)

            #expect(received.count == 1)
            #expect(received.first?.errorsLoading == false)
            #expect(received.first?.variants["bool-value"] as? Bool == true)
            #expect(received.first?.variants["string-value"] as? String == "test")
            #expect(received.first?.flags.contains("string-value") == true)
            // disabled flags are left out, matching posthog-js
            #expect(received.first?.flags.contains("disabled-flag") == false)
            #expect(received.first?.variants["disabled-flag"] == nil)
        }

        @Test("invokes a listener registered after flags loaded with the current values")
        func lateListener() async {
            let sut = track(PostHogSDK.with(config))
            await reload(sut)

            let loaded = await withCheckedContinuation { continuation in
                sut.onFeatureFlags { continuation.resume(returning: $0) }
            }

            #expect(loaded.variants["string-value"] as? String == "test")
        }

        @Test("stops invoking a listener after unsubscribe")
        func unsubscribe() async {
            let sut = track(PostHogSDK.with(config))
            var count = 0
            let subscription = sut.onFeatureFlags { _ in count += 1 }

            subscription.unsubscribe()
            await reload(sut)

            #expect(count == 0)
        }

        @Test("reports errorsLoading with the last known flags when the request fails")
        func errorsLoading() async {
            let sut = track(PostHogSDK.with(config))
            await reload(sut)

            server.flagsResponseHandler = { _ in
                HTTPStubsResponse(jsonObject: [], statusCode: 500, headers: nil)
            }
            var received: [PostHogFeatureFlagsLoaded] = []
            sut.onFeatureFlags { received.append($0) }
            await reload(sut)

            // first: replay of the loaded flags on registration; last: the failed reload
            #expect(received.last?.errorsLoading == true)
            #expect(received.last?.variants["string-value"] as? String == "test")
        }

        @Test("a listener registered while a delivery is queued on main ends on the newest values")
        func lateListenerAfterQueuedDelivery() async {
            let sut = track(PostHogSDK.with(config))
            await reload(sut)

            server.flagsResponseHandler = { _ in
                let body: [String: Any] = [
                    "featureFlags": ["string-value": "v2"],
                    "featureFlagPayloads": [String: Any](),
                    "errorsWhileComputingFlags": false,
                ]
                return HTTPStubsResponse(jsonObject: body, statusCode: 200, headers: nil)
            }
            // Hold main so the reload's delivery is still queued when the listener registers
            let mainBlocked = DispatchSemaphore(value: 0)
            DispatchQueue.main.async { _ = mainBlocked.wait(timeout: .now() + 5) }

            var received: [PostHogFeatureFlagsLoaded] = []
            await withCheckedContinuation { continuation in
                sut.reloadFeatureFlags {
                    sut.onFeatureFlags { received.append($0) }
                    mainBlocked.signal()
                    continuation.resume()
                }
            }
            await MainActor.run {}

            #expect(received.last?.variants["string-value"] as? String == "v2")
        }

        @Test("a listener registered before setup receives bootstrap flags when setup runs off main")
        func bootstrapOffMain() async {
            // An instance with no flag state; listeners survive close() and setup()
            let sut = track(PostHogSDK.with(config))
            sut.close()

            var received: [PostHogFeatureFlagsLoaded] = []
            sut.onFeatureFlags { received.append($0) }

            await withCheckedContinuation { continuation in
                DispatchQueue.global().async {
                    sut.setup(self.makeBootstrapConfig())
                    continuation.resume()
                }
            }
            await MainActor.run {}

            #expect(received.contains { $0.variants["beta-ui"] as? Bool == true && !$0.errorsLoading })
        }

        @Test("a listener registered right after setup on main receives bootstrap flags once")
        func bootstrapOnMainDeliveredOnce() async {
            let sut = track(PostHogSDK.with(config))
            sut.close()

            // setup() and registration in the same main-thread turn, as in didFinishLaunching
            var received: [PostHogFeatureFlagsLoaded] = []
            await withCheckedContinuation { continuation in
                DispatchQueue.main.async {
                    sut.setup(self.makeBootstrapConfig())
                    sut.onFeatureFlags { received.append($0) }
                    continuation.resume()
                }
            }
            await MainActor.run {}
            await MainActor.run {}

            #expect(received.count == 1)
            #expect(received.first?.variants["beta-ui"] as? Bool == true)
        }

        @Test("does not replay the previous user's flags after reset")
        func noReplayAfterReset() async {
            let sut = track(PostHogSDK.with(config))
            await reload(sut)

            // Skip the reload that reset() starts, so only the cleared cache is observed
            sut.remoteConfig?.canReloadFlagsForTesting = false
            sut.reset()

            var received: [PostHogFeatureFlagsLoaded] = []
            sut.onFeatureFlags { received.append($0) }
            await MainActor.run {}

            #expect(received.isEmpty)
        }

        @Test("drops a delivery queued before reset")
        func dropsDeliveryQueuedBeforeReset() async {
            let sut = track(PostHogSDK.with(config))
            await reload(sut)

            var received: [PostHogFeatureFlagsLoaded] = []
            sut.onFeatureFlags { received.append($0) }
            await MainActor.run {}
            let before = received.count

            // Hold main so the reload's delivery is still queued when reset() clears the flags
            let mainBlocked = DispatchSemaphore(value: 0)
            DispatchQueue.main.async { _ = mainBlocked.wait(timeout: .now() + 5) }
            await withCheckedContinuation { continuation in
                sut.reloadFeatureFlags {
                    sut.remoteConfig?.canReloadFlagsForTesting = false
                    sut.reset()
                    sut.onFeatureFlags { received.append($0) }
                    mainBlocked.signal()
                    continuation.resume()
                }
            }
            await MainActor.run {}

            #expect(received.count == before)
        }

        /// Stubs `/flags` so the first response is held until `gate` is signalled and carries
        /// `string-value: "previous-user"`; every later response carries `"new-user"`. `onLaterRequest`
        /// runs when a later request reaches the server, before it is answered.
        private func stubHeldFirstFlagsResponse(gate: DispatchSemaphore, onLaterRequest: @escaping () -> Void = {}) {
            let lock = NSLock()
            var requests = 0
            server.flagsResponseHandler = { _ in
                let count = lock.withLock {
                    requests += 1
                    return requests
                }
                if count == 1 {
                    _ = gate.wait(timeout: .now() + 5)
                } else {
                    onLaterRequest()
                }
                let body: [String: Any] = [
                    "featureFlags": ["string-value": count == 1 ? "previous-user" : "new-user"],
                    "featureFlagPayloads": [String: Any](),
                    "errorsWhileComputingFlags": false,
                ]
                return HTTPStubsResponse(jsonObject: body, statusCode: 200, headers: nil)
            }
        }

        /// Starts a reload whose `/flags` response is held, calls `reset()` with the post-reset reload
        /// skipped, then releases the held response and waits for the main-queue deliveries.
        private func reloadAcrossResetWithoutReload(_ sut: PostHogSDK) async {
            let gate = DispatchSemaphore(value: 0)
            stubHeldFirstFlagsResponse(gate: gate)

            await withCheckedContinuation { continuation in
                sut.remoteConfig?.reloadFeatureFlags { _ in continuation.resume() }
                // Skip the reload that reset() starts, so only the held response could reach a listener
                sut.remoteConfig?.canReloadFlagsForTesting = false
                sut.reset()
                gate.signal()
            }
            await MainActor.run {}
        }

        @Test("drops a load in flight across reset() and delivers the reload reset() started")
        func dropsLoadInFlightAcrossReset() async {
            let sut = track(PostHogSDK.with(config))
            let gate = DispatchSemaphore(value: 0)
            nonisolated(unsafe) var resetReloadSent = false
            nonisolated(unsafe) var cachedWhenResetReloadSent: [String: Any]?
            stubHeldFirstFlagsResponse(gate: gate) {
                // The held response has been handled by the time reset()'s queued reload goes out
                resetReloadSent = true
                cachedWhenResetReloadSent = sut.remoteConfig?.getFeatureFlags()
            }
            var received: [PostHogFeatureFlagsLoaded] = []
            sut.onFeatureFlags { received.append($0) }

            let heldLoadFlags = await withCheckedContinuation { continuation in
                sut.remoteConfig?.reloadFeatureFlags { continuation.resume(returning: $0) }
                sut.reset()
                gate.signal()
            }
            await MainActor.run {}

            #expect(resetReloadSent)
            #expect(cachedWhenResetReloadSent?["string-value"] == nil, "the dropped response must not write the cache")
            #expect(received.map { $0.variants["string-value"] as? String } == ["new-user"])
            #expect(heldLoadFlags?["string-value"] as? String == "new-user")
            #expect(sut.getFeatureFlag("string-value") as? String == "new-user")
        }

        @Test("does not replay a load dropped by reset() to a listener registered afterwards")
        func noReplayOfLoadDroppedByReset() async {
            let sut = track(PostHogSDK.with(config))
            await reloadAcrossResetWithoutReload(sut)

            var received: [PostHogFeatureFlagsLoaded] = []
            sut.onFeatureFlags { received.append($0) }
            await MainActor.run {}

            #expect(received.isEmpty)
            #expect(sut.remoteConfig?.getFeatureFlags()?["string-value"] == nil)
        }

        @Test("does not post didReceiveFeatureFlags for a load dropped by reset()")
        func noNotificationForLoadDroppedByReset() async {
            let sut = track(PostHogSDK.with(config))
            // The notification is global (object: nil), so record this SDK's flags at each post rather
            // than counting posts, which an earlier test's SDK could also make.
            let lock = NSLock()
            var flagsAtPost: [String?] = []
            let observer = NotificationCenter.default.addObserver(
                forName: PostHogSDK.didReceiveFeatureFlags, object: nil, queue: nil
            ) { _ in
                let value = sut.remoteConfig?.getFeatureFlags()?["string-value"] as? String
                lock.withLock { flagsAtPost.append(value) }
            }
            defer { NotificationCenter.default.removeObserver(observer) }

            await reloadAcrossResetWithoutReload(sut)

            #expect(!lock.withLock { flagsAtPost }.contains("previous-user"))
        }

        @Test("does not call a listener unsubscribed by another listener during the same delivery")
        func unsubscribedDuringDelivery() async {
            let sut = track(PostHogSDK.with(config))
            var subscriptionA: PostHogFeatureFlagsSubscription?
            var subscriptionB: PostHogFeatureFlagsSubscription?
            var countA = 0
            var countB = 0
            // Whichever runs first unsubscribes the other, so exactly one of them is called
            subscriptionA = sut.onFeatureFlags { _ in
                countA += 1
                subscriptionB?.unsubscribe()
            }
            subscriptionB = sut.onFeatureFlags { _ in
                countB += 1
                subscriptionA?.unsubscribe()
            }

            await reload(sut)

            #expect(countA + countB == 1)
        }

        @Test("does not deliver an update to the remaining listeners after a listener calls reset()")
        func resetFromListener() async {
            let sut = track(PostHogSDK.with(config))
            var countA = 0
            var countB = 0
            var didReset = false
            // Whichever runs first resets, so the other must not get the invalidated update
            let resetOnce = {
                guard !didReset else { return }
                didReset = true
                sut.remoteConfig?.canReloadFlagsForTesting = false
                sut.reset()
            }
            sut.onFeatureFlags { _ in
                countA += 1
                resetOnce()
            }
            sut.onFeatureFlags { _ in
                countB += 1
                resetOnce()
            }

            await reload(sut)
            #expect(countA + countB == 1)

            sut.remoteConfig?.canReloadFlagsForTesting = true
            await reload(sut)
            #expect(countA + countB == 3)
        }

        @Test("does not deliver an update to the remaining listeners after a listener calls close()")
        func closeFromListener() async {
            let sut = track(PostHogSDK.with(config))
            var countA = 0
            var countB = 0
            var didClose = false
            let closeOnce = {
                guard !didClose else { return }
                didClose = true
                sut.close()
            }
            sut.onFeatureFlags { _ in
                countA += 1
                closeOnce()
            }
            sut.onFeatureFlags { _ in
                countB += 1
                closeOnce()
            }

            await reload(sut)
            #expect(countA + countB == 1)

            sut.setup(config)
            await reload(sut)
            #expect(countA + countB == 3)
        }

        @Test("keeps errorsLoading from a failed load when the bootstrap notification arrives after it")
        func bootstrapAfterFailureKeepsErrorsLoading() async {
            let sut = track(PostHogSDK.with(makeBootstrapConfig()))
            var received: [PostHogFeatureFlagsLoaded] = []
            sut.onFeatureFlags { received.append($0) }
            await MainActor.run {}

            server.flagsResponseHandler = { _ in
                HTTPStubsResponse(jsonObject: [], statusCode: 500, headers: nil)
            }
            await reload(sut)
            #expect(received.last?.errorsLoading == true)

            // A startup failure can reach listeners before the deferred bootstrap notification
            sut.remoteConfig?.bootstrapNotifyPending = true
            sut.remoteConfig?.notifyBootstrappedFlagsIfSeeded()
            await MainActor.run {}

            #expect(received.last?.errorsLoading == true)
            #expect(received.last?.variants["beta-ui"] as? Bool == true)

            let replayed = await withCheckedContinuation { continuation in
                sut.onFeatureFlags { continuation.resume(returning: $0) }
            }
            #expect(replayed.errorsLoading == true)
        }

        private func makeBootstrapConfig() -> PostHogConfig {
            let config = PostHogConfig(projectToken: "test_project_token", host: "http://localhost:9001")
            config.preloadFeatureFlags = false
            config.disableReachabilityForTesting = true
            config.disableQueueTimerForTesting = true
            config.disableFlushOnBackgroundForTesting = true
            config.disableRemoteConfigForTesting = true
            config.bootstrap = PostHogBootstrapConfig(featureFlags: ["beta-ui": true], featureFlagPayloads: nil)
            return config
        }
    }
}
