//
//  PostHogConfigTest.swift
//  PostHogTests
//
//  Created by Manoel Aranda Neto on 30.10.23.
//

import Foundation
@_spi(PostHogInternal) @testable import PostHog
import Testing

@Suite("PostHogConfig", .serialized, .resetsGlobalState)
struct PostHogConfigTest {
    @Test("init config with default values")
    func initConfigWithDefaultValues() {
        let config = PostHogConfig(projectToken: testProjectToken)

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
        #expect(config.persistOptOut == true)

        #if os(iOS) || os(macOS)
            #expect(config.capturePushNotificationSubscriptions == true)
            #expect(config.capturePushNotificationOpened == true)
        #endif
        #expect(config.pushIdentityProvider == nil)
    }

    @Test("init takes project token")
    func initTakesProjectToken() {
        let config = PostHogConfig(projectToken: testProjectToken)

        #expect(config.projectToken == testProjectToken)
        #expect(config.apiKey == testProjectToken)
    }

    @Test("deprecated init(apiKey:) maps to project token")
    func deprecatedInitApiKeyMapsToProjectToken() {
        let config = PostHogConfig(apiKey: testProjectToken)

        #expect(config.projectToken == testProjectToken)
        #expect(config.apiKey == testProjectToken)
        #expect(config.host == URL(string: PostHogConfig.defaultHost))
    }

    @Test("deprecated init(apiKey:host:) maps to project token and host")
    func deprecatedInitApiKeyHostMapsToProjectTokenAndHost() throws {
        let config = PostHogConfig(apiKey: testProjectToken, host: "localhost:9000")

        #expect(config.projectToken == testProjectToken)
        #expect(config.apiKey == testProjectToken)
        #expect(config.host == (try #require(URL(string: "localhost:9000"))))
    }

    @Test("deprecated init(apiKey:host:) trims whitespace-sensitive values")
    func deprecatedInitApiKeyHostTrimsWhitespace() {
        let config = PostHogConfig(
            apiKey: " \n\(testProjectToken)\t ",
            host: " \nhttps://eu.i.posthog.com/\t "
        )

        #expect(config.projectToken == testProjectToken)
        #expect(config.apiKey == testProjectToken)
        #expect(config.host == URL(string: "https://eu.i.posthog.com/"))
    }

    @Test("trims whitespace-sensitive config values")
    func trimsWhitespaceSensitiveConfigValues() {
        let config = PostHogConfig(
            projectToken: " \n\(testProjectToken)\t ",
            host: " \nhttps://eu.i.posthog.com/\t "
        )

        #expect(config.projectToken == testProjectToken)
        #expect(config.apiKey == testProjectToken)
        #expect(config.host == URL(string: "https://eu.i.posthog.com/"))
    }

    @Test("defaults a blank host after trimming whitespace")
    func defaultsBlankHostAfterTrimmingWhitespace() {
        let config = PostHogConfig(projectToken: testProjectToken, host: " \n\t ")

        #expect(config.host == URL(string: PostHogConfig.defaultHost))
    }

    @Test("init takes host")
    func initTakesHost() throws {
        let config = PostHogConfig(projectToken: testProjectToken, host: "localhost:9000")

        #expect(config.host == (try #require(URL(string: "localhost:9000"))))
    }

    #if os(iOS)
        @Suite("when initialized with default values for captureElementInteractions")
        struct DefaultCaptureElementInteractions {
            @Test("should disable autocapture by default")
            func shouldDisableAutocaptureByDefault() {
                let sut = PostHogConfig(projectToken: testProjectToken)
                #expect(!sut.captureElementInteractions)
            }
        }

        @Suite("when initialized with default tracing headers configuration")
        struct DefaultTracingHeaders {
            @Test("should disable tracing headers by default")
            func shouldDisableTracingHeadersByDefault() {
                let sut = PostHogConfig(projectToken: testProjectToken)
                #expect(sut.tracingHeaders == nil)
            }
        }

        @Suite("when customized")
        struct WhenCustomized {
            @Test("should allow disabling autocapture")
            func shouldAllowDisablingAutocapture() {
                let config = PostHogConfig(projectToken: testProjectToken)
                config.captureElementInteractions = false
                #expect(!config.captureElementInteractions)
            }
        }
    #endif
}
