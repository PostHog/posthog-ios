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

    private static func pushHandlerQueue(of sdk: PostHogSDK) -> DispatchQueue? {
        let handler = Mirror(reflecting: sdk).descendant("pushSubscriptionHandler", "some")
        return handler.flatMap { Mirror(reflecting: $0).descendant("workQueue") as? DispatchQueue }
    }
}
