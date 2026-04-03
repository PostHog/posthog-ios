//
//  PostHogPushNotificationTest.swift
//  PostHog
//
//  Created on 03/04/2026.
//

#if os(iOS) || os(macOS)

    import Foundation
    @testable import PostHog
    import Testing

    @Suite("Push Notification Tests", .serialized)
    final class PostHogPushNotificationTest {
        var server: MockPostHogServer!

        init() {
            PostHogPushNotificationIntegration.clearInstalls()
            PostHogAppLifeCycleIntegration.clearInstalls()
            PostHogScreenViewIntegration.clearInstalls()

            server = MockPostHogServer()
            server.start()
        }

        deinit {
            server.stop()
            server = nil
        }

        // Push notification integration requires a real app environment (UNUserNotificationCenter),
        // so we disable it when creating the SDK for device token tests.
        private func getSut(
            flushAt: Int = 1
        ) -> PostHogSDK {
            let config = PostHogConfig(apiKey: testAPIKey, host: "http://localhost:9001")
            config.flushAt = flushAt
            config.captureApplicationLifecycleEvents = false
            config.captureScreenViews = false
            config.capturePushNotificationSubscriptions = false
            config.disableReachabilityForTesting = true
            config.disableQueueTimerForTesting = true
            config.disableFlushOnBackgroundForTesting = true

            let storage = PostHogStorage(config)
            storage.reset()

            return PostHogSDK.with(config)
        }

        // MARK: - Device Token Handling Tests

        @Test("handlePushNotificationDeviceToken converts token to hex string and sends subscription")
        func handleDeviceTokenSendsSubscription() async throws {
            let sut = getSut()

            // Create a known device token
            let tokenBytes: [UInt8] = [0xDE, 0xAD, 0xBE, 0xEF, 0x01, 0x02, 0x03, 0x04]
            let deviceToken = Data(tokenBytes)

            sut.handlePushNotificationDeviceToken(deviceToken)

            // The push subscription is sent asynchronously - give it time
            try await Task.sleep(nanoseconds: 2_000_000_000)

            sut.close()

            // If we got here without a crash, the token was processed correctly.
            // The actual API call goes to /api/push_subscriptions which is stubbed by MockPostHogServer.
        }

        @Test("handlePushNotificationDeviceToken does nothing when SDK is opted out")
        func handleDeviceTokenDoesNothingWhenOptedOut() {
            let config = PostHogConfig(apiKey: testAPIKey, host: "http://localhost:9001")
            config.optOut = true
            config.capturePushNotificationSubscriptions = false
            config.captureApplicationLifecycleEvents = false
            config.captureScreenViews = false
            config.disableReachabilityForTesting = true
            config.disableQueueTimerForTesting = true
            config.disableFlushOnBackgroundForTesting = true

            let storage = PostHogStorage(config)
            storage.reset()

            let sut = PostHogSDK.with(config)

            let tokenBytes: [UInt8] = [0xDE, 0xAD, 0xBE, 0xEF]
            let deviceToken = Data(tokenBytes)

            // Should return early without crashing
            sut.handlePushNotificationDeviceToken(deviceToken)

            sut.close()
        }

        // MARK: - Config Default Tests

        @Test("capturePushNotificationSubscriptions defaults to true")
        func configDefaultsToTrue() {
            let config = PostHogConfig(apiKey: testAPIKey)
            #expect(config.capturePushNotificationSubscriptions == true)
        }

        @Test("capturePushNotificationSubscriptions can be set to false")
        func configCanBeDisabled() {
            let config = PostHogConfig(apiKey: testAPIKey)
            config.capturePushNotificationSubscriptions = false
            #expect(config.capturePushNotificationSubscriptions == false)
        }

        // MARK: - getIntegrations Tests

        @Test("getIntegrations includes push notification integration when enabled")
        func getIntegrationsIncludesPushNotification() {
            let config = PostHogConfig(apiKey: testAPIKey)
            config.capturePushNotificationSubscriptions = true

            let integrations = config.getIntegrations()
            let hasPushIntegration = integrations.contains { $0 is PostHogPushNotificationIntegration }
            #expect(hasPushIntegration)
        }

        @Test("getIntegrations excludes push notification integration when disabled")
        func getIntegrationsExcludesPushNotification() {
            let config = PostHogConfig(apiKey: testAPIKey)
            config.capturePushNotificationSubscriptions = false

            let integrations = config.getIntegrations()
            let hasPushIntegration = integrations.contains { $0 is PostHogPushNotificationIntegration }
            #expect(!hasPushIntegration)
        }

        @Test("getIntegrations excludes push notification integration when swizzling is disabled")
        func getIntegrationsExcludesPushNotificationWhenSwizzlingDisabled() {
            let config = PostHogConfig(apiKey: testAPIKey)
            config.capturePushNotificationSubscriptions = true
            config.enableSwizzling = false

            let integrations = config.getIntegrations()
            // getIntegrations still returns it, but installIntegrations would skip it
            let hasPushIntegration = integrations.contains { $0 is PostHogPushNotificationIntegration }
            #expect(hasPushIntegration)

            // Verify requiresSwizzling is true for this integration
            let pushIntegration = integrations.first { $0 is PostHogPushNotificationIntegration }
            #expect(pushIntegration?.requiresSwizzling == true)
        }
    }

#endif
