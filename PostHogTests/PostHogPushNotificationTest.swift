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
    import UserNotifications

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

        @Test("handlePushNotificationDeviceToken sends subscription")
        func handleDeviceTokenSendsSubscription() async throws {
            let sut = getSut()

            let deviceToken = "deadbeef01020304"

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

            let deviceToken = "deadbeef"

            // Should return early without crashing
            sut.handlePushNotificationDeviceToken(deviceToken)

            sut.close()
        }

        // MARK: - Config Default Tests

        @Test("capturePushNotificationSubscriptions defaults to false")
        func configDefaultsToFalse() {
            let config = PostHogConfig(apiKey: testAPIKey)
            #expect(config.capturePushNotificationSubscriptions == false)
        }

        @Test("capturePushNotificationSubscriptions can be set to true")
        func configCanBeEnabled() {
            let config = PostHogConfig(apiKey: testAPIKey)
            config.capturePushNotificationSubscriptions = true
            #expect(config.capturePushNotificationSubscriptions == true)
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
            let hasPushIntegration = integrations.contains { $0 is PostHogPushNotificationIntegration }
            #expect(!hasPushIntegration)
        }

        // MARK: - Push Subscription Persistence Tests

        // Note: These tests write push subscription data directly to storage because
        // Bundle.main.bundleIdentifier is nil in the SPM test runner, which causes
        // sendPushNotificationDeviceToken to exit early. This simulates the state
        // after the initial send attempt persists data but the network call fails.

        @Test("flush retries persisted push subscription and clears on success")
        func flushRetriesPushSubscription() async throws {
            let sut = getSut()

            // Simulate a persisted push subscription (as if a previous send failed or device was offline)
            sut.storage?.setDictionary(forKey: .pushSubscription, contents: [
                "distinctId": sut.getDistinctId(),
                "deviceToken": "deadbeef01020304",
                "appId": "com.example.test",
            ])

            // Verify it was persisted
            let persistedBefore = sut.storage?.getDictionary(forKey: .pushSubscription) as? [String: String]
            #expect(persistedBefore?["deviceToken"] == "deadbeef01020304")

            // Flush should retry the push subscription
            sut.flush()

            try await Task.sleep(nanoseconds: 2_000_000_000)

            // After a successful retry, the push subscription should be cleared from storage
            let persistedAfter = sut.storage?.getDictionary(forKey: .pushSubscription)
            #expect(persistedAfter == nil)

            // Verify the request was sent
            #expect(server.pushSubscriptionRequests.count == 1)

            sut.close()
        }

        @Test("flush retries persisted push subscription but keeps it on failure")
        func flushKeepsPushSubscriptionOnFailure() async throws {
            server.returnPushSubscription500 = true
            let sut = getSut()

            // Simulate a persisted push subscription
            sut.storage?.setDictionary(forKey: .pushSubscription, contents: [
                "distinctId": sut.getDistinctId(),
                "deviceToken": "aabbccdd",
                "appId": "com.example.test",
            ])

            sut.flush()

            try await Task.sleep(nanoseconds: 2_000_000_000)

            // After a failed retry, the push subscription should remain in storage
            let persisted = sut.storage?.getDictionary(forKey: .pushSubscription) as? [String: String]
            #expect(persisted?["deviceToken"] == "aabbccdd")

            // Verify the request was attempted
            #expect(server.pushSubscriptionRequests.count == 1)

            sut.close()
        }

        @Test("flush retries persisted push subscription after initial failure then succeeds")
        func flushRetriesAfterFailureThenSucceeds() async throws {
            server.returnPushSubscription500 = true
            let sut = getSut()

            // Simulate a persisted push subscription
            sut.storage?.setDictionary(forKey: .pushSubscription, contents: [
                "distinctId": sut.getDistinctId(),
                "deviceToken": "abcdef01",
                "appId": "com.example.test",
            ])

            // First flush: should fail
            sut.flush()
            try await Task.sleep(nanoseconds: 2_000_000_000)

            // Subscription should still be persisted
            let persistedAfterFailure = sut.storage?.getDictionary(forKey: .pushSubscription) as? [String: String]
            #expect(persistedAfterFailure?["deviceToken"] == "abcdef01")

            // Now allow success
            server.returnPushSubscription500 = false
            sut.flush()
            try await Task.sleep(nanoseconds: 2_000_000_000)

            // After success, subscription should be cleared
            let persistedAfterSuccess = sut.storage?.getDictionary(forKey: .pushSubscription)
            #expect(persistedAfterSuccess == nil)

            // Should have had 2 requests: one failed, one succeeded
            #expect(server.pushSubscriptionRequests.count == 2)

            sut.close()
        }

        @Test("reset clears persisted push subscription")
        func resetClearsPushSubscription() {
            let sut = getSut()

            // Simulate a persisted push subscription
            sut.storage?.setDictionary(forKey: .pushSubscription, contents: [
                "distinctId": sut.getDistinctId(),
                "deviceToken": "01020304",
                "appId": "com.example.test",
            ])

            // Verify it was persisted
            let persisted = sut.storage?.getDictionary(forKey: .pushSubscription)
            #expect(persisted != nil)

            sut.reset()

            // After reset, the push subscription should be cleared
            let persistedAfterReset = sut.storage?.getDictionary(forKey: .pushSubscription)
            #expect(persistedAfterReset == nil)

            sut.close()
        }

        @Test("flush does nothing when no push subscription is persisted")
        func flushDoesNothingWithoutPersistedSubscription() async throws {
            let sut = getSut()

            // No push subscription in storage
            let persisted = sut.storage?.getDictionary(forKey: .pushSubscription)
            #expect(persisted == nil)

            sut.flush()

            try await Task.sleep(nanoseconds: 1_000_000_000)

            // No push subscription requests should have been made
            #expect(server.pushSubscriptionRequests.count == 0)

            sut.close()
        }

        // MARK: - Manual Notification Opened Capture Tests

        @Test("capturePushNotificationOpened captures event with base notification properties")
        func capturePushNotificationOpenedCapturesBaseProperties() async throws {
            let sut = getSut()

            sut.capturePushNotificationOpened(
                title: "Hello",
                subtitle: "Sub",
                body: "Body",
                userInfo: [:],
                actionIdentifier: UNNotificationDefaultActionIdentifier
            )

            let events = getBatchedEvents(server)
            #expect(events.count == 1)

            let event = try #require(events.first)
            #expect(event.event == "$push_notification_opened")
            #expect(event.properties["$notification_title"] as? String == "Hello")
            #expect(event.properties["$notification_subtitle"] as? String == "Sub")
            #expect(event.properties["$notification_body"] as? String == "Body")
            #expect(event.properties["$notification_action"] == nil)

            sut.close()
        }

        @Test("capturePushNotificationOpened omits empty subtitle and body")
        func capturePushNotificationOpenedOmitsEmptyFields() async throws {
            let sut = getSut()

            sut.capturePushNotificationOpened(
                title: "Hello",
                subtitle: "",
                body: "",
                userInfo: [:],
                actionIdentifier: UNNotificationDefaultActionIdentifier
            )

            let events = getBatchedEvents(server)
            let event = try #require(events.first)
            #expect(event.properties["$notification_title"] as? String == "Hello")
            #expect(event.properties["$notification_subtitle"] == nil)
            #expect(event.properties["$notification_body"] == nil)

            sut.close()
        }

        @Test("capturePushNotificationOpened flattens posthog payload into properties")
        func capturePushNotificationOpenedFlattensPostHogPayload() async throws {
            let sut = getSut()

            sut.capturePushNotificationOpened(
                title: "Hello",
                subtitle: "",
                body: "",
                userInfo: [
                    "posthog": [
                        "campaign_id": "c123",
                        "message_id": "m456",
                    ],
                    "other_key": "ignored",
                ],
                actionIdentifier: UNNotificationDefaultActionIdentifier
            )

            let events = getBatchedEvents(server)
            let event = try #require(events.first)
            #expect(event.properties["$notification_campaign_id"] as? String == "c123")
            #expect(event.properties["$notification_message_id"] as? String == "m456")
            #expect(event.properties["$notification_other_key"] == nil)

            sut.close()
        }

        @Test("capturePushNotificationOpened includes action for non-default identifier")
        func capturePushNotificationOpenedIncludesCustomAction() async throws {
            let sut = getSut()

            sut.capturePushNotificationOpened(
                title: "Hello",
                subtitle: "",
                body: "",
                userInfo: [:],
                actionIdentifier: "OPEN_URL"
            )

            let events = getBatchedEvents(server)
            let event = try #require(events.first)
            #expect(event.properties["$notification_action"] as? String == "OPEN_URL")

            sut.close()
        }

        @Test("capturePushNotificationOpened does nothing when SDK is opted out")
        func capturePushNotificationOpenedNoopWhenOptedOut() async throws {
            let sut = getSut()
            sut.optOut()

            sut.capturePushNotificationOpened(
                title: "Hello",
                subtitle: "Sub",
                body: "Body",
                userInfo: [:],
                actionIdentifier: UNNotificationDefaultActionIdentifier
            )

            // Give the queue a chance to flush if anything had been captured
            try await Task.sleep(nanoseconds: 500_000_000)
            #expect(server.batchRequests.isEmpty)

            sut.optIn()
            sut.close()
        }

        @Test("capturePushNotificationOpened works when swizzling is disabled")
        func capturePushNotificationOpenedWorksWithoutSwizzling() async throws {
            let config = PostHogConfig(apiKey: testAPIKey, host: "http://localhost:9001")
            config.flushAt = 1
            config.enableSwizzling = false
            config.capturePushNotificationSubscriptions = true
            config.captureApplicationLifecycleEvents = false
            config.captureScreenViews = false
            config.disableReachabilityForTesting = true
            config.disableQueueTimerForTesting = true
            config.disableFlushOnBackgroundForTesting = true

            let storage = PostHogStorage(config)
            storage.reset()

            let sut = PostHogSDK.with(config)

            // Integration should NOT be installed because swizzling is off
            #expect(sut.getPushNotificationIntegration() == nil)

            sut.capturePushNotificationOpened(
                title: "Hello",
                subtitle: "",
                body: "",
                userInfo: [:],
                actionIdentifier: UNNotificationDefaultActionIdentifier
            )

            let events = getBatchedEvents(server)
            let event = try #require(events.first)
            #expect(event.event == "$push_notification_opened")
            #expect(event.properties["$notification_title"] as? String == "Hello")

            sut.close()
        }
    }

#endif
