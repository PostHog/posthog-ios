//
//  PostHogConfigTest.swift
//  PostHogTests
//
//  Created by Manoel Aranda Neto on 30.10.23.
//

import Foundation
@testable import PostHog
import Testing

@Suite("PostHogConfig Tests")
struct PostHogConfigTest {
    @Test("init config with default values")
    func initConfigWithDefaultValues() {
        let config = PostHogConfig(apiKey: testAPIKey)

        #expect(config.host == URL(string: PostHogConfig.defaultHost))
        #expect(config.flushAt == 20)
        #expect(config.maxQueueSize == 1000)
        #expect(config.maxBatchSize == 50)
        #expect(config.flushIntervalSeconds == 30)
        #expect(config.dataMode == .any)
        #expect(config.sendFeatureFlagEvent == true)
        #expect(config.preloadFeatureFlags == true)
        #expect(config.captureApplicationLifecycleEvents == true)
        #expect(config.captureScreenViews == true)
        #expect(config.debug == false)
        #expect(config.optOut == false)
    }

    @Test("init takes api key")
    func initTakesApiKey() {
        let config = PostHogConfig(apiKey: testAPIKey)

        #expect(config.apiKey == testAPIKey)
    }

    @Test("init takes host")
    func initTakesHost() {
        let config = PostHogConfig(apiKey: testAPIKey, host: "localhost:9000")

        #expect(config.host == URL(string: "localhost:9000")!)
    }

    #if os(iOS)
        @Suite("when initialized with default values for captureElementInteractions")
        struct DefaultCaptureElementInteractions {
            @Test("should have autocapture disabled by default")
            func shouldHaveAutocaptureDisabledByDefault() {
                let sut = PostHogConfig(apiKey: testAPIKey)
                #expect(sut.captureElementInteractions == false)
            }
        }

        @Suite("when customized")
        struct WhenCustomized {
            @Test("should allow disabling autocapture")
            func shouldAllowDisablingAutocapture() {
                let config = PostHogConfig(apiKey: testAPIKey)
                config.captureElementInteractions = false
                #expect(config.captureElementInteractions == false)
            }
        }
    #endif
}
