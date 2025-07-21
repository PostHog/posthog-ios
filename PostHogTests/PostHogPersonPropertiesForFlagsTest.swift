//
//  PostHogPersonPropertiesForFlagsTest.swift
//  PostHog
//
//  Created by PostHog SDK on 2025-07-21.
//

@testable import PostHog
import Testing
import XCTest

@Suite("Test Person Properties for Flags", .serialized)
enum PostHogPersonPropertiesForFlagsTest {
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
        
        func getSDKSut(
            storage: PostHogStorage? = nil,
            config: PostHogConfig? = nil
        ) -> PostHogSDK {
            let theConfig = config ?? self.config
            theConfig.captureScreenViews = false
            theConfig.preloadFeatureFlags = false
            theConfig.sendFeatureFlagEvent = false
            
            let sut = PostHogSDK.shared
            sut.setup(theConfig)
            return sut
        }
    }

    @Suite("Test RemoteConfig Person Properties Methods")
    class TestRemoteConfigPersonProperties: BaseTestClass {
        @Test("setPersonPropertiesForFlags stores properties correctly")
        func storesPersonPropertiesCorrectly() async {
            let sut = getSut()
            let properties = ["app_version": "2.93.0", "user_type": "premium"]
            
            sut.setPersonPropertiesForFlags(properties)
            
            // Test that properties are stored by triggering a flag request
            await withCheckedContinuation { continuation in
                sut.loadFeatureFlags(distinctId: "test_user", anonymousId: nil, groups: [:], callback: { _ in
                    continuation.resume()
                })
            }
            
            // Verify the API was called with person_properties
            let lastRequest = server.getLastRequest()
            #expect(lastRequest != nil)
            #expect(lastRequest!.url?.path == "/flags")
            
            // Parse the request body
            let requestData = lastRequest!.httpBody
            #expect(requestData != nil)
            
            let json = try! JSONSerialization.jsonObject(with: requestData!, options: []) as! [String: Any]
            let personProps = json["person_properties"] as? [String: Any]
            
            #expect(personProps != nil)
            #expect(personProps!["app_version"] as? String == "2.93.0")
            #expect(personProps!["user_type"] as? String == "premium")
        }
        
        @Test("setPersonPropertiesForFlags merges properties additively")
        func mergesPropertiesAdditively() async {
            let sut = getSut()
            
            // Set first batch of properties
            sut.setPersonPropertiesForFlags(["app_version": "2.93.0"])
            // Set second batch of properties
            sut.setPersonPropertiesForFlags(["user_type": "premium"])
            
            await withCheckedContinuation { continuation in
                sut.loadFeatureFlags(distinctId: "test_user", anonymousId: nil, groups: [:], callback: { _ in
                    continuation.resume()
                })
            }
            
            let lastRequest = server.getLastRequest()
            let requestData = lastRequest!.httpBody!
            let json = try! JSONSerialization.jsonObject(with: requestData, options: []) as! [String: Any]
            let personProps = json["person_properties"] as? [String: Any]
            
            #expect(personProps != nil)
            #expect(personProps!["app_version"] as? String == "2.93.0")
            #expect(personProps!["user_type"] as? String == "premium")
        }
        
        @Test("resetPersonPropertiesForFlags clears all properties")
        func clearsAllProperties() async {
            let sut = getSut()
            
            // Set properties
            sut.setPersonPropertiesForFlags(["app_version": "2.93.0", "user_type": "premium"])
            
            // Reset properties
            sut.resetPersonPropertiesForFlags()
            
            await withCheckedContinuation { continuation in
                sut.loadFeatureFlags(distinctId: "test_user", anonymousId: nil, groups: [:], callback: { _ in
                    continuation.resume()
                })
            }
            
            let lastRequest = server.getLastRequest()
            let requestData = lastRequest!.httpBody!
            let json = try! JSONSerialization.jsonObject(with: requestData, options: []) as! [String: Any]
            let personProps = json["person_properties"]
            
            // person_properties should be nil when empty
            #expect(personProps == nil)
        }
    }

    @Suite("Test SDK Person Properties Integration")
    class TestSDKPersonPropertiesIntegration: BaseTestClass {
        @Test("setPersonPropertiesForFlags API with default reload")
        func setsPersonPropertiesWithDefaultReload() async {
            let sut = getSDKSut()
            
            sut.setPersonPropertiesForFlags(["app_version": "2.93.0"])
            
            // Wait for the flag reload to complete
            await withCheckedContinuation { continuation in
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    continuation.resume()
                }
            }
            
            let lastRequest = server.getLastRequest()
            #expect(lastRequest?.url?.path == "/flags")
        }
        
        @Test("setPersonPropertiesForFlags API without reload")
        func setsPersonPropertiesWithoutReload() async {
            let sut = getSDKSut()
            
            sut.setPersonPropertiesForFlags(["app_version": "2.93.0"], reloadFeatureFlags: false)
            
            // Give a moment for any potential async operations
            await withCheckedContinuation { continuation in
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    continuation.resume()
                }
            }
            
            // Should not have triggered a flags request
            let lastRequest = server.getLastRequest()
            #expect(lastRequest?.url?.path != "/flags" || lastRequest == nil)
        }
        
        @Test("identify automatically sets person properties for flags")
        func identifyAutomaticallySetsPersonProperties() async {
            let sut = getSDKSut()
            
            sut.identify("test_user", userProperties: ["app_version": "2.93.0", "plan": "premium"])
            
            // Wait for flag reload triggered by identify
            await withCheckedContinuation { continuation in
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    continuation.resume()
                }
            }
            
            let lastRequest = server.getLastRequest()
            #expect(lastRequest?.url?.path == "/flags")
            
            let requestData = lastRequest!.httpBody!
            let json = try! JSONSerialization.jsonObject(with: requestData, options: []) as! [String: Any]
            let personProps = json["person_properties"] as? [String: Any]
            
            #expect(personProps != nil)
            #expect(personProps!["app_version"] as? String == "2.93.0")
            #expect(personProps!["plan"] as? String == "premium")
        }
        
        @Test("reset clears person properties for flags")
        func resetClearsPersonProperties() async {
            let sut = getSDKSut()
            
            // Set properties
            sut.setPersonPropertiesForFlags(["app_version": "2.93.0"])
            
            // Reset
            sut.reset()
            
            // Wait for flag reload triggered by reset
            await withCheckedContinuation { continuation in
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    continuation.resume()
                }
            }
            
            let lastRequest = server.getLastRequest()
            #expect(lastRequest?.url?.path == "/flags")
            
            let requestData = lastRequest!.httpBody!
            let json = try! JSONSerialization.jsonObject(with: requestData, options: []) as! [String: Any]
            let personProps = json["person_properties"]
            
            // person_properties should be nil when empty
            #expect(personProps == nil)
        }
    }

    @Suite("Test Thread Safety")
    class TestThreadSafety: BaseTestClass {
        @Test("concurrent access to person properties is thread-safe")
        func concurrentAccessIsThreadSafe() async {
            let sut = getSut()
            
            await withTaskGroup(of: Void.self) { group in
                // Launch multiple tasks that set properties concurrently
                for i in 0..<10 {
                    group.addTask {
                        sut.setPersonPropertiesForFlags(["property_\(i)": "value_\(i)"])
                    }
                }
                
                // Launch a task that resets properties
                group.addTask {
                    sut.resetPersonPropertiesForFlags()
                }
                
                // Wait for all tasks to complete
                await group.waitForAll()
            }
            
            // Test should complete without crashes (thread safety verified)
        }
    }
}