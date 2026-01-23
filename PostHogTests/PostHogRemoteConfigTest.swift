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
        let config = PostHogConfig(apiKey: testAPIKey, host: "http://localhost:9001")
        var server: MockPostHogServer!

        init() {
            server = MockPostHogServer()
            server.start()
            // important!
            let storage = PostHogStorage(config)
            storage.reset()
        }

        deinit {
            server.stop()
            server = nil
        }

        func getSut(
            storage: PostHogStorage? = nil,
            config: PostHogConfig? = nil
        ) -> PostHogRemoteConfig {
            let theConfig = config ?? self.config
            let theStorage = storage ?? PostHogStorage(theConfig)
            let api = PostHogApi(theConfig)
            return PostHogRemoteConfig(theConfig, theStorage, api) { [:] }
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

        @Test("remote config fetches feature flags if missing")
        func remoteConfigLoadsFeatureFlagsIfNotPreviouslyLoaded() async {
            let config = PostHogConfig(apiKey: testAPIKey, host: "http://localhost:9001")
            config.remoteConfig = true
            config.preloadFeatureFlags = true
            config.storageManager = PostHogStorageManager(config)
            let sut = getSut(config: config)

            var featureFlagsLoaded = false
            var remoteConfigLoaded = false
            let token1 = sut.onFeatureFlagsLoaded.subscribe { _ in
                featureFlagsLoaded = true
            }
            let token2 = sut.onRemoteConfigLoaded.subscribe { _ in
                remoteConfigLoaded = true
            }

            await withCheckedContinuation { continuation in
                let timeout = Date().addingTimeInterval(2) // 2 second timeout
                while !remoteConfigLoaded || !featureFlagsLoaded, Date() < timeout {}
                continuation.resume()
            }

            #expect(sut.getRemoteConfig() != nil)
            #expect(sut.getFeatureFlags() != nil)
            
            _ = (token1, token2) // silence read warnings
        }

        @Test("remote config does not fetch feature flags if preloadFeatureFlags is disabled")
        func remoteConfigDoesNotFetchFeatureFlagsIfPreloadFeatureFlagsIsDisabled() async throws {
            let config = PostHogConfig(apiKey: testAPIKey, host: "http://localhost:9001")
            config.remoteConfig = true
            config.preloadFeatureFlags = false
            config.storageManager = PostHogStorageManager(config)
            let sut = getSut(config: config)

            var featureFlagsLoaded = false
            var remoteConfigLoaded = false

            let token1 = sut.onFeatureFlagsLoaded.subscribe { _ in
                featureFlagsLoaded = true
            }
            let token2 = sut.onRemoteConfigLoaded.subscribe { _ in
                remoteConfigLoaded = true
            }

            await withCheckedContinuation { continuation in
                let timeout = Date().addingTimeInterval(2) // 2 second timeout
                while !remoteConfigLoaded, Date() < timeout {}
                continuation.resume()
            }

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

            let config = PostHogConfig(apiKey: testAPIKey, host: "http://localhost:9001")
            config.remoteConfig = true
            config.preloadFeatureFlags = true
            config.storageManager = PostHogStorageManager(config)

            let sut = getSut(storage: storage, config: config)

            var featureFlagsLoaded = false
            let token = sut.onFeatureFlagsLoaded.subscribe { _ in
                featureFlagsLoaded = true
            }

            #expect(sut.getFeatureFlag("some-flag") as? Bool == true)

            // wait for flags to be loaded
            await withCheckedContinuation { continuation in
                let timeout = Date().addingTimeInterval(2) // 2 second timeout
                while !featureFlagsLoaded, Date() < timeout {}
                continuation.resume()
            }

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

            let config = PostHogConfig(apiKey: testAPIKey, host: "http://localhost:9001")
            config.remoteConfig = true
            config.preloadFeatureFlags = false
            config.storageManager = PostHogStorageManager(config)

            let storage = PostHogStorage(config)
            defer { storage.reset() }

            // set cached flag
            storage.setDictionary(forKey: .flags, contents: ["some-flag": true])
            storage.setDictionary(forKey: .enabledFeatureFlags, contents: ["some-flag": true])
            storage.setDictionary(forKey: .enabledFeatureFlagPayloads, contents: ["some-flag": true])

            let sut = getSut(storage: storage, config: config)

            var remoteConfigLoaded = false
            let token = sut.onRemoteConfigLoaded.subscribe { _ in
                remoteConfigLoaded = true
            }

            // wait for flags to be loaded
            await withCheckedContinuation { continuation in
                let timeout = Date().addingTimeInterval(2) // 2 second timeout
                while !remoteConfigLoaded, Date() < timeout {}
                // need a small delay because of the timing of the check above
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    continuation.resume()
                }
            }

            // test for empty cache
            #expect(storage.getDictionary(forKey: .flags).isNilOrEmpty == true)
            #expect(storage.getDictionary(forKey: .enabledFeatureFlags).isNilOrEmpty == true)
            #expect(storage.getDictionary(forKey: .enabledFeatureFlagPayloads).isNilOrEmpty == true)
            
            _ = token // silence read warnings
        }

        @Test("should not clear flags if remote config call fails")
        func shouldNotClearFlagsIfRemoteConfigCallFails() async {
            let config = PostHogConfig(apiKey: testAPIKey, host: "http://localhost:9001")
            config.preloadFeatureFlags = true
            config.remoteConfig = true

            let storage = PostHogStorage(config)
            defer { storage.reset() }

            storage.setDictionary(forKey: .enabledFeatureFlags, contents: ["foo": true])

            // simulate a net call failure
            server.return500 = true

            let sut = getSut(storage: storage, config: config)

            var featureFlagsLoaded = false
            let token = sut.onFeatureFlagsLoaded.subscribe { _ in
                featureFlagsLoaded = true
            }

            // wait for flags to be loaded
            await withCheckedContinuation { continuation in
                let timeout = Date().addingTimeInterval(2) // 2 second timeout
                while !featureFlagsLoaded, Date() < timeout {}
                // need a small delay because of the timing of the check above
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    continuation.resume()
                }
            }

            // check that cached flag was not removed
            #expect(sut.getFeatureFlag("foo") as? Bool == true)
            
            _ = token // silence read warnings
        }

        @Test("should not clear flags if hasFeatureFlags key is missing")
        func shouldNotClearFlagsIfHasFeatureFlagsKeyIsMissing() async {
            let config = PostHogConfig(apiKey: testAPIKey, host: "http://localhost:9001")
            config.preloadFeatureFlags = true
            config.remoteConfig = true

            let storage = PostHogStorage(config)
            defer { storage.reset() }

            storage.setDictionary(forKey: .enabledFeatureFlags, contents: ["foo": true])

            // removes `hasFeatureFlags` from response
            server.hasFeatureFlags = nil

            let sut = getSut(storage: storage, config: config)

            var featureFlagsLoaded = false
            let token = sut.onFeatureFlagsLoaded.subscribe { _ in
                featureFlagsLoaded = true
            }

            // wait for flags to be loaded
            await withCheckedContinuation { continuation in
                let timeout = Date().addingTimeInterval(2) // 2 second timeout
                while !featureFlagsLoaded, Date() < timeout {}
                // need a small delay because of the timing of the check above
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    continuation.resume()
                }
            }

            // check that cached flag was not removed
            #expect(sut.getFeatureFlag("foo") as? Bool == true)
            
            _ = token // silence read warnings
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
                storage.setDictionary(forKey: .sessionReplay, contents: recording)

                let sut = getSut(storage: storage)

                #expect(sut.isSessionReplayFlagActive() == true)
            }

            @Test("returns isSessionReplayFlagActive false if there is no value")
            func returnsIsSessionReplayFlagActiveFalseIfThereIsNoValue() {
                let sut = getSut()

                #expect(sut.isSessionReplayFlagActive() == false)
            }

            @Test("returns isSessionReplayFlagActive false if feature flag disabled")
            func returnIsSessionReplayFlagActiveFalseIfFeatureFlagDisabled() async {
                let storage = PostHogStorage(config)
                defer { storage.reset() }

                let recording: [String: Any] = ["test": 1]
                storage.setDictionary(forKey: .sessionReplay, contents: recording)

                let sut = getSut(storage: storage)

                #expect(sut.isSessionReplayFlagActive())

                await withCheckedContinuation { continuation in
                    sut.loadFeatureFlags(distinctId: "distinctId", anonymousId: "anonymousId", groups: ["group": "value"], callback: { _ in
                        continuation.resume()
                    })
                }

                #expect(storage.getDictionary(forKey: .sessionReplay) == nil)
                #expect(sut.isSessionReplayFlagActive() == false)
            }

            @Test("returns isSessionReplayFlagActive true if feature flag active")
            func returnIsSessionReplayFlagActiveTrueIfFeatureFlagActive() async {
                let storage = PostHogStorage(config)
                defer { storage.reset() }
                let sut = getSut(storage: storage)

                #expect(sut.isSessionReplayFlagActive() == false)

                server.returnReplay = true

                await withCheckedContinuation { continuation in
                    sut.loadFeatureFlags(distinctId: "distinctId", anonymousId: "anonymousId", groups: ["group": "value"], callback: { _ in
                        continuation.resume()
                    })
                }

                #expect(storage.getDictionary(forKey: .sessionReplay) != nil)
                #expect(config.snapshotEndpoint == "/newS/")
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

                await withCheckedContinuation { continuation in
                    sut.loadFeatureFlags(distinctId: "distinctId", anonymousId: "anonymousId", groups: ["group": "value"], callback: { _ in
                        continuation.resume()
                    })
                }

                #expect(storage.getDictionary(forKey: .sessionReplay) != nil)
                #expect(config.snapshotEndpoint == "/newS/")
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

                await withCheckedContinuation { continuation in
                    sut.loadFeatureFlags(distinctId: "distinctId", anonymousId: "anonymousId", groups: ["group": "value"], callback: { _ in
                        continuation.resume()
                    })
                }

                #expect(storage.getDictionary(forKey: .sessionReplay) != nil)
                #expect(config.snapshotEndpoint == "/newS/")
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

                await withCheckedContinuation { continuation in
                    sut.loadFeatureFlags(distinctId: "distinctId", anonymousId: "anonymousId", groups: ["group": "value"], callback: { _ in
                        continuation.resume()
                    })
                }

                #expect(storage.getDictionary(forKey: .sessionReplay) != nil)
                #expect(config.snapshotEndpoint == "/newS/")
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

                await withCheckedContinuation { continuation in
                    sut.loadFeatureFlags(distinctId: "distinctId", anonymousId: "anonymousId", groups: ["group": "value"], callback: { _ in
                        continuation.resume()
                    })
                }

                #expect(storage.getDictionary(forKey: .sessionReplay) != nil)
                #expect(config.snapshotEndpoint == "/newS/")
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

                await withCheckedContinuation { continuation in
                    sut.loadFeatureFlags(distinctId: "distinctId", anonymousId: "anonymousId", groups: ["group": "value"], callback: { _ in
                        continuation.resume()
                    })
                }

                #expect(storage.getDictionary(forKey: .sessionReplay) != nil)
                #expect(config.snapshotEndpoint == "/newS/")
                #expect(sut.isSessionReplayFlagActive() == false)

                storage.reset()
            }
        }
    #endif
}
