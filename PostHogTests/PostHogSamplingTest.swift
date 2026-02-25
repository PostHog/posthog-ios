import Foundation
@testable import PostHog
import Testing

@Suite("Session Replay Sampling Tests")
class PostHogSamplingTests {
    // MARK: - simpleHash Tests

    @Test("simpleHash produces consistent values for the same input")
    func simpleHashConsistent() {
        let hash1 = simpleHash("test-session-id")
        let hash2 = simpleHash("test-session-id")
        #expect(hash1 == hash2)
    }

    @Test("simpleHash produces positive values")
    func simpleHashPositive() {
        let inputs = [
            "session-1",
            "session-2",
            "abc123",
            "00000000-0000-0000-0000-000000000000",
            UUID().uuidString,
        ]
        for input in inputs {
            #expect(simpleHash(input) >= 0, "Hash for '\(input)' should be non-negative")
        }
    }

    @Test("simpleHash produces distinct values for different inputs")
    func simpleHashDistinct() {
        let hash1 = simpleHash("session-1")
        let hash2 = simpleHash("session-2")
        #expect(hash1 != hash2)
    }

    @Test("simpleHash handles empty string")
    func simpleHashEmpty() {
        let hash = simpleHash("")
        #expect(hash == 0)
    }

    // MARK: - sampleOnProperty Tests

    @Test("sampleOnProperty returns true at rate 1.0")
    func sampleOnPropertyFullRate() {
        // At rate 1.0, all sessions should be sampled in
        for i in 0 ..< 100 {
            #expect(sampleOnProperty("session-\(i)", 1.0) == true)
        }
    }

    @Test("sampleOnProperty returns false at rate 0.0")
    func sampleOnPropertyZeroRate() {
        // At rate 0.0, no sessions should be sampled in
        for i in 0 ..< 100 {
            #expect(sampleOnProperty("session-\(i)", 0.0) == false)
        }
    }

    @Test("sampleOnProperty is deterministic")
    func sampleOnPropertyDeterministic() {
        let sessionId = "test-session-id-12345"
        let rate = 0.5
        let result1 = sampleOnProperty(sessionId, rate)
        let result2 = sampleOnProperty(sessionId, rate)
        #expect(result1 == result2)
    }

    @Test("sampleOnProperty clamps rate above 1.0")
    func sampleOnPropertyClampsAboveOne() {
        // Rate > 1.0 should be clamped to 1.0 (record all)
        for i in 0 ..< 100 {
            #expect(sampleOnProperty("session-\(i)", 1.5) == true)
        }
    }

    @Test("sampleOnProperty clamps rate below 0.0")
    func sampleOnPropertyClampsBelowZero() {
        // Rate < 0.0 should be clamped to 0.0 (record none)
        for i in 0 ..< 100 {
            #expect(sampleOnProperty("session-\(i)", -0.5) == false)
        }
    }

    @Test("sampleOnProperty samples approximately correct percentage")
    func sampleOnPropertyApproximateRate() {
        // With enough samples, ~50% should be sampled in at rate 0.5
        var sampledIn = 0
        let total = 1000
        for i in 0 ..< total {
            if sampleOnProperty("session-\(i)", 0.5) {
                sampledIn += 1
            }
        }
        // Allow generous tolerance since hash distribution may not be perfectly uniform
        let ratio = Double(sampledIn) / Double(total)
        #expect(ratio > 0.3, "Expected roughly 50% sampled in, got \(ratio * 100)%")
        #expect(ratio < 0.7, "Expected roughly 50% sampled in, got \(ratio * 100)%")
    }
}

#if os(iOS)

    // MARK: - parseSampleRate Tests

    @Suite("parseSampleRate Tests", .serialized)
    class ParseSampleRateTests {
        let config = PostHogConfig(apiKey: testAPIKey, host: "http://localhost:9001")
        var server: MockPostHogServer!

        init() {
            server = MockPostHogServer()
            server.start()
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

        @Test("getRecordingSampleRate returns nil when no sample rate is configured")
        func noSampleRateConfigured() {
            let sut = getSut()
            #expect(sut.getRecordingSampleRate() == nil)
        }

        @Test("preloads sample rate from cache as string")
        func preloadsSampleRateFromCacheAsString() {
            let storage = PostHogStorage(config)
            defer { storage.reset() }

            storage.setDictionary(forKey: .sessionReplay, contents: ["sampleRate": "0.75"])

            let sut = getSut(storage: storage)

            #expect(sut.getRecordingSampleRate() == 0.75)
        }

        @Test("preloads sample rate from cache as number")
        func preloadsSampleRateFromCacheAsNumber() {
            let storage = PostHogStorage(config)
            defer { storage.reset() }

            storage.setDictionary(forKey: .sessionReplay, contents: ["sampleRate": 0.5])

            let sut = getSut(storage: storage)

            #expect(sut.getRecordingSampleRate() == 0.5)
        }

        @Test("preloads sample rate 1.0 from cache")
        func preloadsSampleRateOneFromCache() {
            let storage = PostHogStorage(config)
            defer { storage.reset() }

            storage.setDictionary(forKey: .sessionReplay, contents: ["sampleRate": "1"])

            let sut = getSut(storage: storage)

            #expect(sut.getRecordingSampleRate() == 1.0)
        }

        @Test("preloads sample rate 0.0 from cache")
        func preloadsSampleRateZeroFromCache() {
            let storage = PostHogStorage(config)
            defer { storage.reset() }

            storage.setDictionary(forKey: .sessionReplay, contents: ["sampleRate": "0"])

            let sut = getSut(storage: storage)

            #expect(sut.getRecordingSampleRate() == 0.0)
        }

        @Test("ignores invalid sample rate above 1.0 from cache")
        func ignoresInvalidSampleRateAboveOneFromCache() {
            let storage = PostHogStorage(config)
            defer { storage.reset() }

            storage.setDictionary(forKey: .sessionReplay, contents: ["sampleRate": "1.5"])

            let sut = getSut(storage: storage)

            #expect(sut.getRecordingSampleRate() == nil)
        }

        @Test("ignores negative sample rate from cache")
        func ignoresNegativeSampleRateFromCache() {
            let storage = PostHogStorage(config)
            defer { storage.reset() }

            storage.setDictionary(forKey: .sessionReplay, contents: ["sampleRate": "-0.5"])

            let sut = getSut(storage: storage)

            #expect(sut.getRecordingSampleRate() == nil)
        }

        @Test("ignores non-numeric sample rate from cache")
        func ignoresNonNumericSampleRateFromCache() {
            let storage = PostHogStorage(config)
            defer { storage.reset() }

            storage.setDictionary(forKey: .sessionReplay, contents: ["sampleRate": "invalid"])

            let sut = getSut(storage: storage)

            #expect(sut.getRecordingSampleRate() == nil)
        }

        @Test("parses sample rate from remote config response")
        func parsesSampleRateFromRemoteConfig() async {
            let config = PostHogConfig(apiKey: testAPIKey, host: "http://localhost:9001")
            config.remoteConfig = true
            config.preloadFeatureFlags = false
            config.storageManager = PostHogStorageManager(config)

            server.returnReplay = true
            server.sessionRecordingSampleRate = "0.5"

            let sut = getSut(config: config)

            var remoteConfigLoaded = false
            let token = sut.onRemoteConfigLoaded.subscribe { _ in
                remoteConfigLoaded = true
            }

            await withCheckedContinuation { continuation in
                let timeout = Date().addingTimeInterval(2)
                while !remoteConfigLoaded, Date() < timeout {}
                continuation.resume()
            }

            #expect(sut.getRecordingSampleRate() == 0.5)
            _ = token
        }

        @Test("remote config without sample rate leaves it nil")
        func remoteConfigWithoutSampleRate() async {
            let config = PostHogConfig(apiKey: testAPIKey, host: "http://localhost:9001")
            config.remoteConfig = true
            config.preloadFeatureFlags = false
            config.storageManager = PostHogStorageManager(config)

            server.returnReplay = true
            // no sessionRecordingSampleRate set

            let sut = getSut(config: config)

            var remoteConfigLoaded = false
            let token = sut.onRemoteConfigLoaded.subscribe { _ in
                remoteConfigLoaded = true
            }

            await withCheckedContinuation { continuation in
                let timeout = Date().addingTimeInterval(2)
                while !remoteConfigLoaded, Date() < timeout {}
                continuation.resume()
            }

            #expect(sut.getRecordingSampleRate() == nil)
            _ = token
        }
    }

    // MARK: - PostHogSessionReplayConfig sampleRate Tests

    @Suite("PostHogSessionReplayConfig sampleRate Tests")
    class SessionReplayConfigSampleRateTests {
        @Test("sampleRate defaults to nil")
        func sampleRateDefaultsToNil() {
            let config = PostHogSessionReplayConfig()
            #expect(config.sampleRate == nil)
        }

        @Test("sampleRate accepts valid value")
        func sampleRateAcceptsValidValue() {
            let config = PostHogSessionReplayConfig()
            config.sampleRate = NSNumber(value: 0.5)
            #expect(config.sampleRate?.doubleValue == 0.5)
        }

        @Test("sampleRate accepts 0.0")
        func sampleRateAcceptsZero() {
            let config = PostHogSessionReplayConfig()
            config.sampleRate = NSNumber(value: 0.0)
            #expect(config.sampleRate?.doubleValue == 0.0)
        }

        @Test("sampleRate accepts 1.0")
        func sampleRateAcceptsOne() {
            let config = PostHogSessionReplayConfig()
            config.sampleRate = NSNumber(value: 1.0)
            #expect(config.sampleRate?.doubleValue == 1.0)
        }

        @Test("sampleRate rejects value above 1.0")
        func sampleRateRejectsAboveOne() {
            let config = PostHogSessionReplayConfig()
            config.sampleRate = NSNumber(value: 1.5)
            #expect(config.sampleRate == nil)
        }

        @Test("sampleRate rejects negative value")
        func sampleRateRejectsNegative() {
            let config = PostHogSessionReplayConfig()
            config.sampleRate = NSNumber(value: -0.5)
            #expect(config.sampleRate == nil)
        }
    }
#endif
