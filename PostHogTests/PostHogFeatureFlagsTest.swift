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
            return PostHogRemoteConfig(theConfig, theStorage, api) { [:] }
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

            // Verify flags are cleared
            #expect(sut.getFeatureFlag("bool-value") == nil)
            #expect(sut.getFeatureFlag("string-value") == nil)
        }
    }

    @Suite("Test Person and Group Properties for Flags")
    class TestPersonAndGroupPropertiesForFlags: BaseTestClass {
        @Test("Person properties are stored and retrieved correctly")
        func storeAndRetrievePersonProperties() async {
            let sut = PostHogSDK.with(config)

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
            let sut = PostHogSDK.with(config)

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
        func resetPersonPropertiesClearsAll() async {
            let sut = PostHogSDK.with(config)

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
            if let personProperties = requestBody["person_properties"] as? [String: Any] {
                #expect(personProperties["property1"] == nil, "Expected property1 to be removed after reset")
                #expect(personProperties["property2"] == nil, "Expected property2 to be removed after reset")
                // Device properties like $device_manufacturer, $os_name etc. are expected to remain
            }
        }

        @Test("Group properties are stored and retrieved correctly")
        func storeAndRetrieveGroupProperties() async {
            let sut = PostHogSDK.with(config)

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
            let sut = PostHogSDK.with(config)

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
            let sut = PostHogSDK.with(config)

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
            let sut = PostHogSDK.with(config)

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
            let sut = PostHogSDK.with(config)

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
            let sut = PostHogSDK.with(config)

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

        @Test("Group with groupProperties automatically sets group properties for flags")
        func groupWithGroupPropertiesAutomaticallySetsGroupPropertiesForFlags() async {
            let sut = PostHogSDK.with(config)

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

    @Suite("Test Evaluation Contexts")
    class TestEvaluationContexts: BaseTestClass {
        @Test("Evaluation contexts are included in flags request")
        func evaluationContextsIncludedInRequest() async {
            // Configure evaluation contexts
            config.evaluationContexts = ["production", "web", "checkout"]
            let sut = PostHogSDK.with(config)

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
            let sut = PostHogSDK.with(config)

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
            let sut = PostHogSDK.with(config)

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
            let sut = PostHogSDK.with(config)

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
    }
}
