#if os(iOS) || os(macOS)

    import Foundation
    import OHHTTPStubs
    import OHHTTPStubsSwift
    @testable import PostHog
    import Testing

    // Reproductions for the opt-out / unregister bugs found during the RN push review:
    // - posthog-ios#746: opt-out during an in-flight unregister strands the DELETE.
    // Each test asserts the FIXED behavior, so it fails today (= reproduces the bug) and will pass once fixed.
    @Suite("Push opt-out / unregister bug repros", .serialized)
    final class PostHogPushOptOutReproTest {
        var server: MockPostHogServer!

        init() {
            server = MockPostHogServer()
            server.start()
        }

        deinit {
            server.stop()
            server = nil
        }

        /// Parks the first identity mint so the test controls when it completes.
        private final class ParkedMint: @unchecked Sendable {
            private let lock = NSLock()
            private var parked: ((String?) -> Void)?
            private var didPark = false
            func parkFirst(_ completion: @escaping (String?) -> Void) -> Bool {
                lock.withLock {
                    guard !didPark else { return false }
                    didPark = true
                    parked = completion
                    return true
                }
            }
            func release(_ token: String?) {
                let c = lock.withLock { () -> ((String?) -> Void)? in let c = parked
                    parked = nil
                    return c
                }
                c?(token)
            }
            var isParked: Bool { lock.withLock { parked != nil } }
        }

        private func waitFor(_ condition: @escaping () -> Bool, timeout: TimeInterval = 5) async -> Bool {
            let deadline = Date().addingTimeInterval(timeout)
            while Date() < deadline {
                if condition() { return true }
                try? await Task.sleep(nanoseconds: 20_000_000)
            }
            return condition()
        }

        private func delivered(_ storage: PostHogStorage) -> Bool {
            (storage.getDictionary(forKey: .pushSubscription) as? [String: String])?["deliveredForDistinctId"] != nil
        }

        @available(iOS 14.0, macOS 11.0, *)
        @Test("posthog-ios#746: opt-out during an in-flight unregister must still send the DELETE")
        func optOutDuringUnregisterStrandsDelete() async throws {
            let parked = ParkedMint()
            let lock = NSLock()
            var allowed = true
            func isAllowed() -> Bool {
                lock.withLock { allowed }
            }

            let config = PostHogConfig(projectToken: testProjectToken, host: "http://localhost:9001")
            config.maxRetries = 3
            config.disableReachabilityForTesting = true
            let api = PostHogApi(config)
            let storage = PostHogStorage(config)
            storage.reset()
            storage.remove(key: .pushPendingUnregister)
            storage.remove(key: .pushSubscription)

            let handler = PostHogPushSubscriptionHandler(
                api,
                storage,
                config,
                distinctIdProvider: { "user-1" },
                isConnectedProvider: { true },
                isAllowedProvider: { isAllowed() },
                isEnabledProvider: { true }, // SDK stays enabled; only opt-out flips via isAllowed()
                onEventContextChanged: .init()
            )
            handler.identityTokenMintTimeout = 60 // keep the watchdog from firing before we release

            func posts() -> Int {
                server.pushSubscriptionRequests.filter { $0.httpMethod == "POST" }.count
            }
            func deletes() -> Int {
                server.pushSubscriptionRequests.filter { $0.httpMethod == "DELETE" }.count
            }

            // 1) Register the device token while allowed. No provider set, so no identity mint.
            handler.send(deviceToken: "abcdef", appId: "com.example.app")
            #expect(await waitFor { self.delivered(storage) })
            #expect(posts() == 1)
            #expect(deletes() == 0)

            // 2) The wrapper's opt-out flow: unregister, then opt out. Attach a provider that parks the
            //    unregister's mint so the opt-out lands while the DELETE is in flight (the reported race).
            config.pushIdentityProvider = { _, _, completion in
                if !parked.parkFirst(completion) { completion(nil) }
            }
            // unregisterCurrentToken() is the logout path: it clears the stored record first, so the
            // post-mint supersede rule can't cancel the DELETE — isolating the opt-out gate.
            handler.unregisterCurrentToken()
            #expect(await waitFor { parked.isParked }, "unregister should reach the identity mint")
            lock.withLock { allowed = false } // opt-out flips the consent gate mid-flight
            parked.release("identity-token") // let the mint complete

            // A DELETE is data removal, so opt-out must not block it. This fails today: the post-mint
            // isAllowedProvider() gate returns early, the DELETE never goes out, and the server-side
            // subscription stays active for the whole opted-out period.
            let sawDelete = await waitFor { deletes() == 1 }
            #expect(sawDelete, "posthog-ios#746: opt-out stranded the unregister DELETE; subscription stays active")
        }
    }

#endif
