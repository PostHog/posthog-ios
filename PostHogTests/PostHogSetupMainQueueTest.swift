import Foundation
import OHHTTPStubs
import OHHTTPStubsSwift
@testable import PostHog
import Testing

/// `setup()` holds its lock while it installs integrations, and remote config and feature flags
/// notify on the main queue. These tests hold `setup()` inside an integration's `install`, off the
/// main thread, and check that the main queue still delivers both notifications.
@Suite("Main queue during setup", .serialized)
final class PostHogSetupMainQueueTest {
    let server = MockPostHogServer()

    init() {
        server.start()
    }

    deinit {
        server.stop()
    }

    @Test("delivers the remote config notification while setup is still installing integrations")
    func remoteConfigNotification() async {
        #expect(await isDeliveredDuringSetup(.remoteConfig))
    }

    @Test("delivers the feature flags notification while setup is still installing integrations")
    func featureFlagsNotification() async {
        #expect(await isDeliveredDuringSetup(.featureFlags))
    }

    private func isDeliveredDuringSetup(_ notification: SetupHoldingIntegration.Notification) async -> Bool {
        let integration = SetupHoldingIntegration(awaiting: notification)
        let config = SetupHoldingConfig(projectToken: "setup_main_queue_\(notification)", host: "http://localhost:9001")
        config.integration = integration
        // The integration starts the request itself, once it is subscribed
        config.disableRemoteConfigForTesting = true
        config.disableReachabilityForTesting = true
        config.disableQueueTimerForTesting = true
        config.disableFlushOnBackgroundForTesting = true
        PostHogStorage(config).reset()

        let sut: PostHogSDK = await withCheckedContinuation { continuation in
            DispatchQueue.global().async {
                continuation.resume(returning: PostHogSDK.with(config))
            }
        }
        defer { sut.close() }
        return integration.wasDeliveredDuringInstall
    }
}

private final class SetupHoldingConfig: PostHogConfig {
    var integration: PostHogIntegration?

    override func getIntegrations() -> [PostHogIntegration] {
        [integration].compactMap { $0 }
    }
}

/// Runs inside `setup()`, so `install` returns only once the awaited notification has reached the
/// main queue, or the wait has timed out.
private final class SetupHoldingIntegration: PostHogIntegration {
    enum Notification {
        case remoteConfig
        case featureFlags
    }

    let requiresSwizzling = false

    private let notification: Notification
    private let delivered = DispatchSemaphore(value: 0)
    private var token: RegistrationToken?
    private(set) var wasDeliveredDuringInstall = false

    init(awaiting notification: Notification) {
        self.notification = notification
    }

    func install(_ postHog: PostHogSDK) -> PostHogIntegrationInstallResult {
        guard let remoteConfig = postHog.remoteConfig else {
            return .installed
        }

        // Subscribed after the SDK's own subscribers, so this runs only once they have returned
        switch notification {
        case .remoteConfig:
            token = remoteConfig.onRemoteConfigLoaded.subscribe { [delivered] _ in delivered.signal() }
            remoteConfig.reloadRemoteConfig()
        case .featureFlags:
            token = remoteConfig.onFeatureFlagsLoaded.subscribe { [delivered] _ in delivered.signal() }
            remoteConfig.reloadFeatureFlags()
        }

        wasDeliveredDuringInstall = delivered.wait(timeout: .now() + 5) == .success
        return .installed
    }

    func uninstall(_: PostHogSDK) {
        token = nil
    }

    func start() {}

    func stop() {}
}

/// The push subscriber registered in `setup()` hands the handler a completion that records the one-time
/// push recovery as done. The handler also calls it when `close()` released the handler first.
@Suite("Push migration flag after close", .serialized)
final class PostHogPushMigrationAfterCloseTest {
    let server = MockPostHogServer()
    let pushConfigStub: HTTPStubsDescriptor

    init() {
        server.start()
        pushConfigStub = stub(condition: pathEndsWith("/config")) { _ in
            HTTPStubsResponse(jsonObject: ["push": ["appIds": ["com.example.app"]]], statusCode: 200, headers: nil)
        }
    }

    deinit {
        HTTPStubs.removeStub(pushConfigStub)
        server.stop()
    }

    @Test("is not set when close() releases the push handler before it ran")
    func migrationFlagAfterClose() async throws {
        let config = PostHogConfig(projectToken: "push_migration_after_close", host: "http://localhost:9001")
        config.disableRemoteConfigForTesting = true
        config.disableReachabilityForTesting = true
        config.disableQueueTimerForTesting = true
        config.disableFlushOnBackgroundForTesting = true
        config.preloadFeatureFlags = false
        let storage = PostHogStorage(config)
        storage.reset()
        storage.remove(key: .pushAppIdsMigrated)
        storage.remove(key: .remoteConfig)

        let sut = PostHogSDK.with(config)
        // Held like an in-flight request would hold it, so the instance outlives close()
        let remoteConfig = try #require(sut.remoteConfig)

        // Park the handler's queue so close() runs before the handler does
        let handlerQueue = try #require(Self.pushHandlerQueue(of: sut))
        let closed = DispatchSemaphore(value: 0)
        handlerQueue.async { closed.wait() }

        var token: RegistrationToken?
        await withCheckedContinuation { continuation in
            // Subscribed after the SDK's push subscriber, so the handler has been called by now
            token = remoteConfig.onRemoteConfigLoaded.subscribe { _ in continuation.resume() }
            remoteConfig.reloadRemoteConfig()
        }
        withExtendedLifetime(token) {}

        sut.close()
        closed.signal()
        handlerQueue.sync {}

        #expect(storage.getBool(forKey: .pushAppIdsMigrated) != true)
    }

    @Test("does not run the push subscriber when a /config load finishes after close()")
    func pushSubscriberAfterClose() async throws {
        let config = PostHogConfig(projectToken: "push_subscriber_after_close", host: "http://localhost:9001")
        config.disableRemoteConfigForTesting = true
        config.disableReachabilityForTesting = true
        config.disableQueueTimerForTesting = true
        config.disableFlushOnBackgroundForTesting = true
        config.preloadFeatureFlags = false
        let storage = PostHogStorage(config)
        storage.reset()
        storage.remove(key: .pushAppIdsMigrated)
        storage.remove(key: .remoteConfig)

        let sut = PostHogSDK.with(config)
        let remoteConfig = try #require(sut.remoteConfig)
        sut.close()

        #expect(remoteConfig.onRemoteConfigLoaded.subscriberCount == 0)

        var remainingAfterCallback: Set<String> = []
        var token: RegistrationToken?
        await withCheckedContinuation { continuation in
            token = remoteConfig.onRemoteConfigLoaded.subscribe { _ in
                remainingAfterCallback = remoteConfig.consumeNewlyRegisterablePushAppIds()
                continuation.resume()
            }
            remoteConfig.reloadRemoteConfig()
        }
        withExtendedLifetime(token) {}

        #expect(remainingAfterCallback == ["com.example.app"])
    }

    @Test("does not run the push subscriber when a /config load finishes while close() is still running")
    func pushSubscriberDuringClose() async throws {
        let config = PostHogConfig(projectToken: "push_subscriber_during_close", host: "http://localhost:9001")
        config.disableRemoteConfigForTesting = true
        config.disableReachabilityForTesting = true
        config.disableQueueTimerForTesting = true
        config.disableFlushOnBackgroundForTesting = true
        config.preloadFeatureFlags = false
        let storage = PostHogStorage(config)
        storage.reset()
        storage.remove(key: .pushAppIdsMigrated)
        storage.remove(key: .remoteConfig)

        let sut = PostHogSDK.with(config)
        let remoteConfig = try #require(sut.remoteConfig)
        // Held like its queued work would hold it, so the subscriber still finds it after close() lets go
        let handler = try #require(Self.pushHandler(of: sut))
        defer { withExtendedLifetime(handler) {} }
        sut.addExceptionStep("seed")

        // close() clears the exception steps while it holds its lock: hold it there
        let enteredClose = DispatchSemaphore(value: 0)
        let allowCloseToFinish = DispatchSemaphore(value: 0)
        var didPauseClose = false
        let stepsToken = sut.onExceptionStepsChanged.subscribe { steps in
            if steps.isEmpty, !didPauseClose {
                didPauseClose = true
                enteredClose.signal()
                _ = allowCloseToFinish.wait(timeout: .now() + 5)
            }
        }
        defer { withExtendedLifetime(stepsToken) {} }

        let closeFinished = DispatchSemaphore(value: 0)
        DispatchQueue.global().async {
            sut.close()
            closeFinished.signal()
        }
        #expect(enteredClose.wait(timeout: .now() + 2) == .success)

        var remainingAfterCallback: Set<String> = []
        var token: RegistrationToken?
        await withCheckedContinuation { continuation in
            token = remoteConfig.onRemoteConfigLoaded.subscribe { _ in
                remainingAfterCallback = remoteConfig.consumeNewlyRegisterablePushAppIds()
                continuation.resume()
            }
            remoteConfig.reloadRemoteConfig()
        }
        withExtendedLifetime(token) {}

        allowCloseToFinish.signal()
        #expect(closeFinished.wait(timeout: .now() + 2) == .success)

        #expect(remainingAfterCallback == ["com.example.app"])
    }

    private static func pushHandler(of sdk: PostHogSDK) -> AnyObject? {
        Mirror(reflecting: sdk).descendant("pushSubscriptionHandler", "some") as AnyObject?
    }

    private static func pushHandlerQueue(of sdk: PostHogSDK) -> DispatchQueue? {
        pushHandler(of: sdk).flatMap { Mirror(reflecting: $0).descendant("workQueue") as? DispatchQueue }
    }
}

/// A `/flags` load in flight when `close()` runs belongs to the setup being closed, so its result
/// reaches no `onFeatureFlags` listener.
@Suite("Feature flags load during close", .serialized)
final class PostHogFlagsLoadDuringCloseTest {
    let server = MockPostHogServer()

    init() {
        server.start()
    }

    deinit {
        server.stop()
    }

    @Test("is not delivered when it completes while close() is still running")
    func inFlightFlagsDuringClose() async throws {
        let config = PostHogConfig(projectToken: "flags_in_flight_during_close", host: "http://localhost:9001")
        config.disableRemoteConfigForTesting = true
        config.disableReachabilityForTesting = true
        config.disableQueueTimerForTesting = true
        config.disableFlushOnBackgroundForTesting = true
        config.preloadFeatureFlags = false
        PostHogStorage(config).reset()

        let flagsRequestStarted = DispatchSemaphore(value: 0)
        let releaseFlagsResponse = DispatchSemaphore(value: 0)
        let flagsStub = stub(condition: pathEndsWith("/flags")) { _ in
            flagsRequestStarted.signal()
            _ = releaseFlagsResponse.wait(timeout: .now() + 5)
            return HTTPStubsResponse(
                jsonObject: ["featureFlags": ["flag-a": true], "errorsWhileComputingFlags": false],
                statusCode: 200,
                headers: nil
            )
        }
        defer { HTTPStubs.removeStub(flagsStub) }

        let sut = PostHogSDK.with(config)
        let remoteConfig = try #require(sut.remoteConfig)
        sut.addExceptionStep("seed")

        // close() clears the exception steps while it holds its lock: hold it there
        let enteredClose = DispatchSemaphore(value: 0)
        let allowCloseToFinish = DispatchSemaphore(value: 0)
        var didPauseClose = false
        let stepsToken = sut.onExceptionStepsChanged.subscribe { steps in
            if steps.isEmpty, !didPauseClose {
                didPauseClose = true
                enteredClose.signal()
                _ = allowCloseToFinish.wait(timeout: .now() + 5)
            }
        }
        defer { withExtendedLifetime(stepsToken) {} }

        let receivedOnMain = DispatchSemaphore(value: 0)
        var deliveredCount = 0
        let subscription = sut.onFeatureFlags { _ in
            deliveredCount += 1
            receivedOnMain.signal()
        }
        defer { subscription.unsubscribe() }

        remoteConfig.reloadFeatureFlags()
        #expect(flagsRequestStarted.wait(timeout: .now() + 2) == .success)

        let closeFinished = DispatchSemaphore(value: 0)
        DispatchQueue.global().async {
            sut.close()
            closeFinished.signal()
        }
        #expect(enteredClose.wait(timeout: .now() + 2) == .success)

        releaseFlagsResponse.signal()
        _ = receivedOnMain.wait(timeout: .now() + 0.5)

        allowCloseToFinish.signal()
        #expect(closeFinished.wait(timeout: .now() + 2) == .success)
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async { continuation.resume() }
        }

        #expect(deliveredCount == 0)
    }
}
