//
//  PostHogRemoteConfigTest.swift
//  PostHog
//
//  Created by Yiannis Josephides on 20/01/2025.
//

@testable import PostHog
import Testing
import XCTest

@Suite("Test Remote Config", .serialized)
enum PostHogRemoteConfigTest {
    class BaseTestClass {
        let config: PostHogConfig = {
            let c = PostHogConfig(projectToken: testProjectToken, host: "http://localhost:9001")
            c.disableRemoteConfigForTesting = true
            return c
        }()

        var server: MockPostHogServer!

        init() {
            server = MockPostHogServer()
            server.start()
            // important!
            let storage = PostHogStorage(config)
            storage.reset()
            // reset() intentionally KEEPS .remoteConfig (project-level config survives an identity
            // change). These suites share on-disk storage, so clear it explicitly to isolate tests.
            storage.remove(key: .remoteConfig)
        }

        deinit {
            server.stop()
            server = nil
        }

        func getSut(
            storage: PostHogStorage? = nil,
            config: PostHogConfig? = nil,
            featureFlagCalledCallback: ((_ flagKey: String, _ flagValue: Any?) -> Void)? = nil
        ) -> PostHogRemoteConfig {
            let theConfig = config ?? self.config
            let theStorage = storage ?? PostHogStorage(theConfig)
            let api = PostHogApi(theConfig)
            return PostHogRemoteConfig(theConfig, theStorage, api, { [:] }, featureFlagCalledCallback)
        }

        // async bridges over the SDK's callback-based reload APIs.
        func reloadRemoteConfig(_ sut: PostHogRemoteConfig) async {
            await withCheckedContinuation { continuation in
                sut.reloadRemoteConfig { _ in continuation.resume() }
            }
        }

        func loadFeatureFlags(_ sut: PostHogRemoteConfig) async {
            await withCheckedContinuation { continuation in
                sut.loadFeatureFlags(distinctId: "distinctId", anonymousId: "anonymousId", groups: ["group": "value"]) { _ in
                    continuation.resume()
                }
            }
        }

        func reloadConfigThenFlags(_ sut: PostHogRemoteConfig) async {
            await reloadRemoteConfig(sut)
            await loadFeatureFlags(sut)
        }
    }

    @Suite("Test remote config loading")
    class TestRemoteConfigLoading: BaseTestClass {
        @Test("loads cached remote config")
        func loadsCachedRemoteConfig() {
            let storage = PostHogStorage(config)
            defer { storage.reset() }

            storage.setDictionary(forKey: .remoteConfig, contents: ["foo": "bar"])

            let sut = getSut(storage: storage)

            #expect(sut.getRemoteConfig() as? [String: String] == ["foo": "bar"])
        }

        @Test("remote config survives reset (project-level config)")
        func remoteConfigSurvivesReset() {
            let storage = PostHogStorage(config)
            defer { storage.reset() }

            storage.setDictionary(forKey: .remoteConfig, contents: ["errorTracking": ["autocaptureExceptions": true]])

            storage.reset()

            #expect(storage.getDictionary(forKey: .remoteConfig) != nil)
        }

        @Test("remote config fetches feature flags if missing")
        func remoteConfigLoadsFeatureFlagsIfNotPreviouslyLoaded() async {
            let config = PostHogConfig(projectToken: testProjectToken, host: "http://localhost:9001")
            config.preloadFeatureFlags = true
            config.storageManager = PostHogStorageManager(config)
            let sut = getSut(config: config)

            let bothLoaded = AsyncLatch(count: 2)
            let token1 = sut.onFeatureFlagsLoaded.subscribe { _ in
                bothLoaded.signal()
            }
            let token2 = sut.onRemoteConfigLoaded.subscribe { _ in
                bothLoaded.signal()
            }

            await bothLoaded.wait()

            #expect(sut.getRemoteConfig() != nil)
            #expect(sut.getFeatureFlags() != nil)

            _ = (token1, token2) // silence read warnings
        }

        @Test("remote config does not fetch feature flags if preloadFeatureFlags is disabled")
        func remoteConfigDoesNotFetchFeatureFlagsIfPreloadFeatureFlagsIsDisabled() async throws {
            let config = PostHogConfig(projectToken: testProjectToken, host: "http://localhost:9001")
            config.preloadFeatureFlags = false
            config.storageManager = PostHogStorageManager(config)
            let sut = getSut(config: config)

            var featureFlagsLoaded = false
            let remoteConfigLoaded = AsyncLatch()

            let token1 = sut.onFeatureFlagsLoaded.subscribe { _ in
                featureFlagsLoaded = true
            }
            let token2 = sut.onRemoteConfigLoaded.subscribe { _ in
                remoteConfigLoaded.signal()
            }

            await remoteConfigLoaded.wait()

            #expect(featureFlagsLoaded == false)
            #expect(sut.getRemoteConfig() != nil)
            #expect(sut.getFeatureFlags() == nil)

            _ = (token1, token2) // silence read warnings
        }

        @Test("remote config fetches feature flags on init even if flags are cached")
        func remoteConfigFetchesFeatureFlagsOnInitEvenIfFlagsAreCached() async throws {
            let storage = PostHogStorage(config)
            defer { storage.reset() }

            // set cached flag
            storage.setDictionary(forKey: .enabledFeatureFlags, contents: ["some-flag": true])
            // return flipped cached flag
            server.featureFlags = ["some-flag": false]

            let config = PostHogConfig(projectToken: testProjectToken, host: "http://localhost:9001")
            config.preloadFeatureFlags = true
            config.storageManager = PostHogStorageManager(config)

            let sut = getSut(storage: storage, config: config)

            var featureFlagsLoaded = false
            let flagsLoaded = AsyncLatch()
            let token = sut.onFeatureFlagsLoaded.subscribe { _ in
                featureFlagsLoaded = true
                flagsLoaded.signal()
            }

            #expect(sut.getFeatureFlag("some-flag") as? Bool == true)

            // wait for flags to be loaded
            await flagsLoaded.wait()

            // test for new value
            #expect(featureFlagsLoaded == true)
            #expect(sut.getFeatureFlag("some-flag") as? Bool == false)
            _ = token // silence read warnings
        }

        @Test("remote config clears cached flags when hasFeatureFlags is false")
        func remoteConfigClearsCachedFlagsWhenHasFeatureFlagsIsFalse() async throws {
            // return flipped cached flag
            server.hasFeatureFlags = false
            server.featureFlags = [:]

            let config = PostHogConfig(projectToken: testProjectToken, host: "http://localhost:9001")
            config.preloadFeatureFlags = false
            config.storageManager = PostHogStorageManager(config)

            let storage = PostHogStorage(config)
            defer { storage.reset() }

            // set cached flag
            storage.setDictionary(forKey: .flags, contents: ["some-flag": true])
            storage.setDictionary(forKey: .enabledFeatureFlags, contents: ["some-flag": true])
            storage.setDictionary(forKey: .enabledFeatureFlagPayloads, contents: ["some-flag": true])

            let sut = getSut(storage: storage, config: config)

            let remoteConfigLoaded = AsyncLatch()
            let token = sut.onRemoteConfigLoaded.subscribe { _ in
                remoteConfigLoaded.signal()
            }

            await remoteConfigLoaded.wait()

            // The cache clearing runs asynchronously after onRemoteConfigLoaded fires and isn't tied to
            // any callback we can await, so poll the end state — returns the instant it clears rather
            // than blocking on a fixed delay.
            await waitUntil { storage.getDictionary(forKey: .enabledFeatureFlags).isNilOrEmpty }

            // test for empty cache
            #expect(storage.getDictionary(forKey: .flags).isNilOrEmpty == true)
            #expect(storage.getDictionary(forKey: .enabledFeatureFlags).isNilOrEmpty == true)
            #expect(storage.getDictionary(forKey: .enabledFeatureFlagPayloads).isNilOrEmpty == true)

            _ = token // silence read warnings
        }

        @Test("should not clear flags if remote config call fails")
        func shouldNotClearFlagsIfRemoteConfigCallFails() async {
            let config = PostHogConfig(projectToken: testProjectToken, host: "http://localhost:9001")
            config.preloadFeatureFlags = true

            let storage = PostHogStorage(config)
            defer { storage.reset() }

            storage.setDictionary(forKey: .enabledFeatureFlags, contents: ["foo": true])

            // simulate a net call failure
            server.return500 = true

            let sut = getSut(storage: storage, config: config)

            let featureFlagsLoaded = AsyncLatch()
            let token = sut.onFeatureFlagsLoaded.subscribe { _ in
                featureFlagsLoaded.signal()
            }

            // wait for flags to load
            await featureFlagsLoaded.wait()

            // check that cached flag was not removed
            #expect(sut.getFeatureFlag("foo") as? Bool == true)

            _ = token // silence read warnings
        }

        @Test("should not clear flags if hasFeatureFlags key is missing")
        func shouldNotClearFlagsIfHasFeatureFlagsKeyIsMissing() async {
            let config = PostHogConfig(projectToken: testProjectToken, host: "http://localhost:9001")
            config.preloadFeatureFlags = true

            let storage = PostHogStorage(config)
            defer { storage.reset() }

            storage.setDictionary(forKey: .enabledFeatureFlags, contents: ["foo": true])

            // removes `hasFeatureFlags` from response
            server.hasFeatureFlags = nil

            let sut = getSut(storage: storage, config: config)

            let featureFlagsLoaded = AsyncLatch()
            let token = sut.onFeatureFlagsLoaded.subscribe { _ in
                featureFlagsLoaded.signal()
            }

            // wait for flags to load
            await featureFlagsLoaded.wait()

            // check that cached flag was not removed
            #expect(sut.getFeatureFlag("foo") as? Bool == true)

            _ = token // silence read warnings
        }
    }

    @Suite("Test Feature Flag Loading Race Condition")
    class TestFeatureFlagLoadingRaceCondition: BaseTestClass {
        @Test("guard prevents concurrent requests and queues pending")
        func guardPreventsConcurrentRequestsAndQueuesPending() async {
            let config = PostHogConfig(projectToken: testProjectToken, host: "http://localhost:9001")
            config.preloadFeatureFlags = false
            config.storageManager = PostHogStorageManager(config)
            let sut = getSut(config: config)
            sut.canReloadFlagsForTesting = true

            server.flagsResponseDelay = 1.0

            var firstDone = false
            var secondDone = false
            let bothDone = AsyncLatch(count: 2)

            sut.loadFeatureFlags(distinctId: "first", anonymousId: nil, groups: [:]) { _ in
                firstDone = true
                bothDone.signal()
            }
            sut.loadFeatureFlags(distinctId: "second", anonymousId: nil, groups: [:]) { _ in
                secondDone = true
                bothDone.signal()
            }

            await bothDone.wait(timeout: 10)

            #expect(firstDone)
            #expect(secondDone)
            #expect(server.flagsRequests.count == 2)
        }

        @Test("pending request uses correct identity after identify")
        func pendingRequestUsesCorrectIdentity() async {
            let config = PostHogConfig(projectToken: testProjectToken, host: "http://localhost:9001")
            config.preloadFeatureFlags = false
            config.storageManager = PostHogStorageManager(config)
            let sut = getSut(config: config)
            sut.canReloadFlagsForTesting = true

            server.flagsResponseDelay = 1.0

            let bothDone = AsyncLatch(count: 2)

            sut.loadFeatureFlags(distinctId: "anon_uuid", anonymousId: nil, groups: [:]) { _ in
                bothDone.signal()
            }
            sut.loadFeatureFlags(distinctId: "real_user_id", anonymousId: "anon_uuid", groups: [:]) { _ in
                bothDone.signal()
            }

            await bothDone.wait(timeout: 10)

            #expect(server.flagsRequests.count == 2)

            let secondRequest = server.flagsRequests[1]
            let body = server.parseRequest(secondRequest, gzip: false)
            #expect(body?["distinct_id"] as? String == "real_user_id")
            #expect(body?["$anon_distinct_id"] as? String == "anon_uuid")
        }

        @Test("pending request replaces earlier pending with latest")
        func pendingRequestReplacesEarlierPending() async {
            let config = PostHogConfig(projectToken: testProjectToken, host: "http://localhost:9001")
            config.preloadFeatureFlags = false
            config.storageManager = PostHogStorageManager(config)
            let sut = getSut(config: config)
            sut.canReloadFlagsForTesting = true

            server.flagsResponseDelay = 1.0

            var secondCallbackFired = false
            let firstAndThirdDone = AsyncLatch(count: 2)

            sut.loadFeatureFlags(distinctId: "first_id", anonymousId: nil, groups: [:]) { _ in
                firstAndThirdDone.signal()
            }
            sut.loadFeatureFlags(distinctId: "second_id", anonymousId: nil, groups: [:]) { _ in
                secondCallbackFired = true
            }
            sut.loadFeatureFlags(distinctId: "third_id", anonymousId: nil, groups: [:]) { _ in
                firstAndThirdDone.signal()
            }

            await firstAndThirdDone.wait(timeout: 10)

            #expect(server.flagsRequests.count == 2)
            #expect(secondCallbackFired)

            let secondRequest = server.flagsRequests[1]
            let body = server.parseRequest(secondRequest, gzip: false)
            #expect(body?["distinct_id"] as? String == "third_id")
        }

        @Test("callbacks fire for both initial and pending requests")
        func callbacksFireForBothRequests() async {
            let config = PostHogConfig(projectToken: testProjectToken, host: "http://localhost:9001")
            config.preloadFeatureFlags = false
            config.storageManager = PostHogStorageManager(config)
            let sut = getSut(config: config)
            sut.canReloadFlagsForTesting = true

            server.flagsResponseDelay = 1.0

            var firstResult: [String: Any]?
            var secondResult: [String: Any]?
            let bothResults = AsyncLatch(count: 2)

            sut.loadFeatureFlags(distinctId: "user1", anonymousId: nil, groups: [:]) { flags in
                firstResult = flags
                bothResults.signal()
            }
            sut.loadFeatureFlags(distinctId: "user2", anonymousId: nil, groups: [:]) { flags in
                secondResult = flags
                bothResults.signal()
            }

            await bothResults.wait(timeout: 10)

            #expect(firstResult != nil)
            #expect(secondResult != nil)
        }

        @Test("no pending queue when no concurrent load")
        func noPendingQueueWhenNoConcurrentLoad() async {
            let config = PostHogConfig(projectToken: testProjectToken, host: "http://localhost:9001")
            config.preloadFeatureFlags = false
            config.storageManager = PostHogStorageManager(config)
            let sut = getSut(config: config)
            sut.canReloadFlagsForTesting = true

            var result: [String: Any]?

            await withCheckedContinuation { continuation in
                sut.loadFeatureFlags(distinctId: "single_user", anonymousId: nil, groups: [:]) { flags in
                    result = flags
                    continuation.resume()
                }
            }

            #expect(server.flagsRequests.count == 1)
            #expect(result != nil)
        }

        @Test("reloadRemoteConfig concurrent calls do not crash")
        func reloadRemoteConfigConcurrentCallsDoNotCrash() async {
            let config = PostHogConfig(projectToken: testProjectToken, host: "http://localhost:9001")
            config.preloadFeatureFlags = false
            let sut = getSut(config: config)

            await withCheckedContinuation { continuation in
                sut.reloadRemoteConfig { _ in
                    continuation.resume()
                }
                sut.reloadRemoteConfig()
            }

            #expect(sut.getRemoteConfig() != nil)
        }
    }

    #if os(iOS)
        @Suite("Test Session Replay Flags")
        class TestSessionReplayFlags: BaseTestClass {
            @Test("returns isSessionReplayFlagActive true if there is a value")
            func returnsIsSessionReplayFlagActiveTrueIfThereIsAValue() {
                let storage = PostHogStorage(config)
                defer { storage.reset() }

                let recording: [String: Any] = ["test": 1]
                storage.setDictionary(forKey: .remoteConfig, contents: ["sessionRecording": recording])

                let sut = getSut(storage: storage)

                #expect(sut.isSessionReplayFlagActive() == true)
            }

            @Test("returns isSessionReplayFlagActive false if there is no value")
            func returnsIsSessionReplayFlagActiveFalseIfThereIsNoValue() {
                let sut = getSut()

                #expect(sut.isSessionReplayFlagActive() == false)
            }

            @Test("remote config survives reset (project-level config)")
            func sessionReplayConfigSurvivesReset() {
                let storage = PostHogStorage(config)
                defer { storage.reset() }

                storage.setDictionary(forKey: .remoteConfig, contents: ["sessionRecording": ["endpoint": "/s/"]])

                // reset() clears user-scoped state but must keep the project-level remote config, so
                // replay can re-arm after an in-session identity change without an app restart.
                storage.reset()

                #expect(storage.getDictionary(forKey: .remoteConfig) != nil)
            }

            @Test("returns isSessionReplayFlagActive false if recording is disabled remotely")
            func returnIsSessionReplayFlagActiveFalseIfFeatureFlagDisabled() async {
                let storage = PostHogStorage(config)
                defer { storage.reset() }

                let recording: [String: Any] = ["test": 1]
                storage.setDictionary(forKey: .remoteConfig, contents: ["sessionRecording": recording])

                let sut = getSut(storage: storage)

                #expect(sut.isSessionReplayFlagActive())

                // /config (returnReplay == false) now reports recording disabled, which must turn the flag off.
                await reloadRemoteConfig(sut)

                #expect(sut.isSessionReplayFlagActive() == false)
            }

            @Test("returns isSessionReplayFlagActive true if feature flag active")
            func returnIsSessionReplayFlagActiveTrueIfFeatureFlagActive() async {
                let storage = PostHogStorage(config)
                defer { storage.reset() }
                let sut = getSut(storage: storage)

                #expect(sut.isSessionReplayFlagActive() == false)

                server.returnReplay = true

                await reloadConfigThenFlags(sut)

                #expect(config.snapshotEndpoint == "/s/")
                #expect(sut.isSessionReplayFlagActive() == true)
            }

            @Test("returns isSessionReplayFlagActive true if bool linked flag is enabled")
            func returnsIsSessionReplayFlagActiveTrueIfBoolLinkedFlagIsEnabled() async {
                let storage = PostHogStorage(config)
                defer { storage.reset() }

                let sut = getSut(storage: storage)

                #expect(sut.isSessionReplayFlagActive() == false)

                server.returnReplay = true
                server.returnReplayWithVariant = true

                await reloadConfigThenFlags(sut)

                #expect(config.snapshotEndpoint == "/s/")
                #expect(sut.isSessionReplayFlagActive() == true)
            }

            @Test("returns isSessionReplayFlagActive true if bool linked flag is disabled")
            func returnsIsSessionReplayFlagActiveTrueIfBoolLinkedFlagIsDisabled() async {
                let storage = PostHogStorage(config)
                defer { storage.reset() }

                let sut = getSut(storage: storage)

                #expect(sut.isSessionReplayFlagActive() == false)

                server.returnReplay = true
                server.returnReplayWithVariant = true
                server.replayVariantValue = false

                await reloadConfigThenFlags(sut)

                #expect(config.snapshotEndpoint == "/s/")
                #expect(sut.isSessionReplayFlagActive() == false)
            }

            @Test("returns isSessionReplayFlagActive true if multi variant linked flag is a match")
            func returnsIsSessionReplayFlagActiveTrueIfMultiVariantLinkedFlagIsAMatch() async {
                let storage = PostHogStorage(config)
                defer { storage.reset() }

                let sut = getSut(storage: storage)

                #expect(sut.isSessionReplayFlagActive() == false)

                server.returnReplay = true
                server.returnReplayWithVariant = true
                server.returnReplayWithMultiVariant = true
                server.replayVariantName = "recording-platform"
                server.replayVariantValue = ["flag": "recording-platform-check", "variant": "web"]

                await reloadConfigThenFlags(sut)

                #expect(config.snapshotEndpoint == "/s/")
                #expect(sut.isSessionReplayFlagActive() == true)
            }

            @Test("returns isSessionReplayFlagActive false if multi variant linked flag is not a match")
            func returnsIsSessionReplayFlagActiveFalseIfMultiVariantLinkedFlagIsNotAMatch() async {
                let storage = PostHogStorage(config)
                defer { storage.reset() }

                let sut = getSut(storage: storage)

                #expect(sut.isSessionReplayFlagActive() == false)

                server.returnReplay = true
                server.returnReplayWithVariant = true
                server.returnReplayWithMultiVariant = true
                server.replayVariantName = "recording-platform"
                server.replayVariantValue = ["flag": "recording-platform-check", "variant": "mobile"]

                await reloadConfigThenFlags(sut)

                #expect(config.snapshotEndpoint == "/s/")
                #expect(sut.isSessionReplayFlagActive() == false)
            }

            @Test("returns isSessionReplayFlagActive false if bool linked flag is missing")
            func returnsIsSessionReplayFlagActiveFalseIfBoolLinkedFlagIsMissing() async {
                let storage = PostHogStorage(config)

                let sut = getSut(storage: storage)

                #expect(sut.isSessionReplayFlagActive() == false)

                server.returnReplay = true
                server.returnReplayWithVariant = true
                server.replayVariantName = "some-missing-flag"
                server.flagsSkipReplayVariantName = true

                await reloadConfigThenFlags(sut)

                #expect(config.snapshotEndpoint == "/s/")
                #expect(sut.isSessionReplayFlagActive() == false)

                storage.reset()
            }

            @Test("calls featureFlagCalledCallback when bool linked flag is checked")
            func callsFeatureFlagCalledCallbackWhenBoolLinkedFlagIsChecked() async {
                let storage = PostHogStorage(config)
                defer { storage.reset() }

                var calledFlagKey: String?
                var calledFlagValue: Any?

                let sut = getSut(storage: storage) { flagKey, flagValue in
                    calledFlagKey = flagKey
                    calledFlagValue = flagValue
                }

                #expect(sut.isSessionReplayFlagActive() == false)

                server.returnReplay = true
                server.returnReplayWithVariant = true

                await reloadConfigThenFlags(sut)

                #expect(sut.isSessionReplayFlagActive() == true)
                #expect(calledFlagKey != nil)
                #expect(calledFlagValue != nil)
            }

            @Test("calls featureFlagCalledCallback when multi variant linked flag is checked")
            func callsFeatureFlagCalledCallbackWhenMultiVariantLinkedFlagIsChecked() async {
                let storage = PostHogStorage(config)
                defer { storage.reset() }

                var calledFlagKey: String?
                var calledFlagValue: Any?

                let sut = getSut(storage: storage) { flagKey, flagValue in
                    calledFlagKey = flagKey
                    calledFlagValue = flagValue
                }

                #expect(sut.isSessionReplayFlagActive() == false)

                server.returnReplay = true
                server.returnReplayWithVariant = true
                server.returnReplayWithMultiVariant = true
                server.replayVariantName = "recording-platform"
                server.replayVariantValue = ["flag": "recording-platform-check", "variant": "web"]

                await reloadConfigThenFlags(sut)

                #expect(sut.isSessionReplayFlagActive() == true)
                #expect(calledFlagKey == "recording-platform-check")
                #expect(calledFlagValue as? String == "web")
            }

            @Test("does not call featureFlagCalledCallback when sendFeatureFlagEvent is disabled")
            func doesNotCallFeatureFlagCalledCallbackWhenSendFeatureFlagEventDisabled() async {
                let config = PostHogConfig(projectToken: testProjectToken, host: "http://localhost:9001")
                config.sendFeatureFlagEvent = false
                let storage = PostHogStorage(config)
                defer { storage.reset() }

                var callbackInvoked = false

                let sut = getSut(storage: storage, config: config) { _, _ in
                    callbackInvoked = true
                }

                server.returnReplay = true
                server.returnReplayWithVariant = true

                await reloadConfigThenFlags(sut)

                #expect(sut.isSessionReplayFlagActive() == true)
                #expect(callbackInvoked == false)
            }

            @Test("does not call featureFlagCalledCallback when no linked flag")
            func doesNotCallFeatureFlagCalledCallbackWhenNoLinkedFlag() async {
                let storage = PostHogStorage(config)
                defer { storage.reset() }

                var callbackInvoked = false

                let sut = getSut(storage: storage) { _, _ in
                    callbackInvoked = true
                }

                server.returnReplay = true

                await reloadConfigThenFlags(sut)

                #expect(sut.isSessionReplayFlagActive() == true)
                #expect(callbackInvoked == false)
            }

            @Test("session replay re-arms from cached config after reset")
            func sessionReplayReArmsFromCachedConfigAfterReset() async {
                let storage = PostHogStorage(config)
                defer { storage.reset() }

                server.returnReplay = true
                server.sessionRecordingSampleRate = "0.42"

                let sut = getSut(storage: storage)

                // /config (the only source of recording config) populates the in-memory recording
                // state and persists the whole config to storage under .remoteConfig.
                await reloadRemoteConfig(sut)
                #expect(sut.isSessionReplayFlagActive() == true)
                #expect(sut.getRecordingSampleRate() == 0.42)

                // Mimic reset(): storage.reset() KEEPS the persisted .remoteConfig (project-level, not
                // user data) while clearing user state; clear() resets the in-memory replay flags but
                // keeps the cached remote config, so the following /flags reload can re-evaluate replay.
                storage.reset()
                sut.clear()
                #expect(sut.isSessionReplayFlagActive() == false)
                #expect(sut.getRecordingSampleRate() == nil)

                // The post-reset /flags reload carries no sessionRecording, so replay must re-arm from
                // the retained .remoteConfig (the else branch), without waiting for an app restart.
                await loadFeatureFlags(sut)

                #expect(sut.isSessionReplayFlagActive() == true)
                #expect(sut.getRecordingSampleRate() == 0.42)
            }

            @Test("replay stays off after reset when the new user does not match the linked flag")
            func sessionReplayStaysOffAfterResetWhenLinkedFlagMissing() async {
                let storage = PostHogStorage(config)
                defer { storage.reset() }

                // Recording is gated on a linked flag the post-reset user won't have:
                // /config advertises linkedFlag, /flags omits it.
                server.returnReplay = true
                server.returnReplayWithVariant = true
                server.replayVariantName = "some-missing-flag"
                server.flagsSkipReplayVariantName = true

                let sut = getSut(storage: storage)

                // /config caches the recording config (with linkedFlag) under .remoteConfig.
                await reloadRemoteConfig(sut)
                #expect(storage.getDictionary(forKey: .remoteConfig) != nil)

                storage.reset()
                sut.clear()

                // The post-reset /flags reload hits the else branch and re-evaluates the cached
                // config against the new user's flags. The linked flag is missing, so replay must
                // stay off rather than blindly re-arming.
                await loadFeatureFlags(sut)

                #expect(sut.isSessionReplayFlagActive() == false)
            }

            @Test("session replay re-arms from cached config on a quota-limited flags reload")
            func sessionReplayReArmsOnQuotaLimitedFlagsReload() async {
                let storage = PostHogStorage(config)
                defer { storage.reset() }

                server.returnReplay = true
                server.sessionRecordingSampleRate = "0.42"

                let sut = getSut(storage: storage)

                await reloadRemoteConfig(sut)
                #expect(sut.isSessionReplayFlagActive() == true)
                #expect(sut.getRecordingSampleRate() == 0.42)

                storage.reset()
                sut.clear()
                #expect(sut.isSessionReplayFlagActive() == false)
                #expect(sut.getRecordingSampleRate() == nil)

                server.quotaLimitFeatureFlags = true
                await loadFeatureFlags(sut)

                #expect(sut.isSessionReplayFlagActive() == true)
                #expect(sut.getRecordingSampleRate() == 0.42)
            }

            @Test("flags reload with no cached recording config leaves replay inactive")
            func flagsReloadWithoutCachedRecordingConfigLeavesReplayInactive() async {
                let storage = PostHogStorage(config)
                defer { storage.reset() }

                let sut = getSut(storage: storage)
                #expect(sut.isSessionReplayFlagActive() == false)

                await loadFeatureFlags(sut)

                #expect(sut.isSessionReplayFlagActive() == false)
            }
        }
    #endif

    // MARK: Error Tracking Config

    // Note: We don't yet support the errorTrackingAutocaptureTriggers and suppressionRules features.

    @Suite("Test Error Tracking Config")
    class TestErrorTrackingConfig: BaseTestClass {
        private func makeIsolatedConfig(disableRemoteConfigForTesting: Bool = true) -> PostHogConfig {
            let config = PostHogConfig(projectToken: "\(testProjectToken)-\(UUID().uuidString)", host: "http://localhost:9001")
            config.disableRemoteConfigForTesting = disableRemoteConfigForTesting
            return config
        }

        @Test("returns isAutocaptureExceptionsEnabled false by default")
        func returnsAutocaptureExceptionsDisabledByDefault() {
            let config = makeIsolatedConfig()
            let storage = PostHogStorage(config)
            defer { storage.reset() }

            let sut = getSut(storage: storage, config: config)

            #expect(sut.isAutocaptureExceptionsEnabled() == false)
        }

        @Test("returns isAutocaptureExceptionsEnabled true from cached config")
        func returnsAutocaptureExceptionsEnabledFromCache() {
            let config = makeIsolatedConfig()
            let storage = PostHogStorage(config)
            defer { storage.reset() }

            storage.setDictionary(forKey: .remoteConfig, contents: ["errorTracking": ["autocaptureExceptions": true]])

            let sut = getSut(storage: storage, config: config)

            #expect(sut.isAutocaptureExceptionsEnabled() == true)
        }

        @Test("returns isAutocaptureExceptionsEnabled false from cached config when disabled")
        func returnsAutocaptureExceptionsDisabledFromCache() {
            let config = makeIsolatedConfig()
            let storage = PostHogStorage(config)
            defer { storage.reset() }

            storage.setDictionary(forKey: .remoteConfig, contents: ["errorTracking": ["autocaptureExceptions": false]])

            let sut = getSut(storage: storage, config: config)

            #expect(sut.isAutocaptureExceptionsEnabled() == false)
        }

        @Test("enables autocapture exceptions from remote config dict")
        func enablesAutocaptureExceptionsFromRemoteConfigDict() async {
            let config = makeIsolatedConfig(disableRemoteConfigForTesting: false)
            config.preloadFeatureFlags = false
            config.storageManager = PostHogStorageManager(config)

            server.remoteConfigErrorTracking = ["autocaptureExceptions": true]

            let storage = PostHogStorage(config)
            defer { storage.reset() }

            let sut = getSut(storage: storage, config: config)

            let remoteConfigLoaded = AsyncLatch()
            let token = sut.onRemoteConfigLoaded.subscribe { _ in
                remoteConfigLoaded.signal()
            }

            await remoteConfigLoaded.wait()

            #expect(sut.isAutocaptureExceptionsEnabled() == true)
            #expect(storage.getDictionary(forKey: .remoteConfig) != nil)

            _ = token
        }

        @Test("error tracking re-arms from cached config after reset")
        func errorTrackingReArmsFromCachedConfigAfterReset() async {
            let config = makeIsolatedConfig()
            server.remoteConfigErrorTracking = ["autocaptureExceptions": true]

            let storage = PostHogStorage(config)
            defer { storage.reset() }

            let sut = getSut(storage: storage, config: config)

            // /config (the only source of error-tracking config) enables autocapture and persists
            // it under .errorTracking.
            await reloadRemoteConfig(sut)
            #expect(sut.isAutocaptureExceptionsEnabled() == true)

            // Mimic reset(): storage.reset() wipes the cached remote config but KEEPS the persisted
            // .errorTracking slice (project-level, not user data); clear() zeroes the in-memory flag.
            storage.reset()
            sut.clear()
            #expect(sut.isAutocaptureExceptionsEnabled() == false)

            // The post-reset /flags reload carries no errorTracking and the cached remote config is
            // gone, so autocapture must re-arm from the persisted .errorTracking slice.
            await loadFeatureFlags(sut)
            #expect(sut.isAutocaptureExceptionsEnabled() == true)
        }

        @Test("disables autocapture exceptions from remote config dict")
        func disablesAutocaptureExceptionsFromRemoteConfigDict() async {
            let config = makeIsolatedConfig(disableRemoteConfigForTesting: false)
            config.preloadFeatureFlags = false
            config.storageManager = PostHogStorageManager(config)

            server.remoteConfigErrorTracking = ["autocaptureExceptions": false]

            let storage = PostHogStorage(config)
            defer { storage.reset() }

            let sut = getSut(storage: storage, config: config)

            let remoteConfigLoaded = AsyncLatch()
            let token = sut.onRemoteConfigLoaded.subscribe { _ in
                remoteConfigLoaded.signal()
            }

            await remoteConfigLoaded.wait()

            #expect(sut.isAutocaptureExceptionsEnabled() == false)

            _ = token
        }

        @Test("disables autocapture exceptions when errorTracking is boolean false")
        func disablesAutocaptureExceptionsWhenErrorTrackingIsBooleanFalse() async {
            let config = makeIsolatedConfig(disableRemoteConfigForTesting: false)
            config.preloadFeatureFlags = false
            config.storageManager = PostHogStorageManager(config)

            server.remoteConfigErrorTracking = false

            let storage = PostHogStorage(config)
            defer { storage.reset() }

            // Pre-cache an enabled config to verify it gets disabled
            storage.setDictionary(forKey: .remoteConfig, contents: ["errorTracking": ["autocaptureExceptions": true]])

            let sut = getSut(storage: storage, config: config)

            // Should initially be true from cache
            #expect(sut.isAutocaptureExceptionsEnabled() == true)

            let remoteConfigLoaded = AsyncLatch()
            let token = sut.onRemoteConfigLoaded.subscribe { _ in
                remoteConfigLoaded.signal()
            }

            await remoteConfigLoaded.wait()

            #expect(sut.isAutocaptureExceptionsEnabled() == false)

            _ = token
        }

        @Test("disables autocapture exceptions when errorTracking key is missing")
        func disablesAutocaptureExceptionsWhenErrorTrackingKeyIsMissing() async {
            let config = makeIsolatedConfig(disableRemoteConfigForTesting: false)
            config.preloadFeatureFlags = false
            config.storageManager = PostHogStorageManager(config)

            server.remoteConfigErrorTracking = nil

            let storage = PostHogStorage(config)
            defer { storage.reset() }

            let sut = getSut(storage: storage, config: config)

            let remoteConfigLoaded = AsyncLatch()
            let token = sut.onRemoteConfigLoaded.subscribe { _ in
                remoteConfigLoaded.signal()
            }

            await remoteConfigLoaded.wait()

            #expect(sut.isAutocaptureExceptionsEnabled() == false)

            _ = token
        }

        @Test("error tracking re-arms from cached config on a quota-limited flags reload")
        func errorTrackingReArmsOnQuotaLimitedFlagsReload() async {
            let config = makeIsolatedConfig()
            server.remoteConfigErrorTracking = ["autocaptureExceptions": true]

            let storage = PostHogStorage(config)
            defer { storage.reset() }

            let sut = getSut(storage: storage, config: config)

            await reloadRemoteConfig(sut)
            #expect(sut.isAutocaptureExceptionsEnabled() == true)

            storage.reset()
            sut.clear()
            #expect(sut.isAutocaptureExceptionsEnabled() == false)

            server.quotaLimitFeatureFlags = true
            await loadFeatureFlags(sut)

            #expect(sut.isAutocaptureExceptionsEnabled() == true)
        }

        @Test("flags reload with no cached error tracking does not re-arm it")
        func flagsReloadWithoutCachedErrorTrackingDoesNotReArm() async {
            let config = makeIsolatedConfig()

            let storage = PostHogStorage(config)
            defer { storage.reset() }

            let sut = getSut(storage: storage, config: config)
            #expect(sut.isAutocaptureExceptionsEnabled() == false)

            await loadFeatureFlags(sut)

            #expect(sut.isAutocaptureExceptionsEnabled() == false)
        }
    }

    @Suite("Test Capture Performance Config")
    class TestCapturePerformanceConfig: BaseTestClass {
        private func makeIsolatedConfig(disableRemoteConfigForTesting: Bool = true) -> PostHogConfig {
            let config = PostHogConfig(projectToken: "\(testProjectToken)-\(UUID().uuidString)", host: "http://localhost:9001")
            config.disableRemoteConfigForTesting = disableRemoteConfigForTesting
            return config
        }

        @Test("capture performance stays in the cached remote config across reset")
        func capturePerformanceSurvivesReset() async {
            let config = makeIsolatedConfig()
            let storage = PostHogStorage(config)
            defer { storage.reset() }

            let sut = getSut(storage: storage, config: config)

            await reloadRemoteConfig(sut)
            #expect(sut.getRemoteConfig()?["capturePerformance"] != nil)

            storage.reset()
            sut.clear()

            #expect(storage.getDictionary(forKey: .remoteConfig) != nil)
            #expect(sut.getRemoteConfig()?["capturePerformance"] != nil)
        }
    }
}
