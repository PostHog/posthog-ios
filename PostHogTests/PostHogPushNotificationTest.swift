#if os(iOS) || os(macOS)

    import Foundation
    @testable import PostHog
    import Testing
    import UserNotifications

    @Suite("Push Notification Tests", .serialized)
    final class PostHogPushNotificationTest {
        var server: MockPostHogServer!

        init() {
            if #available(iOS 14.0, macOS 11.0, *) {
                PostHogPushNotificationOpenIntegration.clearInstalls()
            }
            #if os(iOS)
                if #available(iOS 14.0, *) {
                    PostHogPushNotificationSubscriptionIntegration.clearInstalls()
                }
            #endif
            PostHogAppLifeCycleIntegration.clearInstalls()
            PostHogScreenViewIntegration.clearInstalls()

            server = MockPostHogServer()
            server.start()
        }

        deinit {
            server.stop()
            server = nil
        }

        // MARK: - Helpers

        private func waitFor(_ condition: @escaping () -> Bool, timeout: TimeInterval = 5) async -> Bool {
            let deadline = Date().addingTimeInterval(timeout)
            while Date() < deadline {
                if condition() {
                    return true
                }
                try? await Task.sleep(nanoseconds: 20_000_000)
            }
            return condition()
        }

        private func delivered(_ storage: PostHogStorage) -> Bool {
            let record = storage.getDictionary(forKey: .pushSubscription) as? [String: String]
            return record?["deliveredForDistinctId"] != nil
        }

        private func record(_ storage: PostHogStorage) -> [String: String]? {
            storage.getDictionary(forKey: .pushSubscription) as? [String: String]
        }

        private func makeHandler(
            maxRetries: Int = 3,
            distinctIdProvider: @escaping () -> String = { "user-1" },
            isConnectedProvider: @escaping () -> Bool = { true },
            isAllowedProvider: @escaping () -> Bool = { true },
            onEventContextChanged: PostHogMulticastCallback<[String: Any]> = .init(),
            resetStorage: Bool = true
        ) -> (handler: PostHogPushSubscriptionHandler, storage: PostHogStorage, config: PostHogConfig) {
            let config = PostHogConfig(projectToken: testProjectToken, host: "http://localhost:9001")
            config.maxRetries = maxRetries
            config.disableReachabilityForTesting = true
            let api = PostHogApi(config)
            let storage = PostHogStorage(config)
            if resetStorage {
                storage.reset()
            }
            let handler = PostHogPushSubscriptionHandler(
                api,
                storage,
                config,
                distinctIdProvider: distinctIdProvider,
                isConnectedProvider: isConnectedProvider,
                isAllowedProvider: isAllowedProvider,
                onEventContextChanged: onEventContextChanged
            )
            return (handler, storage, config)
        }

        private func getSDK(
            optOut: Bool = false,
            enableSwizzling: Bool = true,
            capturePushNotificationOpened: Bool = false,
            reuseAnonymousId: Bool = false
        ) -> PostHogSDK {
            let config = PostHogConfig(projectToken: testProjectToken, host: "http://localhost:9001")
            config.flushAt = 1
            config.optOut = optOut
            config.reuseAnonymousId = reuseAnonymousId
            config.enableSwizzling = enableSwizzling
            config.captureApplicationLifecycleEvents = false
            config.captureScreenViews = false
            config.capturePushNotificationSubscriptions = false
            config.capturePushNotificationOpened = capturePushNotificationOpened
            config.disableReachabilityForTesting = true
            config.disableQueueTimerForTesting = true
            config.disableFlushOnBackgroundForTesting = true

            let storage = PostHogStorage(config)
            storage.reset()

            return PostHogSDK.with(config)
        }

        // MARK: - Config defaults

        @Test("capturePushNotificationSubscriptions and capturePushNotificationOpened default to true")
        func configFlagsDefaultToTrue() {
            let config = PostHogConfig(projectToken: testProjectToken)
            #expect(config.capturePushNotificationSubscriptions == true)
            #expect(config.capturePushNotificationOpened == true)
        }

        // MARK: - getIntegrations gating

        @Test("getIntegrations includes the opened integration only when its flag is enabled")
        func getIntegrationsGatesOpenedIntegration() {
            guard #available(iOS 14.0, macOS 11.0, *) else { return }

            let enabled = PostHogConfig(projectToken: testProjectToken)
            enabled.capturePushNotificationOpened = true
            #expect(enabled.getIntegrations().contains { $0 is PostHogPushNotificationOpenIntegration })

            let disabled = PostHogConfig(projectToken: testProjectToken)
            disabled.capturePushNotificationOpened = false
            #expect(!disabled.getIntegrations().contains { $0 is PostHogPushNotificationOpenIntegration })
        }

        #if os(iOS)
            @Test("getIntegrations includes the subscription integration only when its flag is enabled (iOS)")
            func getIntegrationsGatesSubscriptionIntegration() {
                guard #available(iOS 14.0, *) else { return }

                let enabled = PostHogConfig(projectToken: testProjectToken)
                enabled.capturePushNotificationSubscriptions = true
                #expect(enabled.getIntegrations().contains { $0 is PostHogPushNotificationSubscriptionIntegration })

                let disabled = PostHogConfig(projectToken: testProjectToken)
                disabled.capturePushNotificationSubscriptions = false
                #expect(!disabled.getIntegrations().contains { $0 is PostHogPushNotificationSubscriptionIntegration })
            }
        #endif

        // MARK: - Registration (device token)

        @Test("registers the device token and keeps the delivered record (decision 5)")
        func registersAndKeepsDeliveredRecord() async throws {
            let (handler, storage, _) = makeHandler(distinctIdProvider: { "user-1" })

            handler.send(deviceToken: "abcdef", appId: "com.example.app")

            #expect(await waitFor { self.delivered(storage) })
            #expect(server.pushSubscriptionRequests.count == 1)

            let saved = try #require(record(storage))
            #expect(saved["deviceToken"] == "abcdef")
            #expect(saved["appId"] == "com.example.app")
            #expect(saved["deliveredForDistinctId"] == "user-1")

            let body = try #require(server.parseRequest(server.pushSubscriptionRequests[0]))
            #expect(body["distinct_id"] as? String == "user-1")
            #expect(body["device_token"] as? String == "abcdef")
            #expect(body["app_id"] as? String == "com.example.app")
            #expect(body["platform"] as? String == "ios")
        }

        @Test("a new token supersedes the previously persisted record (latest-wins)")
        func latestWinsOverwritesRecord() async {
            // Stay offline so nothing is sent and we test persistence overwriting only.
            let (handler, storage, _) = makeHandler(isConnectedProvider: { false })

            handler.send(deviceToken: "old-token", appId: "com.example.old")
            handler.send(deviceToken: "new-token", appId: "com.example.new")

            let saved = record(storage)
            #expect(saved?["deviceToken"] == "new-token")
            #expect(saved?["appId"] == "com.example.new")
            #expect(saved?["deliveredForDistinctId"] == nil)
            #expect(server.pushSubscriptionRequests.isEmpty)
        }

        @Test("re-registering the delivered token for the same distinct id is skipped")
        func sendSkipsAlreadyDeliveredToken() async {
            let (handler, storage, _) = makeHandler(distinctIdProvider: { "user-1" })
            handler.send(deviceToken: "tok", appId: "com.example.app")
            #expect(await waitFor { self.delivered(storage) })

            handler.send(deviceToken: "tok", appId: "com.example.app")

            try? await Task.sleep(nanoseconds: 300_000_000)
            #expect(server.pushSubscriptionRequests.count == 1)
            // The delivered stamp survives, so an identity change can still trigger a resend.
            #expect(record(storage)?["deliveredForDistinctId"] == "user-1")
        }

        @Test("re-registering a different token after delivery sends again")
        func sendSendsNewTokenAfterDelivery() async {
            let (handler, storage, _) = makeHandler(distinctIdProvider: { "user-1" })
            handler.send(deviceToken: "tok-1", appId: "com.example.app")
            #expect(await waitFor { self.delivered(storage) })

            handler.send(deviceToken: "tok-2", appId: "com.example.app")

            #expect(await waitFor { self.server.pushSubscriptionRequests.count == 2 })
            #expect(record(storage)?["deviceToken"] == "tok-2")
        }

        @Test("re-registering the delivered token under a new distinct id sends again")
        func sendResendsDeliveredTokenForNewDistinctId() async {
            var distinctId = "user-1"
            let (handler, storage, _) = makeHandler(distinctIdProvider: { distinctId })
            handler.send(deviceToken: "tok", appId: "com.example.app")
            #expect(await waitFor { self.delivered(storage) })

            distinctId = "user-2"
            handler.send(deviceToken: "tok", appId: "com.example.app")

            #expect(await waitFor { self.server.pushSubscriptionRequests.count == 2 })
            #expect(await waitFor { self.record(storage)?["deliveredForDistinctId"] == "user-2" })
        }

        // MARK: - Unregister (decision 6)

        @Test("unregister sends exactly one DELETE with the 5-field body and never retries (vector 7)")
        func unregisterFiresOneDeleteNoRetry() async throws {
            // Even a 500 must not be retried — unregister is best-effort, single-shot.
            server.pushSubscriptionStatusCode = 500
            let (handler, _, _) = makeHandler(distinctIdProvider: { "user-1" })

            handler.unregister(distinctId: "user-1", deviceToken: "tok", appId: "com.example.app")

            #expect(await waitFor { self.server.pushSubscriptionRequests.contains { $0.httpMethod == "DELETE" } })
            // Give any (wrongful) retry a window to appear, then assert there was only one.
            try? await Task.sleep(nanoseconds: 300_000_000)
            let deletes = server.pushSubscriptionRequests.filter { $0.httpMethod == "DELETE" }
            #expect(deletes.count == 1)

            let body = try #require(server.parseRequest(deletes[0]))
            #expect(body["api_key"] as? String == testProjectToken)
            #expect(body["distinct_id"] as? String == "user-1")
            #expect(body["device_token"] as? String == "tok")
            #expect(body["platform"] as? String == "ios")
            #expect(body["app_id"] as? String == "com.example.app")
        }

        @Test("unregisterCurrentToken DELETEs for the current id and forgets the stored record")
        func unregisterCurrentForgetsRecord() async throws {
            let (handler, storage, _) = makeHandler(distinctIdProvider: { "user-1" })
            handler.send(deviceToken: "tok", appId: "com.example.app")
            #expect(await waitFor { self.delivered(storage) })

            handler.unregisterCurrentToken()

            #expect(await waitFor { self.server.pushSubscriptionRequests.contains { $0.httpMethod == "DELETE" } })
            let del = try #require(server.pushSubscriptionRequests.first { $0.httpMethod == "DELETE" })
            #expect(try #require(server.parseRequest(del))["distinct_id"] as? String == "user-1")
            #expect(record(storage) == nil)
        }

        @Test("unregister is a no-op when the SDK is disabled or opted out (vector 7)")
        func unregisterGuarded() async {
            let (handler, _, _) = makeHandler(isAllowedProvider: { false })
            handler.unregister(distinctId: "user-1", deviceToken: "tok", appId: "app")
            try? await Task.sleep(nanoseconds: 150_000_000)
            #expect(server.pushSubscriptionRequests.isEmpty)
        }

        #if os(iOS)
            @Test("reset() unregisters the old identity then re-registers under the new anonymous id (vector 8)")
            func resetMovesTokenToAnonymous() async throws {
                // Flag off — reset is record-based, not flag-gated (a manually-registered token still moves).
                let sut = getSDK()
                defer { sut.close() }

                sut.identify("user-A")
                sut.registerPushNotificationToken("tokA", appId: "com.example.app")
                #expect(await waitFor { self.server.pushSubscriptionRequests.contains { $0.httpMethod == "POST" } })
                #expect(sut.getDistinctId() == "user-A")
                server.pushSubscriptionRequests = []

                sut.reset()

                #expect(await waitFor {
                    self.server.pushSubscriptionRequests.contains { $0.httpMethod == "DELETE" }
                        && self.server.pushSubscriptionRequests.contains { $0.httpMethod == "POST" }
                })

                let del = try #require(server.pushSubscriptionRequests.first { $0.httpMethod == "DELETE" })
                let delBody = try #require(server.parseRequest(del))
                #expect(delBody["distinct_id"] as? String == "user-A")
                #expect(delBody["device_token"] as? String == "tokA")

                let post = try #require(server.pushSubscriptionRequests.first { $0.httpMethod == "POST" })
                let postBody = try #require(server.parseRequest(post))
                #expect(postBody["device_token"] as? String == "tokA")
                #expect(postBody["distinct_id"] as? String != "user-A")
                #expect(postBody["distinct_id"] as? String == sut.getDistinctId())
            }

            @Test("reset() with reuseAnonymousId keeps the id: re-registers without a DELETE")
            func resetReuseAnonymousIdSkipsDelete() async throws {
                let sut = getSDK(reuseAnonymousId: true)
                defer { sut.close() }

                sut.registerPushNotificationToken("tokA", appId: "com.example.app")
                #expect(await waitFor { self.server.pushSubscriptionRequests.contains { $0.httpMethod == "POST" } })
                let idBefore = sut.getDistinctId()
                server.pushSubscriptionRequests = []

                sut.reset()
                #expect(sut.getDistinctId() == idBefore)

                // A re-register POST fires (the wiped record is re-persisted), but no DELETE — the id didn't change.
                #expect(await waitFor { self.server.pushSubscriptionRequests.contains { $0.httpMethod == "POST" } })
                try? await Task.sleep(nanoseconds: 250_000_000)
                #expect(!server.pushSubscriptionRequests.contains { $0.httpMethod == "DELETE" })
            }
        #endif

        @Test("reset() sends no push requests when no token was ever registered")
        func resetNoTokenNoRequests() async throws {
            let sut = getSDK()
            defer { sut.close() }

            sut.reset()
            try? await Task.sleep(nanoseconds: 300_000_000)
            #expect(server.pushSubscriptionRequests.isEmpty)
        }

        @Test("reregisterAfterReset re-persists and sends the snapshot when storage was cleared")
        func reregisterAfterResetPersistsWhenCleared() async throws {
            let (handler, storage, _) = makeHandler(distinctIdProvider: { "anon-1" })

            handler.reregisterAfterReset(deviceToken: "tok", appId: "com.example.app")

            #expect(await waitFor { self.delivered(storage) })
            let saved = try #require(record(storage))
            #expect(saved["deviceToken"] == "tok")
            #expect(saved["deliveredForDistinctId"] == "anon-1")

            let body = try #require(server.parseRequest(server.pushSubscriptionRequests[0]))
            #expect(body["device_token"] as? String == "tok")
            #expect(body["distinct_id"] as? String == "anon-1")
        }

        @Test("reregisterAfterReset skips when a newer token was persisted during reset (no clobber)")
        func reregisterAfterResetSkipsWhenSuperseded() async throws {
            let (handler, storage, _) = makeHandler(distinctIdProvider: { "anon-1" })

            // Simulate an APNs delivery that raced reset(): a newer token is persisted after storage was
            // cleared but before the stale snapshot re-register runs.
            storage.setDictionary(forKey: .pushSubscription, contents: [
                "deviceToken": "newer-token",
                "appId": "com.example.new",
            ])

            handler.reregisterAfterReset(deviceToken: "stale-snapshot", appId: "com.example.old")

            // Give any (wrongful) send a window to appear.
            try? await Task.sleep(nanoseconds: 200_000_000)

            // Newer token untouched; no POST for the stale snapshot.
            let saved = try #require(record(storage))
            #expect(saved["deviceToken"] == "newer-token")
            #expect(saved["appId"] == "com.example.new")
            #expect(server.pushSubscriptionRequests.isEmpty)
        }

        // MARK: - Retry & backoff (vector 4)

        @Test("retry backoff is exponential, capped at 30s (vector 4)")
        func retryBackoffIsExponential() {
            let (handler, _, _) = makeHandler()
            #expect(handler.retryDelay(forAttempt: 1) == 5)
            #expect(handler.retryDelay(forAttempt: 2) == 10)
            #expect(handler.retryDelay(forAttempt: 3) == 20)
            #expect(handler.retryDelay(forAttempt: 4) == 30)
            #expect(handler.retryDelay(forAttempt: 5) == 30)
        }

        @Test("retries after a 500 then succeeds (vector 4)")
        func retriesAfter500ThenSucceeds() async throws {
            server.pushSubscriptionStatusCode = 500
            let (handler, storage, _) = makeHandler()

            handler.send(deviceToken: "tok", appId: "app")
            #expect(await waitFor { handler.retryCountForTesting == 1 })
            #expect(!delivered(storage))

            // Allow success and drive the retry without waiting on the real backoff window.
            server.pushSubscriptionStatusCode = nil
            handler.clearBackoffForTesting()
            handler.retryIfNeeded()

            #expect(await waitFor { self.delivered(storage) })
            #expect(server.pushSubscriptionRequests.count == 2)
        }

        @Test("gives up after maxRetries, keeps the record, and retries once on relaunch (vector 4)")
        func givesUpKeepsRecordThenRetriesOnRelaunch() async throws {
            server.pushSubscriptionStatusCode = 500
            let maxRetries = 3
            let (handler, storage, config) = makeHandler(maxRetries: maxRetries)

            handler.send(deviceToken: "tok", appId: "app") // attempt 1
            #expect(await waitFor { handler.retryCountForTesting == 1 })

            // Drive attempts 2 ... maxRetries + 1
            for expected in 2 ... (maxRetries + 1) {
                handler.clearBackoffForTesting()
                handler.retryIfNeeded()
                #expect(await waitFor { self.server.pushSubscriptionRequests.count >= expected })
            }

            #expect(await waitFor { handler.isHaltedForTesting })
            #expect(server.pushSubscriptionRequests.count == maxRetries + 1)

            // Further in-session retries do nothing while halted.
            handler.clearBackoffForTesting()
            handler.retryIfNeeded()
            try await Task.sleep(nanoseconds: 200_000_000)
            #expect(server.pushSubscriptionRequests.count == maxRetries + 1)

            // The record is kept for the next launch.
            #expect(record(storage)?["deviceToken"] == "tok")
            #expect(!delivered(storage))

            // Relaunch: a fresh handler over the same storage retries once, now succeeding.
            server.pushSubscriptionStatusCode = nil
            let relaunched = PostHogPushSubscriptionHandler(
                PostHogApi(config),
                storage,
                config,
                distinctIdProvider: { "user-1" },
                isConnectedProvider: { true },
                isAllowedProvider: { true },
                onEventContextChanged: .init()
            )
            relaunched.retryIfNeeded()

            #expect(await waitFor { self.delivered(storage) })
            #expect(server.pushSubscriptionRequests.count == maxRetries + 2)
        }

        @Test("honors a Retry-After header for the backoff window")
        func honorsRetryAfterHeader() async throws {
            server.pushSubscriptionStatusCode = 503
            server.pushSubscriptionRetryAfter = "1"
            let (handler, _, _) = makeHandler()

            handler.send(deviceToken: "tok", appId: "app")
            // A retryable failure schedules a backoff; the request is still counted.
            #expect(await waitFor { handler.retryCountForTesting == 1 })
            #expect(server.pushSubscriptionRequests.count == 1)
        }

        // MARK: - Non-retryable (vector 5)

        @Test("a 400 response keeps the record and stops in-session retries (vector 5)")
        func nonRetryable400KeepsRecordNoInSessionRetry() async throws {
            server.pushSubscriptionStatusCode = 400
            let (handler, storage, _) = makeHandler()

            handler.send(deviceToken: "tok", appId: "app")
            #expect(await waitFor { handler.isHaltedForTesting })
            #expect(server.pushSubscriptionRequests.count == 1)

            // No in-session retry.
            handler.clearBackoffForTesting()
            handler.retryIfNeeded()
            try await Task.sleep(nanoseconds: 200_000_000)
            #expect(server.pushSubscriptionRequests.count == 1)

            // Record kept, not marked delivered.
            #expect(record(storage)?["deviceToken"] == "tok")
            #expect(!delivered(storage))
        }

        // MARK: - Offline

        @Test("defers while offline without burning a retry attempt")
        func offlineDefersWithoutBurningAttempt() async throws {
            var connected = false
            let (handler, storage, _) = makeHandler(isConnectedProvider: { connected })

            handler.send(deviceToken: "tok", appId: "app")
            try await Task.sleep(nanoseconds: 300_000_000)
            #expect(server.pushSubscriptionRequests.isEmpty)
            #expect(handler.retryCountForTesting == 0)
            #expect(record(storage)?["deviceToken"] == "tok")

            // Reconnect → the persisted record is sent.
            connected = true
            handler.retryIfNeeded()
            #expect(await waitFor { self.server.pushSubscriptionRequests.count == 1 })
        }

        @Test("does not send when disallowed (disabled or opted out) but keeps the record")
        func disallowedKeepsRecordSendsNothing() async throws {
            let (handler, storage, _) = makeHandler(isAllowedProvider: { false })

            handler.send(deviceToken: "tok", appId: "app")

            try await Task.sleep(nanoseconds: 300_000_000)
            #expect(server.pushSubscriptionRequests.isEmpty)
            #expect(record(storage)?["deviceToken"] == "tok")
        }

        // MARK: - Re-register on identify (decision 5)

        @Test("re-registers the token when the distinct id changes (decision 5)")
        func reRegistersOnDistinctIdChange() async throws {
            var distinctId = "user-1"
            let contextChanged = PostHogMulticastCallback<[String: Any]>()
            let (handler, storage, _) = makeHandler(
                distinctIdProvider: { distinctId },
                onEventContextChanged: contextChanged
            )

            handler.send(deviceToken: "tok", appId: "app")
            #expect(await waitFor { self.delivered(storage) })
            let firstBody = try #require(server.parseRequest(server.pushSubscriptionRequests[0]))
            #expect(firstBody["distinct_id"] as? String == "user-1")

            // Identity changes; the context-changed multicast fires with the new id.
            distinctId = "user-2"
            contextChanged.invoke(["distinct_id": "user-2"])

            #expect(await waitFor { self.server.pushSubscriptionRequests.count == 2 })
            let secondBody = try #require(server.parseRequest(server.pushSubscriptionRequests[1]))
            #expect(secondBody["distinct_id"] as? String == "user-2")
        }

        @Test("does not re-register when the distinct id is unchanged")
        func noResendWhenDistinctIdUnchanged() async throws {
            let contextChanged = PostHogMulticastCallback<[String: Any]>()
            let (handler, storage, _) = makeHandler(
                distinctIdProvider: { "user-1" },
                onEventContextChanged: contextChanged
            )

            handler.send(deviceToken: "tok", appId: "app")
            #expect(await waitFor { self.delivered(storage) })
            #expect(server.pushSubscriptionRequests.count == 1)

            contextChanged.invoke(["distinct_id": "user-1"])
            try await Task.sleep(nanoseconds: 300_000_000)
            #expect(server.pushSubscriptionRequests.count == 1)
        }

        @Test("opted out: an identity change does not resend (resendIfDistinctIdChanged)")
        func optedOutIdentityChangeDoesNotResend() async throws {
            var allowed = true
            var distinctId = "user-1"
            let contextChanged = PostHogMulticastCallback<[String: Any]>()
            let (handler, storage, _) = makeHandler(
                distinctIdProvider: { distinctId },
                isAllowedProvider: { allowed },
                onEventContextChanged: contextChanged
            )

            // Deliver once so the record is stamped with deliveredForDistinctId = "user-1".
            handler.send(deviceToken: "tok", appId: "app")
            #expect(await waitFor { self.delivered(storage) })
            #expect(server.pushSubscriptionRequests.count == 1)

            // Opt out, then change identity: resendIfDistinctIdChanged runs but the guard blocks the send.
            allowed = false
            distinctId = "user-2"
            contextChanged.invoke(["distinct_id": "user-2"])

            try await Task.sleep(nanoseconds: 300_000_000)
            #expect(server.pushSubscriptionRequests.count == 1)
            #expect(record(storage)?["deviceToken"] == "tok")
        }

        // MARK: - SDK-level device token API

        #if os(iOS)
            @Test("registerPushNotificationToken with an explicit appId sends a request")
            func sdkHandleDeviceTokenWithExplicitAppId() async throws {
                let sut = getSDK()

                sut.registerPushNotificationToken("deadbeef01", appId: "com.example.app")

                #expect(await waitFor { self.server.pushSubscriptionRequests.count == 1 })
                let body = try #require(server.parseRequest(server.pushSubscriptionRequests[0]))
                #expect(body["device_token"] as? String == "deadbeef01")
                #expect(body["app_id"] as? String == "com.example.app")
                #expect(body["platform"] as? String == "ios")

                sut.close()
            }

            @Test("opted out: registerPushNotificationToken sends no request (vector 6)")
            func sdkRegistrationNoRequestWhenOptedOut() async throws {
                let sut = getSDK(optOut: true)

                sut.registerPushNotificationToken("deadbeef", appId: "com.example.app")

                try await Task.sleep(nanoseconds: 300_000_000)
                #expect(server.pushSubscriptionRequests.isEmpty)

                sut.close()
            }
        #endif

        @Test("flush retries a persisted subscription and marks it delivered")
        func sdkFlushRetriesPersistedSubscription() async throws {
            let sut = getSDK()

            // Bundle.main.bundleIdentifier is nil under the SPM runner, so write the record directly.
            sut.storage?.setDictionary(forKey: .pushSubscription, contents: [
                "deviceToken": "deadbeef",
                "appId": "com.example.test",
            ])

            sut.flush()

            #expect(await waitFor { self.server.pushSubscriptionRequests.count == 1 })
            #expect(await waitFor {
                (sut.storage?.getDictionary(forKey: .pushSubscription) as? [String: String])?["deliveredForDistinctId"] != nil
            })

            sut.close()
        }

        @Test("opted out: flush does not retry a persisted subscription (vector 6)")
        func optedOutFlushDoesNotRetry() async throws {
            let sut = getSDK(optOut: true)

            sut.storage?.setDictionary(forKey: .pushSubscription, contents: [
                "deviceToken": "deadbeef",
                "appId": "com.example.test",
            ])

            sut.flush()

            try await Task.sleep(nanoseconds: 300_000_000)
            #expect(server.pushSubscriptionRequests.isEmpty)

            sut.close()
        }

        @Test("setup retries a persisted subscription from a previous launch")
        func setupRetriesPersistedSubscriptionFromPreviousLaunch() async throws {
            let config = PostHogConfig(projectToken: testProjectToken, host: "http://localhost:9001")
            config.captureApplicationLifecycleEvents = false
            config.captureScreenViews = false
            config.capturePushNotificationSubscriptions = false
            config.capturePushNotificationOpened = false
            config.disableReachabilityForTesting = true
            config.disableQueueTimerForTesting = true
            config.disableFlushOnBackgroundForTesting = true

            // Seed the record before the SDK exists, as a previous launch would have.
            let storage = PostHogStorage(config)
            storage.reset()
            storage.setDictionary(forKey: .pushSubscription, contents: [
                "deviceToken": "tok-from-last-launch",
                "appId": "com.example.test",
            ])

            let sut = PostHogSDK.with(config)

            #expect(await waitFor { self.server.pushSubscriptionRequests.count == 1 })
            let body = try #require(server.parseRequest(server.pushSubscriptionRequests[0]))
            #expect(body["device_token"] as? String == "tok-from-last-launch")

            sut.close()
        }

        @Test("reset re-registers the persisted push subscription instead of dropping it (decision 5/6)")
        func sdkResetReregistersPersistedSubscription() {
            let sut = getSDK()

            sut.storage?.setDictionary(forKey: .pushSubscription, contents: [
                "deviceToken": "tok",
                "appId": "com.example.test",
            ])
            #expect(sut.storage?.getDictionary(forKey: .pushSubscription) != nil)

            sut.reset()

            // The token follows the user rather than being dropped: reset() unregisters it for the old
            // identity and re-registers it, so the record is re-persisted synchronously (the DELETE-then-POST
            // wire behavior is covered by resetMovesTokenToAnonymous).
            let moved = sut.storage?.getDictionary(forKey: .pushSubscription) as? [String: String]
            #expect(moved?["deviceToken"] == "tok")
            #expect(moved?["appId"] == "com.example.test")

            sut.close()
        }

        // MARK: - Opened capture property mapping (vectors 1, 2, 6)

        @Test("captures $push_notification_opened with the posthog payload flattened (vector 1)")
        func openCaptureFlattensPosthogPayload() async throws {
            let sut = getSDK()

            sut.capturePushNotificationOpened(
                title: "Hello",
                subtitle: "",
                body: "World",
                payload: ["posthog": ["campaign": "summer", "message_id": "42"]],
                action: nil
            )

            let events = getBatchedEvents(server)
            let event = try #require(events.first)
            #expect(event.event == "$push_notification_opened")
            #expect(event.properties["$notification_title"] as? String == "Hello")
            #expect(event.properties["$notification_body"] as? String == "World")
            #expect(event.properties["$notification_campaign"] as? String == "summer")
            #expect(event.properties["$notification_message_id"] as? String == "42")

            sut.close()
        }

        @Test("parses a JSON-string posthog payload (FCM relay path)")
        func openCaptureParsesPosthogJSONString() async throws {
            let sut = getSDK()

            sut.capturePushNotificationOpened(
                title: "Hello",
                subtitle: "",
                body: "World",
                payload: ["posthog": "{\"campaign\":\"summer\",\"message_id\":\"42\"}"],
                action: nil
            )

            let events = getBatchedEvents(server)
            let event = try #require(events.first)
            #expect(event.properties["$notification_campaign"] as? String == "summer")
            #expect(event.properties["$notification_message_id"] as? String == "42")

            sut.close()
        }

        @Test("ignores a posthog payload string that is not a JSON object")
        func openCaptureIgnoresInvalidPosthogString() async throws {
            let sut = getSDK()

            sut.capturePushNotificationOpened(
                title: "Hello",
                subtitle: "",
                body: "",
                payload: ["posthog": "not-json"],
                action: nil
            )

            let events = getBatchedEvents(server)
            let event = try #require(events.first)
            #expect(event.properties["$notification_title"] as? String == "Hello")
            #expect(event.properties.keys.filter { $0.hasPrefix("$notification_") } == ["$notification_title"])

            sut.close()
        }

        @Test("captures only base notification props when there is no posthog payload (vector 2)")
        func openCaptureBasePropsOnly() async throws {
            let sut = getSDK()

            sut.capturePushNotificationOpened(
                title: "Hello",
                subtitle: "Sub",
                body: "World",
                payload: ["unrelated": "ignored"],
                action: UNNotificationDefaultActionIdentifier
            )

            let events = getBatchedEvents(server)
            let event = try #require(events.first)
            #expect(event.properties["$notification_title"] as? String == "Hello")
            #expect(event.properties["$notification_subtitle"] as? String == "Sub")
            #expect(event.properties["$notification_body"] as? String == "World")
            #expect(event.properties["$notification_action"] == nil)
            #expect(event.properties["$notification_unrelated"] == nil)

            sut.close()
        }

        @Test("omits empty subtitle and body")
        func openCaptureOmitsEmptyFields() async throws {
            let sut = getSDK()

            sut.capturePushNotificationOpened(
                title: "Hello",
                subtitle: "",
                body: "",
                payload: [:],
                action: nil
            )

            let events = getBatchedEvents(server)
            let event = try #require(events.first)
            #expect(event.properties["$notification_title"] as? String == "Hello")
            #expect(event.properties["$notification_subtitle"] == nil)
            #expect(event.properties["$notification_body"] == nil)

            sut.close()
        }

        @Test("omits an empty title")
        func openCaptureOmitsEmptyTitle() async throws {
            let sut = getSDK()

            sut.capturePushNotificationOpened(
                title: "",
                subtitle: "",
                body: "World",
                payload: [:],
                action: nil
            )

            let events = getBatchedEvents(server)
            let event = try #require(events.first)
            #expect(event.properties["$notification_title"] == nil)
            #expect(event.properties["$notification_body"] as? String == "World")

            sut.close()
        }

        @Test("includes the action identifier when it is non-default")
        func openCaptureIncludesCustomAction() async throws {
            let sut = getSDK()

            sut.capturePushNotificationOpened(
                title: "Hello",
                subtitle: "",
                body: "",
                payload: [:],
                action: "OPEN_URL"
            )

            let events = getBatchedEvents(server)
            let event = try #require(events.first)
            #expect(event.properties["$notification_action"] as? String == "OPEN_URL")

            sut.close()
        }

        @Test("all-nil arguments capture the event with no notification properties")
        func openCaptureAllNilArguments() async throws {
            let sut = getSDK()

            sut.capturePushNotificationOpened()

            let events = getBatchedEvents(server)
            let event = try #require(events.first)
            #expect(event.event == "$push_notification_opened")
            #expect(event.properties.keys.filter { $0.hasPrefix("$notification_") }.isEmpty)

            sut.close()
        }

        @Test("opted out: no $push_notification_opened event is captured (vector 6)")
        func openCaptureNoEventWhenOptedOut() async throws {
            let sut = getSDK(optOut: true)

            sut.capturePushNotificationOpened(
                title: "Hello",
                subtitle: "Sub",
                body: "Body",
                payload: [:],
                action: nil
            )

            try await Task.sleep(nanoseconds: 300_000_000)
            #expect(server.batchRequests.isEmpty)

            sut.close()
        }

        @Test("manual open-capture works when swizzling is disabled")
        func openCaptureWorksWithoutSwizzling() async throws {
            let sut = getSDK(enableSwizzling: false, capturePushNotificationOpened: true)

            if #available(iOS 14.0, macOS 11.0, *) {
                #expect(sut.getPushNotificationIntegration() == nil)
            }

            sut.capturePushNotificationOpened(
                title: "Hello",
                subtitle: "",
                body: "",
                payload: [:],
                action: nil
            )

            let events = getBatchedEvents(server)
            let event = try #require(events.first)
            #expect(event.event == "$push_notification_opened")
            #expect(event.properties["$notification_title"] as? String == "Hello")

            sut.close()
        }
    }

#endif
