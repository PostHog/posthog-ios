import Foundation
@_spi(PostHogInternal) @testable import PostHog
import Testing

@Suite("Opt-out persistence", .serialized)
final class PostHogOptOutPersistenceTest {
    private let token = "test_opt_out_\(UUID().uuidString)"
    private var cleanup: (() -> Void)?

    deinit { cleanup?() }

    private func makeSut(optOut: Bool, persistOptOut: Bool = true, persisted: Bool? = nil) -> PostHogSDK {
        let config = PostHogConfig(projectToken: token, host: "http://localhost:9001")
        config.preloadFeatureFlags = false
        config.sendFeatureFlagEvent = false
        config.disableRemoteConfigForTesting = true
        config.disableReachabilityForTesting = true
        config.disableQueueTimerForTesting = true
        config.disableFlushOnBackgroundForTesting = true
        config.captureApplicationLifecycleEvents = false
        config.captureScreenViews = false
        config.errorTrackingConfig.autoCapture = false
        #if os(iOS)
            config.sessionReplay = false
        #endif
        config.optOut = optOut
        config.persistOptOut = persistOptOut

        let storage = PostHogStorage(config)
        storage.reset()
        cleanup = { storage.reset() }
        if let persisted {
            storage.setBool(forKey: .optOut, contents: persisted)
        }
        return PostHogSDK.with(config)
    }

    private func persistedOptOut() -> Bool? {
        PostHogStorage(PostHogConfig(projectToken: token, host: "http://localhost:9001")).getBool(forKey: .optOut)
    }

    // MARK: - Default: the SDK owns the state (unchanged behavior)

    @Test("a persisted opt-out outranks an opted-in config")
    func persistedOptOutWins() {
        let sut = makeSut(optOut: false, persisted: true)
        defer { sut.close() }

        #expect(sut.isOptOut() == true)
    }

    @Test("a persisted opt-in outranks an opted-out config")
    func persistedOptInWins() {
        let sut = makeSut(optOut: true, persisted: false)
        defer { sut.close() }

        #expect(sut.isOptOut() == false)
    }

    @Test("the config decides when nothing is persisted")
    func configDecidesWithoutPersistedState() {
        let sut = makeSut(optOut: true)
        defer { sut.close() }

        #expect(sut.isOptOut() == true)
    }

    @Test("optOut() and optIn() write the state to disk")
    func runtimeChangesArePersisted() {
        let sut = makeSut(optOut: false)
        defer { sut.close() }

        sut.optOut()
        #expect(persistedOptOut() == true)

        sut.optIn()
        #expect(persistedOptOut() == false)
    }

    // MARK: - persistOptOut = false: the host owns the state

    @Test("the config outranks a persisted opt-in")
    func hostOptOutBeatsPersistedOptIn() {
        let sut = makeSut(optOut: true, persistOptOut: false, persisted: false)
        defer { sut.close() }

        #expect(sut.isOptOut() == true)
    }

    @Test("the config outranks a persisted opt-out")
    func hostOptInBeatsPersistedOptOut() {
        let sut = makeSut(optOut: false, persistOptOut: false, persisted: true)
        defer { sut.close() }

        #expect(sut.isOptOut() == false)
    }

    @Test("optOut() changes the running SDK without writing to disk")
    func runtimeOptOutIsNotPersisted() {
        let sut = makeSut(optOut: false, persistOptOut: false)
        defer { sut.close() }

        sut.optOut()

        #expect(sut.isOptOut() == true)
        #expect(persistedOptOut() == nil)
    }

    @Test("optIn() leaves a value an earlier build stored untouched")
    func runtimeOptInLeavesStoredValueAlone() {
        let sut = makeSut(optOut: true, persistOptOut: false, persisted: true)
        defer { sut.close() }

        sut.optIn()

        #expect(sut.isOptOut() == false)
        #expect(persistedOptOut() == true)
    }

    @Test("optIn() changes the running SDK without writing to disk")
    func runtimeOptInIsNotPersisted() {
        let sut = makeSut(optOut: true, persistOptOut: false)
        defer { sut.close() }

        sut.optIn()

        #expect(sut.isOptOut() == false)
        #expect(persistedOptOut() == nil)
    }
}
