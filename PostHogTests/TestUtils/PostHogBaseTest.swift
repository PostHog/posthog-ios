//
//  PostHogBaseTest.swift
//  PostHogTests
//
//  Created by Ioannis Josephides on 13/02/2026.
//

import Foundation
@testable import PostHog
import XCTest

// MARK: - Base class for tests that create PostHogSDK instances

class PostHogSDKBaseTest {
    let server: MockPostHogServer
    let storageTracker = TestStorageTracker()

    init(serverVersion: Int = 3) {
        server = MockPostHogServer(version: serverVersion)
        server.start()
    }

    deinit {
        storageTracker.cleanup()
        server.stop()
    }

    func makeConfig(
        apiKey: String = uniqueApiKey(),
        host: String? = nil
    ) -> PostHogConfig {
        let host = host ?? server.url
        let config = PostHogConfig(apiKey: apiKey, host: host)
        storageTracker.track(config)
        config.disableReachabilityForTesting = true
        config.disableQueueTimerForTesting = true
        config.captureApplicationLifecycleEvents = false
        config.preloadFeatureFlags = false
        config.sendFeatureFlagEvent = false
        return config
    }

    func makeSDK(config: PostHogConfig) -> PostHogSDK {
        let storage = PostHogStorage(config)
        storage.reset()
        return PostHogSDK.with(config)
    }
}

// MARK: - Base class for tests that create PostHogRemoteConfig instances

class PostHogRemoteConfigBaseTest {
    let config: PostHogConfig
    lazy var storage = PostHogStorage(config)
    var server: MockPostHogServer!

    init(serverVersion: Int = 3) {
        server = MockPostHogServer(version: serverVersion)
        config = PostHogConfig(apiKey: uniqueApiKey(), host: server.url)
        config.preloadFeatureFlags = false
        config.remoteConfig = false
        server.start()
        // important!
        storage.reset()
    }

    deinit {
        storage.reset()
        server.stop()
        server = nil
    }

    func getSut(
        storage: PostHogStorage? = nil,
        config: PostHogConfig? = nil,
        configureConfig: ((PostHogConfig) -> Void)? = nil
    ) -> PostHogRemoteConfig {
        let theConfig = config ?? self.config
        configureConfig?(theConfig)
        let theStorage = storage ?? self.storage
        let api = PostHogApi(theConfig)
        return PostHogRemoteConfig(theConfig, theStorage, api) { [:] }
    }
}
