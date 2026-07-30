#if os(iOS) || os(macOS)

    import Foundation
    import OHHTTPStubs
    import OHHTTPStubsSwift
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

        /// Thread-safe recorder for `pushIdentityProvider` closures, which may run on any thread.
        private final class MintRecorder {
            private let lock = NSLock()
            private var invocations = [(distinctId: String, appId: String)]()

            /// Records one invocation and returns its 1-based ordinal (usable as a unique token suffix).
            func record(_ distinctId: String, _ appId: String) -> Int {
                lock.withLock {
                    invocations.append((distinctId, appId))
                    return invocations.count
                }
            }

            var count: Int { lock.withLock { invocations.count } }
            var distinctIds: [String] { lock.withLock { invocations.map(\.distinctId) } }
        }

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
                // reset() deliberately keeps .pushPendingUnregister (a logout DELETE must outlive
                // reset) and .pushSubscription (the handler clears it under recordLock instead);
                // clear both here so state from a prior test can't leak into this handler.
                storage.remove(key: .pushPendingUnregister)
                storage.remove(key: .pushSubscription)
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
            reuseAnonymousId: Bool = false,
            pushIdentityProvider: ((String, String, @escaping (String?) -> Void) -> Void)? = nil
        ) -> PostHogSDK {
            let config = PostHogConfig(projectToken: testProjectToken, host: "http://localhost:9001")
            config.flushAt = 1
            config.optOut = optOut
            config.reuseAnonymousId = reuseAnonymousId
            config.enableSwizzling = enableSwizzling
            config.pushIdentityProvider = pushIdentityProvider
            config.captureApplicationLifecycleEvents = false
            config.captureScreenViews = false
            config.capturePushNotificationSubscriptions = false
            config.capturePushNotificationOpened = capturePushNotificationOpened
            config.disableReachabilityForTesting = true
            config.disableQueueTimerForTesting = true
            config.disableFlushOnBackgroundForTesting = true

            let storage = PostHogStorage(config)
            storage.reset()
            storage.remove(key: .pushSubscription)
            storage.remove(key: .pushPendingUnregister)

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

        @Test("unregister sends exactly one DELETE with the 5-field body per attempt (vector 7)")
        func unregisterFiresOneDeleteNoRetry() async throws {
            // A 500 fires one DELETE per attempt (no immediate retry); the intent is kept and retried
            // only on flush()/next launch, so no second DELETE appears within this call.
            server.pushSubscriptionStatusCode = 500
            let (handler, _, _) = makeHandler(distinctIdProvider: { "user-1" })

            handler.unregister(distinctId: "user-1", deviceToken: "tok", appId: "com.example.app")

            #expect(await waitFor { self.server.pushSubscriptionRequests.contains { $0.httpMethod == "DELETE" } })
            // Give any (wrongful) retry a window to appear, then assert there was only one.
            try? await Task.sleep(nanoseconds: 300_000_000)
            let deletes = server.pushSubscriptionRequests.filter { $0.httpMethod == "DELETE" }
            #expect(deletes.count == 1)

            let firstDelete = try #require(deletes.first)
            let body = try #require(server.parseRequest(firstDelete))
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

            @Test("reset(): DELETE reuses the old id's cached token, re-POST mints the anon id's (vector 11)")
            func resetMintsPerLegIdentityTokens() async throws {
                let recorder = MintRecorder()
                let sut = getSDK(pushIdentityProvider: { distinctId, appId, completion in
                    _ = recorder.record(distinctId, appId)
                    completion("jwt-\(distinctId)")
                })
                defer { sut.close() }

                sut.identify("user-A")
                sut.registerPushNotificationToken("tokA", appId: "com.example.app")
                #expect(await waitFor {
                    (sut.storage?.getDictionary(forKey: .pushSubscription) as? [String: String])?["deliveredForDistinctId"] == "user-A"
                })
                server.pushSubscriptionRequests = []

                sut.reset()

                #expect(await waitFor {
                    self.server.pushSubscriptionRequests.contains { $0.httpMethod == "DELETE" }
                        && self.server.pushSubscriptionRequests.contains { $0.httpMethod == "POST" }
                })

                // The DELETE leg reuses the token already cached for the delivered id (no re-mint); the
                // re-POST leg mints a fresh token for the new anon id. The exact invocation count is not
                // asserted: reset()'s context-change resend races the explicit DELETE/re-POST legs, so the
                // cache hit for the DELETE leg is timing-dependent (unlike Android, where the single
                // executor serializes both legs).
                let del = try #require(server.pushSubscriptionRequests.first { $0.httpMethod == "DELETE" })
                let delBody = try #require(server.parseRequest(del))
                #expect(delBody["distinct_id"] as? String == "user-A")
                #expect(delBody["identity_token"] as? String == "jwt-user-A")

                let post = try #require(server.pushSubscriptionRequests.first { $0.httpMethod == "POST" })
                let postBody = try #require(server.parseRequest(post))
                let anonId = try #require(postBody["distinct_id"] as? String)
                #expect(anonId != "user-A")
                #expect(postBody["identity_token"] as? String == "jwt-\(anonId)")
                #expect(recorder.distinctIds.starts(with: ["user-A"]))
                #expect(recorder.distinctIds.contains(anonId))
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

        @Test("recordForReset clears the record under its lock so a concurrent send() isn't lost")
        func recordForResetClearsUnderLockPreservesConcurrentSend() async throws {
            let (handler, storage, _) = makeHandler(distinctIdProvider: { "user-1" })

            handler.send(deviceToken: "old-tok", appId: "com.example.app")
            #expect(await waitFor { self.delivered(storage) })

            // recordForReset() snapshots AND clears in the same locked section — nothing left for an
            // unlocked storage.reset() to delete afterward.
            let snapshot = handler.recordForReset()
            #expect(snapshot?.deviceToken == "old-tok")
            #expect(record(storage) == nil)

            // A send() racing the reset lands in the gap before reregisterAfterReset() runs.
            handler.send(deviceToken: "new-tok", appId: "com.example.app")
            #expect(await waitFor { self.delivered(storage) })

            handler.reregisterAfterReset(deviceToken: snapshot!.deviceToken, appId: snapshot!.appId)
            try? await Task.sleep(nanoseconds: 200_000_000)

            // The fresh, concurrently-written record survives; the stale pre-reset snapshot is not
            // rewritten over it.
            let saved = try #require(record(storage))
            #expect(saved["deviceToken"] == "new-tok")
        }

        // MARK: - Stale identity / identical re-register races

        @Test("distinct id changing during the identity-token mint skips the stale send")
        func staleDistinctIdDuringMintSkipsSend() async throws {
            var distinctId = "user-1"
            let lock = NSLock()
            var pendingCompletion: ((String?) -> Void)?
            let (handler, storage, config) = makeHandler(distinctIdProvider: { distinctId })
            config.pushIdentityProvider = { _, _, completion in
                lock.withLock { pendingCompletion = completion }
            }

            handler.send(deviceToken: "tok", appId: "app")
            #expect(await waitFor { lock.withLock { pendingCompletion != nil } })

            // Identity changes while the mint is still in flight.
            distinctId = "user-2"
            lock.withLock { pendingCompletion }?("jwt-user-1")

            // The stale-identity send is skipped; no request fires for it.
            try await Task.sleep(nanoseconds: 300_000_000)
            #expect(server.pushSubscriptionRequests.isEmpty)
            #expect(!delivered(storage))

            // `isSending` was released, so a fresh send for the new identity still works.
            config.pushIdentityProvider = { _, _, completion in completion("jwt-user-2") }
            handler.send(deviceToken: "tok", appId: "app")
            #expect(await waitFor { self.delivered(storage) })
            #expect(record(storage)?["deliveredForDistinctId"] == "user-2")
        }

        @Test("re-registering an identical undelivered token does not reset retry state (keeps backoff)")
        func repeatIdenticalRegisterKeepsBackoffPause() async throws {
            server.pushSubscriptionStatusCode = 500
            let (handler, _, _) = makeHandler()

            handler.send(deviceToken: "tok", appId: "app")
            #expect(await waitFor { handler.retryCountForTesting == 1 })

            // APNs re-delivers the same token while still paused — must not reset retryCount/backoff.
            handler.send(deviceToken: "tok", appId: "app")
            try await Task.sleep(nanoseconds: 200_000_000)

            #expect(handler.retryCountForTesting == 1)
            #expect(server.pushSubscriptionRequests.count == 1) // still paused, no immediate re-attempt
        }

        @Test("a registration racing an unregister's identity mint cancels the pending DELETE (supersede at mint completion)")
        func registrationDuringUnregisterMintCancelsDelete() async throws {
            let lock = NSLock()
            var mintCount = 0
            var completions: [Int: (String?) -> Void] = [:]
            let (handler, storage, config) = makeHandler(distinctIdProvider: { "user-1" })
            config.pushIdentityProvider = { _, _, completion in
                lock.withLock {
                    mintCount += 1
                    completions[mintCount] = completion
                }
            }

            handler.unregister(distinctId: "user-1", deviceToken: "tok", appId: "app")
            #expect(await waitFor { lock.withLock { completions[1] != nil } })

            // Re-login as user-1 for the same app while the DELETE's mint is still in flight; its own
            // mint is captured too, so the registration record exists but isn't delivered yet.
            handler.send(deviceToken: "tok", appId: "app")
            #expect(await waitFor { lock.withLock { completions[2] != nil } })

            // Release the DELETE's mint: the pending unregister still matches this identity/app, and a
            // (still-undelivered) registration record for it exists, so the DELETE must be cancelled.
            lock.withLock { completions[1] }?("jwt-1")
            try await Task.sleep(nanoseconds: 300_000_000)
            #expect(!server.pushSubscriptionRequests.contains { $0.httpMethod == "DELETE" })
            #expect(!handler.hasPendingUnregisterForTesting)

            // Let the registration finish normally.
            lock.withLock { completions[2] }?("jwt-2")
            #expect(await waitFor { self.delivered(storage) })
        }

        @Test("retryIfNeeded fires a pending unregister for a different app id even when a registration is queued")
        func retryFiresDifferentAppIdUnregisterWhenRegistrationQueued() async throws {
            var connected = false
            let (handler, _, _) = makeHandler(distinctIdProvider: { "user-1" }, isConnectedProvider: { connected })

            // Log out of user-1's appA while offline, then register a token for a different app (appB).
            handler.unregister(distinctId: "user-1", deviceToken: "tok", appId: "com.example.appA")
            handler.send(deviceToken: "tok2", appId: "com.example.appB")

            try await Task.sleep(nanoseconds: 200_000_000)
            #expect(server.pushSubscriptionRequests.isEmpty)
            #expect(handler.hasPendingUnregisterForTesting)

            connected = true
            handler.retryIfNeeded()

            // Different app_id: the backend keys registrations per (person, app_id), so the queued
            // DELETE for appA still fires alongside the POST for appB — neither supersedes the other.
            #expect(await waitFor {
                self.server.pushSubscriptionRequests.contains { $0.httpMethod == "DELETE" }
                    && self.server.pushSubscriptionRequests.contains { $0.httpMethod == "POST" }
            })
            #expect(await waitFor { !handler.hasPendingUnregisterForTesting })
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

        @Test("a 429 response is retried (rate limited)")
        func retries429ThenSucceeds() async throws {
            server.pushSubscriptionStatusHandler = { requestNumber in requestNumber == 1 ? 429 : 200 }
            let (handler, storage, _) = makeHandler()

            handler.send(deviceToken: "tok", appId: "app")
            #expect(await waitFor { handler.retryCountForTesting == 1 })
            #expect(!delivered(storage))

            handler.clearBackoffForTesting()
            handler.retryIfNeeded()

            #expect(await waitFor { self.delivered(storage) })
            #expect(server.pushSubscriptionRequests.count == 2)
        }

        @Test("a transport error (no HTTP response) is retried")
        func retriesTransportErrorThenSucceeds() async throws {
            let lock = NSLock()
            var requestCount = 0
            server.pushSubscriptionResponseHandler = { _ in
                let count = lock.withLock { () -> Int in
                    requestCount += 1
                    return requestCount
                }
                if count == 1 {
                    let networkError = NSError(domain: NSURLErrorDomain, code: NSURLErrorTimedOut, userInfo: nil)
                    return HTTPStubsResponse(error: networkError)
                }
                return HTTPStubsResponse(jsonObject: ["distinct_id": "test", "platform": "ios"], statusCode: 200, headers: nil)
            }
            let (handler, storage, _) = makeHandler()

            handler.send(deviceToken: "tok", appId: "app")
            #expect(await waitFor { handler.retryCountForTesting == 1 })
            #expect(!delivered(storage))

            handler.clearBackoffForTesting()
            handler.retryIfNeeded()

            #expect(await waitFor { self.delivered(storage) })
            #expect(server.pushSubscriptionRequests.count == 2)
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

        // MARK: - Identity verification (vectors 9–14)

        @Test("provider token lands as identity_token on register POST and unregister DELETE (vector 9)")
        func identityTokenOnRegisterAndUnregister() async throws {
            let (handler, storage, config) = makeHandler(distinctIdProvider: { "user-1" })
            // Complete from a foreign thread — the provider contract allows any thread.
            config.pushIdentityProvider = { _, _, completion in
                DispatchQueue.global().async { completion("jwt-abc") }
            }

            handler.send(deviceToken: "tok", appId: "com.example.app")
            #expect(await waitFor { self.delivered(storage) })

            let post = try #require(server.pushSubscriptionRequests.first { $0.httpMethod == "POST" })
            let postBody = try #require(server.parseRequest(post))
            #expect(postBody["identity_token"] as? String == "jwt-abc")
            #expect(postBody["api_key"] as? String == testProjectToken)
            #expect(postBody["distinct_id"] as? String == "user-1")
            #expect(postBody["device_token"] as? String == "tok")
            #expect(postBody["platform"] as? String == "ios")
            #expect(postBody["app_id"] as? String == "com.example.app")

            handler.unregisterCurrentToken()

            #expect(await waitFor { self.server.pushSubscriptionRequests.contains { $0.httpMethod == "DELETE" } })
            let del = try #require(server.pushSubscriptionRequests.first { $0.httpMethod == "DELETE" })
            #expect(try #require(server.parseRequest(del))["identity_token"] as? String == "jwt-abc")
        }

        @Test("no provider: bodies contain no identity_token key (vector 10)")
        func noProviderOmitsIdentityToken() async throws {
            let (handler, storage, _) = makeHandler(distinctIdProvider: { "user-1" })

            handler.send(deviceToken: "tok", appId: "com.example.app")
            #expect(await waitFor { self.delivered(storage) })
            handler.unregisterCurrentToken()
            #expect(await waitFor { self.server.pushSubscriptionRequests.count == 2 })

            for request in server.pushSubscriptionRequests {
                let body = try #require(server.parseRequest(request))
                #expect(!body.keys.contains("identity_token"))
            }
        }

        @Test("provider completing nil: body contains no identity_token key (vector 10)")
        func nilCompletionOmitsIdentityToken() async throws {
            let (handler, storage, config) = makeHandler()
            config.pushIdentityProvider = { _, _, completion in completion(nil) }

            handler.send(deviceToken: "tok", appId: "app")

            #expect(await waitFor { self.delivered(storage) })
            let body = try #require(server.parseRequest(server.pushSubscriptionRequests[0]))
            #expect(!body.keys.contains("identity_token"))
        }

        @Test("a provider that never completes falls back to a token-less send instead of wedging")
        func neverCompletingProviderFallsBackTokenLess() async throws {
            let (handler, storage, config) = makeHandler()
            handler.identityTokenMintTimeout = 0.05
            config.pushIdentityProvider = { _, _, _ in } // never calls completion

            handler.send(deviceToken: "tok-1", appId: "app")
            #expect(await waitFor { self.delivered(storage) })
            let firstPost = try #require(server.pushSubscriptionRequests.first { $0.httpMethod == "POST" })
            #expect(!(try #require(server.parseRequest(firstPost))).keys.contains("identity_token"))

            // isSending was released by the fallback, so a later registration is not wedged.
            handler.send(deviceToken: "tok-2", appId: "app")
            #expect(await waitFor { self.server.pushSubscriptionRequests.filter { $0.httpMethod == "POST" }.count == 2 })
            let secondPost = server.pushSubscriptionRequests.filter { $0.httpMethod == "POST" }[1]
            #expect(try #require(server.parseRequest(secondPost))["device_token"] as? String == "tok-2")
        }

        @Test("only the first provider completion is honored")
        func onlyFirstProviderCompletionHonored() async throws {
            let (handler, storage, config) = makeHandler()
            config.pushIdentityProvider = { _, _, completion in
                completion("jwt-first")
                completion("jwt-second")
            }

            handler.send(deviceToken: "tok", appId: "app")

            #expect(await waitFor { self.delivered(storage) })
            #expect(server.pushSubscriptionRequests.count == 1)
            let body = try #require(server.parseRequest(server.pushSubscriptionRequests[0]))
            #expect(body["identity_token"] as? String == "jwt-first")
        }

        @Test("a mint completing after opt-out is not cached; opt-in re-mints")
        func lateMintAfterOptOutNotCached() async throws {
            // The provider is invoked off the caller's thread, so guard the shared state with a lock
            // and wait for each mint to land before driving its completion.
            let lock = NSLock()
            var allowed = true
            var pendingCompletion: ((String?) -> Void)?
            var mints = 0
            let (handler, storage, config) = makeHandler(isAllowedProvider: { lock.withLock { allowed } })
            config.pushIdentityProvider = { _, _, completion in
                lock.withLock { mints += 1
                    pendingCompletion = completion
                }
            }

            handler.send(deviceToken: "tok", appId: "app")
            #expect(await waitFor { lock.withLock { mints } == 1 })
            lock.withLock { allowed = false }
            handler.onOptOut()
            lock.withLock { pendingCompletion }?("jwt-stale")

            lock.withLock { allowed = true }
            handler.send(deviceToken: "tok", appId: "app")
            #expect(await waitFor { lock.withLock { mints } == 2 })
            lock.withLock { pendingCompletion }?("jwt-fresh")

            #expect(await waitFor { self.delivered(storage) })
            #expect(lock.withLock { mints } == 2)
            let post = try #require(server.pushSubscriptionRequests.last)
            #expect(try #require(server.parseRequest(post))["identity_token"] as? String == "jwt-fresh")
        }

        @Test("500 then 200: provider minted once, both attempts carry the same token (vector 12)")
        func retryReusesCachedIdentityToken() async throws {
            server.pushSubscriptionStatusHandler = { requestNumber in requestNumber == 1 ? 500 : 200 }
            let recorder = MintRecorder()
            let (handler, storage, config) = makeHandler()
            config.pushIdentityProvider = { distinctId, appId, completion in
                completion("jwt-mint-\(recorder.record(distinctId, appId))")
            }

            handler.send(deviceToken: "tok", appId: "app")
            #expect(await waitFor { handler.retryCountForTesting == 1 })

            handler.clearBackoffForTesting()
            handler.retryIfNeeded()

            #expect(await waitFor { self.delivered(storage) })
            #expect(server.pushSubscriptionRequests.count == 2)
            #expect(recorder.count == 1)
            for request in server.pushSubscriptionRequests {
                let body = try #require(server.parseRequest(request))
                #expect(body["identity_token"] as? String == "jwt-mint-1")
            }
        }

        @Test("401 then 200: one fresh-token retry with a re-minted token succeeds (vector 13)")
        func authRetryWithFreshTokenSucceeds() async throws {
            server.pushSubscriptionStatusHandler = { requestNumber in requestNumber == 1 ? 401 : 200 }
            let recorder = MintRecorder()
            let (handler, storage, config) = makeHandler()
            config.pushIdentityProvider = { distinctId, appId, completion in
                completion("jwt-mint-\(recorder.record(distinctId, appId))")
            }

            handler.send(deviceToken: "tok", appId: "app")

            #expect(await waitFor { self.delivered(storage) })
            #expect(server.pushSubscriptionRequests.count == 2)
            #expect(recorder.count == 2)
            let first = try #require(server.parseRequest(server.pushSubscriptionRequests[0]))
            #expect(first["identity_token"] as? String == "jwt-mint-1")
            let second = try #require(server.parseRequest(server.pushSubscriptionRequests[1]))
            #expect(second["identity_token"] as? String == "jwt-mint-2")
        }

        @Test("401 twice: terminal after exactly two requests and two mints, record kept (vector 13)")
        func secondAuthFailureIsTerminal() async throws {
            server.pushSubscriptionStatusCode = 401
            let recorder = MintRecorder()
            let (handler, storage, config) = makeHandler()
            config.pushIdentityProvider = { distinctId, appId, completion in
                completion("jwt-mint-\(recorder.record(distinctId, appId))")
            }

            handler.send(deviceToken: "tok", appId: "app")

            #expect(await waitFor { handler.isHaltedForTesting })
            #expect(server.pushSubscriptionRequests.count == 2)
            #expect(recorder.count == 2)

            // No further in-session attempts while halted.
            handler.clearBackoffForTesting()
            handler.retryIfNeeded()
            try await Task.sleep(nanoseconds: 200_000_000)
            #expect(server.pushSubscriptionRequests.count == 2)

            #expect(record(storage)?["deviceToken"] == "tok")
            #expect(!delivered(storage))
        }

        @Test("a resend coalesced during a 401 auth-retry doesn't reopen the one-retry cap (no mint loop)")
        func coalescedResendDoesNotBreakAuthRetryCap() async throws {
            // Every request 401s. Hold the first mint open so a second registration coalesces into
            // pendingResend while the original send is in flight; releasing it drives the 401 cascade.
            // Under the bug, servicing the coalesced resend reset didAuthRetry out from under the
            // in-flight auth-retry, granting an unbounded chain of fresh-token retries that never halts.
            server.pushSubscriptionStatusCode = 401
            let recorder = MintRecorder()
            let lock = NSLock()
            var firstCompletion: ((String?) -> Void)?
            let (handler, _, config) = makeHandler()
            config.pushIdentityProvider = { distinctId, appId, completion in
                let n = recorder.record(distinctId, appId)
                if n == 1 {
                    lock.withLock { firstCompletion = completion }
                } else {
                    DispatchQueue.global().async { completion("jwt-mint-\(n)") }
                }
            }

            // `isSending` is claimed synchronously in send #1, so send #2 coalesces into pendingResend
            // before mint #1 (which runs off-thread) completes. Wait for that mint, then release it.
            handler.send(deviceToken: "tok-1", appId: "app")
            handler.send(deviceToken: "tok-2", appId: "app")
            #expect(await waitFor { recorder.count >= 1 })
            lock.withLock { firstCompletion }?("jwt-mint-1")

            // Fix: R1(tok-1) + its one auth-retry, then the resend cycle R3(tok-2) + its one
            // auth-retry — four requests, then terminal. The bug never halts and requests run away.
            #expect(await waitFor { handler.isHaltedForTesting })
            try await Task.sleep(nanoseconds: 300_000_000)
            #expect(server.pushSubscriptionRequests.count == 4)
            #expect(recorder.count <= 4)
        }

        @Test("401 with no provider: terminal after one request, record kept (vector 14)")
        func unauthorizedWithoutProviderIsTerminal() async throws {
            server.pushSubscriptionStatusCode = 401
            let (handler, storage, _) = makeHandler()

            handler.send(deviceToken: "tok", appId: "app")

            #expect(await waitFor { handler.isHaltedForTesting })
            #expect(server.pushSubscriptionRequests.count == 1)
            #expect(record(storage)?["deviceToken"] == "tok")
            #expect(!delivered(storage))
        }

        @Test("unregister DELETE gets one 401 fresh-token retry then succeeds (mirrors register vector 13)")
        func unregisterAuthRetryWithFreshTokenSucceeds() async throws {
            // A same-process logout can carry an expired cached token; a 401 must re-mint and retry once.
            server.pushSubscriptionStatusHandler = { requestNumber in requestNumber == 1 ? 401 : 200 }
            let recorder = MintRecorder()
            let (handler, _, config) = makeHandler(distinctIdProvider: { "user-1" })
            config.pushIdentityProvider = { distinctId, appId, completion in
                completion("jwt-mint-\(recorder.record(distinctId, appId))")
            }

            handler.unregister(distinctId: "user-1", deviceToken: "tok", appId: "app")

            #expect(await waitFor { self.server.pushSubscriptionRequests.filter { $0.httpMethod == "DELETE" }.count == 2 })
            #expect(recorder.count == 2) // cache cleared on the 401, so the retry re-mints
            let deletes = server.pushSubscriptionRequests.filter { $0.httpMethod == "DELETE" }
            #expect(try #require(server.parseRequest(deletes[0]))["identity_token"] as? String == "jwt-mint-1")
            #expect(try #require(server.parseRequest(deletes[1]))["identity_token"] as? String == "jwt-mint-2")
            // Success on the retry clears the durable intent.
            #expect(await waitFor { !handler.hasPendingUnregisterForTesting })
        }

        @Test("unregister twice-401 is terminal: exactly one fresh-token retry, then intent dropped")
        func unregisterAuthRetryTerminalDropsIntent() async throws {
            server.pushSubscriptionStatusCode = 401
            let recorder = MintRecorder()
            let (handler, _, config) = makeHandler(distinctIdProvider: { "user-1" })
            config.pushIdentityProvider = { distinctId, appId, completion in
                completion("jwt-mint-\(recorder.record(distinctId, appId))")
            }

            handler.unregister(distinctId: "user-1", deviceToken: "tok", appId: "app")

            #expect(await waitFor { self.server.pushSubscriptionRequests.filter { $0.httpMethod == "DELETE" }.count == 2 })
            try await Task.sleep(nanoseconds: 300_000_000)
            #expect(server.pushSubscriptionRequests.filter { $0.httpMethod == "DELETE" }.count == 2)
            #expect(recorder.count == 2)
            // A terminal 401 is a best-effort ceiling — the intent is dropped, not retried on flush.
            #expect(!handler.hasPendingUnregisterForTesting)
        }

        @Test("unregister offline persists the intent and drains it on retryIfNeeded")
        func unregisterOfflinePersistsAndDrains() async throws {
            var connected = false
            let (handler, _, _) = makeHandler(distinctIdProvider: { "user-1" }, isConnectedProvider: { connected })

            handler.unregister(distinctId: "user-1", deviceToken: "tok", appId: "app")

            try await Task.sleep(nanoseconds: 200_000_000)
            #expect(server.pushSubscriptionRequests.isEmpty) // no attempt while offline
            #expect(handler.hasPendingUnregisterForTesting) // but the delete intent is durable

            connected = true
            handler.retryIfNeeded()
            #expect(await waitFor { self.server.pushSubscriptionRequests.contains { $0.httpMethod == "DELETE" } })
            #expect(await waitFor { !handler.hasPendingUnregisterForTesting }) // cleared on 2xx
        }

        @Test("retryIfNeeded drops a pending unregister for the current identity when a registration is queued")
        func retryDropsSameIdentityUnregisterWhenRegistrationQueued() async throws {
            var connected = false
            let (handler, _, _) = makeHandler(distinctIdProvider: { "user-1" }, isConnectedProvider: { connected })

            // Log out of user-1 while offline, then re-register for the same identity.
            handler.unregister(distinctId: "user-1", deviceToken: "tok", appId: "app")
            handler.send(deviceToken: "tok", appId: "app")

            try await Task.sleep(nanoseconds: 200_000_000)
            #expect(server.pushSubscriptionRequests.isEmpty)
            #expect(handler.hasPendingUnregisterForTesting)

            connected = true
            handler.retryIfNeeded()

            // Register supersedes the queued DELETE: only the POST goes out, the intent is dropped.
            #expect(await waitFor { self.server.pushSubscriptionRequests.count == 1 })
            #expect(server.pushSubscriptionRequests[0].httpMethod == "POST")
            #expect(!handler.hasPendingUnregisterForTesting)
        }

        @Test("unregister drops the pending intent on a terminal 4xx")
        func unregisterTerminalDropsIntent() async throws {
            server.pushSubscriptionStatusCode = 400
            let (handler, _, _) = makeHandler(distinctIdProvider: { "user-1" })

            handler.unregister(distinctId: "user-1", deviceToken: "tok", appId: "app")

            #expect(await waitFor { self.server.pushSubscriptionRequests.contains { $0.httpMethod == "DELETE" } })
            #expect(await waitFor { !handler.hasPendingUnregisterForTesting })
        }

        @Test("re-registering the same identity cancels a queued unregister for it")
        func reRegisterCancelsPendingUnregister() async throws {
            var connected = false
            let (handler, _, _) = makeHandler(distinctIdProvider: { "user-A" }, isConnectedProvider: { connected })

            // Offline logout queues a durable unregister for user-A.
            handler.unregister(distinctId: "user-A", deviceToken: "tok", appId: "app")
            try await Task.sleep(nanoseconds: 150_000_000)
            #expect(handler.hasPendingUnregisterForTesting)

            // Re-login as user-A: a delivered registration must supersede the stale logout-DELETE.
            connected = true
            handler.send(deviceToken: "tok", appId: "app")
            #expect(await waitFor { !handler.hasPendingUnregisterForTesting })

            // A later flush must not delete the freshly re-registered subscription.
            let deletesBefore = server.pushSubscriptionRequests.filter { $0.httpMethod == "DELETE" }.count
            handler.retryIfNeeded()
            try await Task.sleep(nanoseconds: 200_000_000)
            #expect(server.pushSubscriptionRequests.filter { $0.httpMethod == "DELETE" }.count == deletesBefore)
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

        @Test("resendIfDistinctIdChanged's disk read never runs on the caller's (main) thread")
        func resendRunsOffCallerThread() async throws {
            var distinctId = "user-1"
            let contextChanged = PostHogMulticastCallback<[String: Any]>()
            let (handler, storage, _) = makeHandler(
                distinctIdProvider: { distinctId },
                onEventContextChanged: contextChanged
            )

            handler.send(deviceToken: "tok", appId: "app")
            #expect(await waitFor { self.delivered(storage) })

            final class Observation: @unchecked Sendable {
                private let lock = NSLock()
                private var value: Bool?
                func record(_ isMainThread: Bool) {
                    lock.withLock { value = isMainThread }
                }
                var ranOnMainThread: Bool? { lock.withLock { value } }
            }
            let observation = Observation()
            handler.onResendForTesting = { isMainThread in
                observation.record(isMainThread)
            }

            // Mirrors how screen() actually fires this: synchronously on the calling (main) thread.
            distinctId = "user-2"
            await MainActor.run {
                contextChanged.invoke(["distinct_id": "user-2"])
            }

            #expect(await waitFor { observation.ranOnMainThread != nil })
            #expect(observation.ranOnMainThread == false)
        }

        // MARK: - SDK-level device token API

        #if os(iOS)
            @Test("registerPushNotificationToken with an explicit appId sends a request")
            func sdkHandleDeviceTokenWithExplicitAppId() async throws {
                let sut = getSDK()
                defer { sut.close() }

                sut.registerPushNotificationToken("deadbeef01", appId: "com.example.app")

                #expect(await waitFor { self.server.pushSubscriptionRequests.count == 1 })
                let body = try #require(server.parseRequest(server.pushSubscriptionRequests[0]))
                #expect(body["device_token"] as? String == "deadbeef01")
                #expect(body["app_id"] as? String == "com.example.app")
                #expect(body["platform"] as? String == "ios")
            }

            @Test("opted out: registerPushNotificationToken sends no request (vector 6)")
            func sdkRegistrationNoRequestWhenOptedOut() async throws {
                let sut = getSDK(optOut: true)
                defer { sut.close() }

                sut.registerPushNotificationToken("deadbeef", appId: "com.example.app")

                try await Task.sleep(nanoseconds: 300_000_000)
                #expect(server.pushSubscriptionRequests.isEmpty)
            }

            @Test("unregisterPushNotificationToken fires a DELETE for a previously-registered token")
            func sdkUnregisterFiresDelete() async throws {
                let sut = getSDK()
                defer { sut.close() }

                sut.registerPushNotificationToken("deadbeef01", appId: "com.example.app")
                #expect(await waitFor { self.server.pushSubscriptionRequests.count == 1 })

                sut.unregisterPushNotificationToken()

                #expect(await waitFor { self.server.pushSubscriptionRequests.contains { $0.httpMethod == "DELETE" } })
            }

            @Test("opted out: unregisterPushNotificationToken sends no request")
            func sdkUnregisterNoRequestWhenOptedOut() async throws {
                let sut = getSDK(optOut: true)
                defer { sut.close() }

                sut.unregisterPushNotificationToken()

                try await Task.sleep(nanoseconds: 300_000_000)
                #expect(server.pushSubscriptionRequests.isEmpty)
            }
        #endif

        @Test("flush retries a persisted subscription and marks it delivered")
        func sdkFlushRetriesPersistedSubscription() async throws {
            let sut = getSDK()
            defer { sut.close() }

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
        }

        @Test("opted out: flush does not retry a persisted subscription (vector 6)")
        func optedOutFlushDoesNotRetry() async throws {
            let sut = getSDK(optOut: true)
            defer { sut.close() }

            sut.storage?.setDictionary(forKey: .pushSubscription, contents: [
                "deviceToken": "deadbeef",
                "appId": "com.example.test",
            ])

            sut.flush()

            try await Task.sleep(nanoseconds: 300_000_000)
            #expect(server.pushSubscriptionRequests.isEmpty)
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
            storage.remove(key: .pushPendingUnregister)
            storage.setDictionary(forKey: .pushSubscription, contents: [
                "deviceToken": "tok-from-last-launch",
                "appId": "com.example.test",
            ])

            let sut = PostHogSDK.with(config)

            #expect(await waitFor { self.server.pushSubscriptionRequests.count == 1 })
            let body = try #require(server.parseRequest(server.pushSubscriptionRequests[0]))
            #expect(body["device_token"] as? String == "tok-from-last-launch")
        }

        @Test("reset re-registers the persisted push subscription instead of dropping it (decision 5/6)")
        func sdkResetReregistersPersistedSubscription() {
            let sut = getSDK()
            defer { sut.close() }

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
        }

        // MARK: - Opened capture property mapping (vectors 1, 2, 6)

        @Test("captures $push_notification_opened with the posthog payload flattened (vector 1)")
        func openCaptureFlattensPosthogPayload() async throws {
            let sut = getSDK()
            defer { sut.close() }

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
        }

        @Test("parses a JSON-string posthog payload (FCM relay path)")
        func openCaptureParsesPosthogJSONString() async throws {
            let sut = getSDK()
            defer { sut.close() }

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
        }

        @Test("ignores a posthog payload string that is not a JSON object")
        func openCaptureIgnoresInvalidPosthogString() async throws {
            let sut = getSDK()
            defer { sut.close() }

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
        }

        @Test("captures only base notification props when there is no posthog payload (vector 2)")
        func openCaptureBasePropsOnly() async throws {
            let sut = getSDK()
            defer { sut.close() }

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
        }

        @Test("omits empty subtitle and body")
        func openCaptureOmitsEmptyFields() async throws {
            let sut = getSDK()
            defer { sut.close() }

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
        }

        @Test("omits an empty title")
        func openCaptureOmitsEmptyTitle() async throws {
            let sut = getSDK()
            defer { sut.close() }

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
        }

        @Test("includes the action identifier when it is non-default")
        func openCaptureIncludesCustomAction() async throws {
            let sut = getSDK()
            defer { sut.close() }

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
        }

        @Test("all-nil arguments capture the event with no notification properties")
        func openCaptureAllNilArguments() async throws {
            let sut = getSDK()
            defer { sut.close() }

            sut.capturePushNotificationOpened()

            let events = getBatchedEvents(server)
            let event = try #require(events.first)
            #expect(event.event == "$push_notification_opened")
            #expect(event.properties.keys.filter { $0.hasPrefix("$notification_") }.isEmpty)
        }

        @Test("opted out: no $push_notification_opened event is captured (vector 6)")
        func openCaptureNoEventWhenOptedOut() async throws {
            let sut = getSDK(optOut: true)
            defer { sut.close() }

            sut.capturePushNotificationOpened(
                title: "Hello",
                subtitle: "Sub",
                body: "Body",
                payload: [:],
                action: nil
            )

            try await Task.sleep(nanoseconds: 300_000_000)
            #expect(server.batchRequests.isEmpty)
        }

        @Test("manual open-capture works when swizzling is disabled")
        func openCaptureWorksWithoutSwizzling() async throws {
            let sut = getSDK(enableSwizzling: false, capturePushNotificationOpened: true)
            defer { sut.close() }

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
        }
    }

#endif
