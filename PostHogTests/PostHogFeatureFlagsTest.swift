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
        func storeAndRetrievePersonProperties() {
            let sut = getSut()
            let properties = [
                "test_property": "test_value",
                "plan": "premium",
                "age": 25,
            ] as [String: Any]

            // Set properties
            sut.setPersonPropertiesForFlags(properties)

            // Verify they can be retrieved by testing the internal state
            // Since getPersonPropertiesForFlags is private, we'll test via flag loading
            let expectation = expectation(description: "Flag loading completed")

            sut.loadFeatureFlags(distinctId: "test_user", anonymousId: nil, groups: [:]) { _ in
                expectation.fulfill()
            }

            wait(for: [expectation], timeout: 1.0)

            // Verify the request included person properties by checking server received data
            #expect(server.flagsRequests.count > 0)
            let lastRequest = server.flagsRequests.last!
            let requestBody = server.parseRequest(lastRequest, gzip: false)

            #expect(requestBody != nil)
            if let personProperties = requestBody?["person_properties"] as? [String: Any] {
                #expect(personProperties["test_property"] as? String == "test_value")
                #expect(personProperties["plan"] as? String == "premium")
                #expect(personProperties["age"] as? Int == 25)
            } else {
                #expect(Bool(false), "Person properties not found in request")
            }
        }

        @Test("Person properties are additive")
        func personPropertiesAreAdditive() {
            let sut = getSut()

            // Set first batch of properties
            sut.setPersonPropertiesForFlags(["property1": "value1", "shared": "original"])

            // Set second batch that overlaps
            sut.setPersonPropertiesForFlags(["property2": "value2", "shared": "updated"])

            let expectation = expectation(description: "Flag loading completed")

            sut.loadFeatureFlags(distinctId: "test_user", anonymousId: nil, groups: [:]) { _ in
                expectation.fulfill()
            }

            wait(for: [expectation], timeout: 1.0)

            #expect(server.flagsRequests.count > 0)
            let lastRequest = server.flagsRequests.last!
            let requestBody = server.parseRequest(lastRequest, gzip: false)
            #expect(requestBody != nil)
            if let personProperties = requestBody?["person_properties"] as? [String: Any] {
                #expect(personProperties["property1"] as? String == "value1")
                #expect(personProperties["property2"] as? String == "value2")
                #expect(personProperties["shared"] as? String == "updated") // Latest wins
            } else {
                #expect(Bool(false), "Person properties not found in request")
            }
        }

        @Test("Reset person properties clears all properties")
        func resetPersonPropertiesClearsAll() {
            let sut = getSut()

            // Set some properties
            sut.setPersonPropertiesForFlags(["property1": "value1", "property2": "value2"])

            // Reset them
            sut.resetPersonPropertiesForFlags()

            let expectation = expectation(description: "Flag loading completed")

            sut.loadFeatureFlags(distinctId: "test_user", anonymousId: nil, groups: [:]) { _ in
                expectation.fulfill()
            }

            wait(for: [expectation], timeout: 1.0)

            #expect(server.flagsRequests.count > 0)
            let lastRequest = server.flagsRequests.last!
            let requestBody = server.parseRequest(lastRequest, gzip: false)
            #expect(requestBody != nil)
            if let requestBody = requestBody {
                #expect(requestBody["person_properties"] == nil)
            }
        }

        @Test("Group properties are stored and retrieved correctly")
        func storeAndRetrieveGroupProperties() {
            let sut = getSut()
            let properties = [
                "plan": "enterprise",
                "seats": 50,
                "industry": "technology",
            ] as [String: Any]

            // Set group properties
            sut.setGroupPropertiesForFlags("organization", properties: properties)

            let expectation = expectation(description: "Flag loading completed")

            sut.loadFeatureFlags(distinctId: "test_user", anonymousId: nil, groups: [:]) { _ in
                expectation.fulfill()
            }

            wait(for: [expectation], timeout: 1.0)

            #expect(server.flagsRequests.count > 0)
            let lastRequest = server.flagsRequests.last!
            let requestBody = server.parseRequest(lastRequest, gzip: false)
            #expect(requestBody != nil)
            if let groupProperties = requestBody?["group_properties"] as? [String: [String: Any]],
               let orgProperties = groupProperties["organization"]
            {
                #expect(orgProperties["plan"] as? String == "enterprise")
                #expect(orgProperties["seats"] as? Int == 50)
                #expect(orgProperties["industry"] as? String == "technology")
            } else {
                #expect(Bool(false), "Group properties not found in request")
            }
        }

        @Test("Multiple group types are handled correctly")
        func multipleGroupTypesHandled() {
            let sut = getSut()

            // Set properties for different group types
            sut.setGroupPropertiesForFlags("organization", properties: ["plan": "enterprise"])
            sut.setGroupPropertiesForFlags("team", properties: ["role": "engineering"])

            let expectation = expectation(description: "Flag loading completed")

            sut.loadFeatureFlags(distinctId: "test_user", anonymousId: nil, groups: [:]) { _ in
                expectation.fulfill()
            }

            wait(for: [expectation], timeout: 1.0)

            #expect(server.flagsRequests.count > 0)
            let lastRequest = server.flagsRequests.last!
            let requestBody = server.parseRequest(lastRequest, gzip: false)
            #expect(requestBody != nil)
            if let groupProperties = requestBody?["group_properties"] as? [String: [String: Any]] {
                #expect(groupProperties["organization"]?["plan"] as? String == "enterprise")
                #expect(groupProperties["team"]?["role"] as? String == "engineering")
            } else {
                #expect(Bool(false), "Group properties not found in request")
            }
        }

        @Test("Reset group properties for specific type")
        func resetGroupPropertiesSpecificType() {
            let sut = getSut()

            // Set properties for multiple group types
            sut.setGroupPropertiesForFlags("organization", properties: ["plan": "enterprise"])
            sut.setGroupPropertiesForFlags("team", properties: ["role": "engineering"])

            // Reset only organization properties
            sut.resetGroupPropertiesForFlags("organization")

            let expectation = expectation(description: "Flag loading completed")

            sut.loadFeatureFlags(distinctId: "test_user", anonymousId: nil, groups: [:]) { _ in
                expectation.fulfill()
            }

            wait(for: [expectation], timeout: 1.0)

            #expect(server.flagsRequests.count > 0)
            let lastRequest = server.flagsRequests.last!
            let requestBody = server.parseRequest(lastRequest, gzip: false)
            #expect(requestBody != nil)
            if let groupProperties = requestBody?["group_properties"] as? [String: [String: Any]] {
                #expect(groupProperties["organization"] == nil)
                #expect(groupProperties["team"]?["role"] as? String == "engineering")
            } else {
                #expect(Bool(false), "Group properties not found in request")
            }
        }

        @Test("Reset all group properties")
        func resetAllGroupProperties() {
            let sut = getSut()

            // Set properties for multiple group types
            sut.setGroupPropertiesForFlags("organization", properties: ["plan": "enterprise"])
            sut.setGroupPropertiesForFlags("team", properties: ["role": "engineering"])

            // Reset all group properties
            sut.resetGroupPropertiesForFlags()

            let expectation = expectation(description: "Flag loading completed")

            sut.loadFeatureFlags(distinctId: "test_user", anonymousId: nil, groups: [:]) { _ in
                expectation.fulfill()
            }

            wait(for: [expectation], timeout: 1.0)

            #expect(server.flagsRequests.count > 0)
            let lastRequest = server.flagsRequests.last!
            let requestBody = server.parseRequest(lastRequest, gzip: false)
            #expect(requestBody != nil)
            if let requestBody = requestBody {
                #expect(requestBody["group_properties"] == nil)
            }
        }

        @Test("Both person and group properties sent together")
        func bothPersonAndGroupPropertiesSent() {
            let sut = getSut()

            // Set both types of properties
            sut.setPersonPropertiesForFlags(["user_plan": "premium"])
            sut.setGroupPropertiesForFlags("organization", properties: ["org_plan": "enterprise"])

            let expectation = expectation(description: "Flag loading completed")

            sut.loadFeatureFlags(distinctId: "test_user", anonymousId: nil, groups: [:]) { _ in
                expectation.fulfill()
            }

            wait(for: [expectation], timeout: 1.0)

            #expect(server.flagsRequests.count > 0)
            let lastRequest = server.flagsRequests.last!
            let requestBody = server.parseRequest(lastRequest, gzip: false)
            #expect(requestBody != nil)
            if let requestBody = requestBody {
                // Check person properties
                if let personProperties = requestBody["person_properties"] as? [String: Any] {
                    #expect(personProperties["user_plan"] as? String == "premium")
                } else {
                    #expect(Bool(false), "Person properties not found")
                }

                // Check group properties
                if let groupProperties = requestBody["group_properties"] as? [String: [String: Any]] {
                    #expect(groupProperties["organization"]?["org_plan"] as? String == "enterprise")
                } else {
                    #expect(Bool(false), "Group properties not found")
                }
            } else {
                #expect(Bool(false), "Request body not found")
            }
        }
    }
}
