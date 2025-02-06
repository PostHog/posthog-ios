//
//  PostHogSDKInstanceTest.swift
//  PostHog
//
//  Created by Yiannis Josephides on 04/02/2025.
//

import Dispatch
import Testing

@testable import PostHog

@Suite("PostHogSDK instance creation", .serialized)
class PostHogSDKInstanceTest {
    
    init() {
        PostHogSDK.clearInstanceKeysForTesting()
    }
    
    @Test("When creating an instance with the same API key, the same instance is returned")
    func whenCreatingAnInstanceWithTheSameAPIKeyTheSameInstanceIsReturned() {
        let apiKey = "tc1_same_key_1"
        let sharedInstance = PostHogSDK.shared

        let config = PostHogConfig(apiKey: apiKey)
        PostHogSDK.shared.setup(PostHogConfig(apiKey: apiKey))
        let instance = PostHogSDK.with(config)

        #expect(instance === sharedInstance)
    }

    @Test("When creating an instance with a different API key, a new instance is returned")
    func whenCreatingAnInstanceWithADifferentAPIKeyANewInstanceIsReturned() {
        let apiKey1 = "tc2_different_key_1"
        let apiKey2 = "tc2_different_key_2"

        PostHogSDK.shared.setup(PostHogConfig(apiKey: apiKey1))
        let instance = PostHogSDK.with(PostHogConfig(apiKey: apiKey2))

        #expect(instance !== PostHogSDK.shared)
    }

    @Test("Calling .with() with the same API key, will return the same instance")
    func callingWithSameAPIKeyWillReturnSameInstance() {
        let apiKey = "tc3_same_key_1"

        let instance1 = PostHogSDK.with(PostHogConfig(apiKey: apiKey))
        let instance2 = PostHogSDK.with(PostHogConfig(apiKey: apiKey))
        let instance3 = PostHogSDK.with(PostHogConfig(apiKey: apiKey))

        #expect(instance1 === instance2)
        #expect(instance1 === instance3)
    }

    @Test("Creating an instance with the same api key, after the first instance is released, leads to a new instance created")
    func whenCreatingAnInstanceWithTheSameAPIKeyAfterFirstInstanceIsReleasedLeadsToANewInstanceCreated() async throws {
        let apiKey = "tc4_same_key_1"

        var instance1: PostHogSDK? = PostHogSDK.with(PostHogConfig(apiKey: apiKey))
        let instance1Identifier = ObjectIdentifier(instance1!)

        instance1 = nil

        // Need to look into this, we need to give some time to dealloc.
        // Probably holding a strong reference in a timer or something
        try await Task.sleep(nanoseconds: 1 * NSEC_PER_SEC)

        let instance2 = PostHogSDK.with(PostHogConfig(apiKey: apiKey))
        let instance2Identifier = ObjectIdentifier(instance2)
        

        #expect(instance1Identifier != instance2Identifier)
    }

    @Test("Creating an instance with the same key concurrently, won't crash the app")
    func whenCreatingAnInstanceWithTheSameAPIKeyWillNotCrashTheApp() {
        let apiKey = "tc5_same_key_1"
        let iterationCount = 1_000
        var instances = [PostHogSDK?](repeating: nil, count: iterationCount)

        DispatchQueue.concurrentPerform(iterations: iterationCount) { index in
            instances[index] = PostHogSDK.with(PostHogConfig(apiKey: apiKey))
        }

        // All instances should reference the same object
        let uniqueInstances = Set(instances.compactMap { ObjectIdentifier($0!) })
        #expect(uniqueInstances.count == 1)
    }

    @Test("Creating an instance with a different key concurrently, won't crash the app")
    func creatingAnInstanceWithADifferentKeyConcurrentlyWillNotCrashTheApp() {
        let iterationCount = 1_000
        var instances = [PostHogSDK?](repeating: nil, count: iterationCount)

        DispatchQueue.concurrentPerform(iterations: iterationCount) { index in
            let apiKey = "tc6_different_key_\(index)"
            instances[index] = PostHogSDK.with(PostHogConfig(apiKey: apiKey))
        }

        // Verify all instances are unique using object identifiers
        let uniqueInstances = Set(instances.compactMap { ObjectIdentifier($0!) })
        #expect(uniqueInstances.count == instances.count)
    }
}
