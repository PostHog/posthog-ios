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
            return PostHogRemoteConfig(theConfig, theStorage, api)
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

        @Test("reloadRemoteConfig fetches feature flags if missing")
        func onRemoteConfigLoadsFeatureFlagsIfNotPreviouslyLoaded() async {
            let config = PostHogConfig(apiKey: testAPIKey, host: "http://localhost:9001")
            config.remoteConfig = true
            config.preloadFeatureFlags = true
            config.storageManager = PostHogStorageManager(config)
            let sut = getSut(config: config)

            var featureFlagsLoaded = false
            var remoteConfigLoaded = false
            sut.onFeatureFlagsLoaded = { _ in
                featureFlagsLoaded = true
            }
            sut.onRemoteConfigLoaded = { _ in
                remoteConfigLoaded = true
            }

            await withCheckedContinuation { continuation in
                while !remoteConfigLoaded || !featureFlagsLoaded {}
                continuation.resume()
            }

            #expect(sut.getRemoteConfig() != nil)
            #expect(sut.getFeatureFlags() != nil)
        }

        @Test("reloadRemoteConfig does not fetch feature flags if preloadFeatureFlags is disabled")
        func reloadRemoteConfigDoesNotFetchFeatureFlagsIfPreloadFeatureFlagsIsDisabled() async throws {
            let config = PostHogConfig(apiKey: testAPIKey, host: "http://localhost:9001")
            config.remoteConfig = true
            config.preloadFeatureFlags = false
            config.storageManager = PostHogStorageManager(config)
            let sut = getSut(config: config)

            var featureFlagsLoaded = false
            var remoteConfigLoaded = false

            sut.onFeatureFlagsLoaded = { _ in
                featureFlagsLoaded = true
            }
            sut.onRemoteConfigLoaded = { _ in
                remoteConfigLoaded = true
            }

            await withCheckedContinuation { continuation in
                while !remoteConfigLoaded {}
                continuation.resume()
            }

            #expect(featureFlagsLoaded == false)
            #expect(sut.getRemoteConfig() != nil)
            #expect(sut.getFeatureFlags() == nil)
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
