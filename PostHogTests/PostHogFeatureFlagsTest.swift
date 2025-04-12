//
//  PostHogFeatureFlagsTest.swift
//  PostHog
//
//  Created by Yiannis Josephides on 20/01/2025.
//

@testable import PostHog
import Testing
import XCTest

@Suite("Test Feature Flags", .serialized)
enum PostHogFeatureFlagsTest {
    class BaseTestClass {
        let config = PostHogConfig(apiKey: testAPIKey, host: "http://localhost:9001")
        var server: MockPostHogServer!

        init() {
            server = MockPostHogServer(version: 4)
            server.start()
            // important!
            let storage = PostHogStorage(config)
            storage.reset()
        }

        deinit {
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
            return PostHogRemoteConfig(theConfig, theStorage, api)
        }
    }

    @Suite("Test isFeatureEnabled()")
    class TestIsFeatureFlagEnabled: BaseTestClass {
        @Test("Returns true for enabled Bool flag")
        func testReturnsTrueBoolean() async {
            let sut = getSut()

            await withCheckedContinuation { continuation in
                sut.loadFeatureFlags(distinctId: "distinctId", anonymousId: "anonymousId", groups: ["group": "value"], callback: { _ in
                    continuation.resume()
                })
            }

            #expect(sut.isFeatureEnabled("bool-value") == true)
        }

        @Test("Returns true for enabled String flag")
        func testReturnsTrueString() async {
            let sut = getSut()

            await withCheckedContinuation { continuation in
                sut.loadFeatureFlags(distinctId: "distinctId", anonymousId: "anonymousId", groups: ["group": "value"], callback: { _ in
                    continuation.resume()
                })
            }

            #expect(sut.isFeatureEnabled("string-value") == true)
        }

        @Test("Returns false for disabled flag")
        func testReturnsFalseDisabled() async {
            let sut = getSut()

            await withCheckedContinuation { continuation in
                sut.loadFeatureFlags(distinctId: "distinctId", anonymousId: "anonymousId", groups: ["group": "value"], callback: { _ in
                    continuation.resume()
                })
            }

            #expect(sut.isFeatureEnabled("disabled-flag") == false)
        }
    }

    @Suite("Test getFeatureFlag")
    class TestGetFeatureFlagValue: BaseTestClass {
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

            #expect(sut.isFeatureEnabled("new-flag") == true)
            #expect(sut.isFeatureEnabled("bool-value") == true)
        }

        @Test("clears feature flags when quota limited")
        func clearsFeatureFlagsWhenQuotaLimited() async {
            let sut = getSut()

            // First load some feature flags normally
            await withCheckedContinuation { continuation in
                sut.loadFeatureFlags(distinctId: "distinctId", anonymousId: "anonymousId", groups: ["group": "value"], callback: { _ in
                    continuation.resume()
                })
            }

            // Verify flags are loaded
            #expect(sut.isFeatureEnabled("bool-value") == true)
            #expect(sut.getFeatureFlag("string-value") as? String == "test")

            // Now set the server to return quota limited response
            server.quotaLimitFeatureFlags = true

            // Load flags again, this time with quota limiting
            await withCheckedContinuation { continuation in
                sut.loadFeatureFlags(distinctId: "distinctId", anonymousId: "anonymousId", groups: ["group": "value"], callback: { _ in
                    continuation.resume()
                })
            }

            // Verify flags are cleared
            #expect(sut.isFeatureEnabled("bool-value") == false)
            #expect(sut.getFeatureFlag("string-value") == nil)
        }
    }
}
