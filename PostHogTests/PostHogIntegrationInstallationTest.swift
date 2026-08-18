//
//  PostHogIntegrationInstallationTest.swift
//  PostHog
//
//  Created by Yiannis Josephides on 19/02/2025.
//

@testable import PostHog
import Testing
import XCTest

@Suite("Test integration installation", .serialized)
class PostHogIntegrationInstallationTest {
    var server: MockPostHogServer!

    init() {
        server = MockPostHogServer()
        server.start()
        #if os(iOS)
            PostHogReplayIntegration.clearInstalls()
        #endif
        #if os(iOS) || targetEnvironment(macCatalyst)
            PostHogAutocaptureIntegration.clearInstalls()
        #endif
        #if os(iOS) || os(macOS)
            if #available(iOS 14.0, macOS 11.0, *) {
                PostHogPushNotificationOpenIntegration.clearInstalls()
            }
        #endif
        #if os(iOS)
            if #available(iOS 14.0, *) {
                PostHogPushNotificationSubscriptionIntegration.clearInstalls()
            }
        #endif
        PostHogAppLifeCycleIntegration.clearInstalls()
        PostHogScreenViewIntegration.clearInstalls()
        #if os(iOS) || os(macOS) || os(tvOS)
            PostHogErrorTrackingAutoCaptureIntegration.clearInstalls()
        #endif
    }

    deinit {
        server.stop()
        server = nil
    }

    private func getSut(
        projectToken: String,
        sessionReplay: Bool = false,
        captureApplicationLifecycleEvents: Bool = false,
        captureScreenViews: Bool = false,
        captureElementInteractions: Bool = false,
        disableRemoteConfig: Bool = true,
        errorTrackingAutoCapture: Bool = false,
        enableSwizzling: Bool = true,
        capturePushNotificationOpened: Bool = false,
        capturePushNotificationSubscriptions: Bool = false
    ) -> PostHogSDK {
        let config = PostHogConfig(projectToken: projectToken, host: "http://localhost:9001")
        config.captureApplicationLifecycleEvents = captureApplicationLifecycleEvents
        config.disableRemoteConfigForTesting = disableRemoteConfig
        config.disableFlushOnBackgroundForTesting = true
        config.disableReachabilityForTesting = true
        config.enableSwizzling = enableSwizzling

        #if os(iOS)
            config.sessionReplay = sessionReplay
        #endif

        #if os(iOS) || targetEnvironment(macCatalyst)
            config.captureElementInteractions = captureElementInteractions
        #endif

        #if os(iOS) || os(macOS)
            // Keep push integrations opt-in per test; they default to true otherwise.
            config.capturePushNotificationSubscriptions = capturePushNotificationSubscriptions
            config.capturePushNotificationOpened = capturePushNotificationOpened
        #endif

        config.captureScreenViews = captureScreenViews
        config.errorTrackingConfig.autoCapture = errorTrackingAutoCapture

        let storage = PostHogStorage(config)
        storage.reset()

        return PostHogSDK.with(config)
    }

    #if os(iOS)
        @Test("replay integration installed only once, on first instance")
        func replayIntegrationInstalledOnce() {
            let first = getSut(projectToken: "test_project_token", sessionReplay: true)
            let second = getSut(projectToken: "test_project_token", sessionReplay: true)

            #expect(first.getReplayIntegration() != nil)
            #expect(second.getReplayIntegration() == nil)

            first.close()
            second.close()
        }
    #endif

    #if os(iOS) || targetEnvironment(macCatalyst)
        @Test("autocapture integration installed only once, on first instance")
        func autocaptureIntegrationInstalledOnce() async {
            let first = getSut(projectToken: "test_project_token", captureElementInteractions: true)
            let second = getSut(projectToken: "test_project_token", captureElementInteractions: true)

            #expect(first.getAutocaptureIntegration() != nil)
            #expect(second.getAutocaptureIntegration() == nil)

            first.close()
            second.close()
        }
    #endif

    @Test("app life cycle integration installed only once, on first instance")
    func appLifeCycleIntegrationInstalledOnce() async {
        let first = getSut(projectToken: "test_project_token", captureApplicationLifecycleEvents: true)
        let second = getSut(projectToken: "test_project_token", captureApplicationLifecycleEvents: true)

        #expect(first.getAppLifeCycleIntegration() != nil)
        #expect(second.getAppLifeCycleIntegration() == nil)

        first.close()
        second.close()
    }

    @Test("screen view integration installed only once, on first instance")
    func screenViewIntegrationInstalledOnce() async {
        let first = getSut(projectToken: "test_project_token", captureScreenViews: true)
        let second = getSut(projectToken: "test_project_token", captureScreenViews: true)

        #expect(first.getScreenViewIntegration() != nil)
        #expect(second.getScreenViewIntegration() == nil)

        first.close()
        second.close()
    }

    // MARK: - Error tracking integration

    #if os(iOS) || os(macOS) || os(tvOS)
        @Test("error tracking integration installed on first launch before remote config arrives")
        func errorTrackingInstalledBeforeRemoteConfig() {
            // disableRemoteConfig=true means hasFetchedRemoteConfig stays false.
            // The integration must install by default so a crash on the very first launch
            // (before /config responds) is not silently missed.
            let sut = getSut(
                projectToken: "test_error_tracking_\(UUID().uuidString)",
                disableRemoteConfig: true,
                errorTrackingAutoCapture: true
            )
            defer { sut.close() }

            #expect(sut.getErrorTrackingIntegration() != nil)
        }

        @Test("error tracking integration not installed when disk-cached remote config disables it")
        func errorTrackingNotInstalledWhenRemoteConfigDisables() async {
            // Remote fetch is disabled, so hasFetchedRemoteConfig stays false. The disk-cached config
            // (seeded below) is what flips hasCachedRemoteConfig → true, and with autocaptureExceptions=false
            // that makes the gate skip installation.
            let token = "test_error_tracking_\(UUID().uuidString)"
            let config = PostHogConfig(projectToken: token, host: "http://localhost:9001")
            config.disableRemoteConfigForTesting = true
            config.disableFlushOnBackgroundForTesting = true
            config.disableReachabilityForTesting = true
            config.errorTrackingConfig.autoCapture = true

            let storage = PostHogStorage(config)
            defer { storage.reset() }
            // Seed disk-cached config with autocapture disabled so hasCachedRemoteConfig → true
            storage.setDictionary(forKey: .remoteConfig, contents: ["errorTracking": ["autocaptureExceptions": false]])

            let sut = PostHogSDK.with(config)
            defer { sut.close() }

            #expect(sut.getErrorTrackingIntegration() == nil)
        }

        @Test("error tracking integration uninstalls when remote config loads with autocapture disabled")
        func errorTrackingUninstallsWhenRemoteConfigDisables() async {
            // Start with no cached config (hasFetchedRemoteConfig=false) → integration installs.
            // Then simulate remote config arriving with autocaptureExceptions=false → integration uninstalls.
            server.remoteConfigErrorTracking = ["autocaptureExceptions": false]
            // Hold the /config response so the installed-by-default state is observable before it lands.
            server.configResponseDelay = 0.5

            let token = "test_error_tracking_\(UUID().uuidString)"
            let config = PostHogConfig(projectToken: token, host: "http://localhost:9001")
            config.disableRemoteConfigForTesting = false
            config.preloadFeatureFlags = false
            config.disableFlushOnBackgroundForTesting = true
            config.disableReachabilityForTesting = true
            config.errorTrackingConfig.autoCapture = true

            let storage = PostHogStorage(config)
            defer { storage.reset() }
            // Ensure no cached remote config so hasFetchedRemoteConfig starts false
            storage.remove(key: .remoteConfig)

            let sut = PostHogSDK.with(config)
            defer { sut.close() }

            // Before /config arrives the integration must be installed (default-on)
            #expect(sut.getErrorTrackingIntegration() != nil)

            // Poll for the end state rather than awaiting onRemoteConfigLoaded: multicast callbacks
            // are unordered, so a subscriber can be notified before the integration's own removal
            // callback has run.
            await waitUntil(timeout: 10) { sut.getErrorTrackingIntegration() == nil }

            // After /config with autocaptureExceptions=false the integration must be removed
            #expect(sut.getErrorTrackingIntegration() == nil)
        }

        @Test("error tracking integration stays installed when remote config loads with autocapture enabled")
        func errorTrackingStaysInstalledWhenRemoteConfigEnables() async {
            server.remoteConfigErrorTracking = ["autocaptureExceptions": true]

            let token = "test_error_tracking_\(UUID().uuidString)"
            let config = PostHogConfig(projectToken: token, host: "http://localhost:9001")
            config.disableRemoteConfigForTesting = false
            config.preloadFeatureFlags = false
            config.disableFlushOnBackgroundForTesting = true
            config.disableReachabilityForTesting = true
            config.errorTrackingConfig.autoCapture = true

            let storage = PostHogStorage(config)
            defer { storage.reset() }
            storage.remove(key: .remoteConfig)

            let sut = PostHogSDK.with(config)
            defer { sut.close() }

            #expect(sut.getErrorTrackingIntegration() != nil)

            // onRemoteConfigLoaded is enqueued on main before hasFetchedRemoteConfig flips, so a
            // main-queue hop after the flag flips guarantees any removal callback has already run.
            await waitUntil(timeout: 10) { sut.remoteConfig?.hasFetchedRemoteConfig == true }
            await MainActor.run {}

            #expect(sut.getErrorTrackingIntegration() != nil)
        }

        @Test("error tracking integration installs when live remote config enables after a cached-disabled start")
        func errorTrackingInstallsWhenRemoteConfigEnablesAfterCachedDisable() async {
            // Disk cache disables autocapture → integration is skipped at startup. The live /config
            // then enables it → the integration must install rather than wait for the next launch.
            server.remoteConfigErrorTracking = ["autocaptureExceptions": true]
            server.configResponseDelay = 0.5

            let token = "test_error_tracking_\(UUID().uuidString)"
            let config = PostHogConfig(projectToken: token, host: "http://localhost:9001")
            config.disableRemoteConfigForTesting = false
            config.preloadFeatureFlags = false
            config.disableFlushOnBackgroundForTesting = true
            config.disableReachabilityForTesting = true
            config.errorTrackingConfig.autoCapture = true

            let storage = PostHogStorage(config)
            defer { storage.reset() }
            // Seed cached config with autocapture disabled so the startup gate skips installation.
            storage.setDictionary(forKey: .remoteConfig, contents: ["errorTracking": ["autocaptureExceptions": false]])

            let sut = PostHogSDK.with(config)
            defer { sut.close() }

            // Cached-disabled: not installed before the live /config lands.
            #expect(sut.getErrorTrackingIntegration() == nil)

            // Live /config enables autocapture → integration installs.
            await waitUntil(timeout: 10) { sut.getErrorTrackingIntegration() != nil }
            #expect(sut.getErrorTrackingIntegration() != nil)
        }

        @Test("error tracking integration installs on re-install after a failed /config fetch")
        func errorTrackingInstallsAfterFailedRemoteConfigFetch() async {
            // A failed /config sets hasFetchedRemoteConfig=true but leaves no config data. A later
            // re-install (here via optIn) must not read that failure as a remote disable — it should
            // install by default, just as a first launch would.
            let token = "test_error_tracking_\(UUID().uuidString)"
            let config = PostHogConfig(projectToken: token, host: "http://localhost:9001")
            config.disableRemoteConfigForTesting = true
            config.disableFlushOnBackgroundForTesting = true
            config.disableReachabilityForTesting = true
            config.errorTrackingConfig.autoCapture = true
            config.optOut = true // integrations are not installed while opted out

            let storage = PostHogStorage(config)
            storage.reset() // no cached config → the only remote state is the simulated failed fetch
            defer { storage.reset() }

            let sut = PostHogSDK.with(config)
            defer { sut.close() }

            #expect(sut.getErrorTrackingIntegration() == nil) // opted out, not installed yet

            // Simulate a completed-but-failed /config: fetched flag set, no config data stored.
            sut.remoteConfig?.setRemoteConfigDidFetchForTesting(true)

            sut.optIn() // triggers re-install with a fetched-but-failed remote config
            #expect(sut.getErrorTrackingIntegration() != nil)
        }
    #endif

    #if os(iOS) || os(macOS)
        @Test("push notification opened integration installed only once, on first instance")
        func pushNotificationOpenedIntegrationInstalledOnce() async {
            guard #available(iOS 14.0, macOS 11.0, *) else { return }
            let first = getSut(projectToken: "test_project_token", capturePushNotificationOpened: true)
            let second = getSut(projectToken: "test_project_token", capturePushNotificationOpened: true)

            #expect(first.getPushNotificationIntegration() != nil)
            #expect(second.getPushNotificationIntegration() == nil)

            first.close()
            second.close()
        }

        @Test("push notification opened integration not installed when the flag is disabled")
        func pushNotificationOpenedIntegrationNotInstalledWhenDisabled() async {
            guard #available(iOS 14.0, macOS 11.0, *) else { return }
            let sut = getSut(projectToken: "test_project_token", capturePushNotificationOpened: false)

            #expect(sut.getPushNotificationIntegration() == nil)

            sut.close()
        }

        @Test("push notification opened integration skipped when swizzling is disabled")
        func pushNotificationOpenedIntegrationSkippedWithoutSwizzling() async {
            guard #available(iOS 14.0, macOS 11.0, *) else { return }
            let sut = getSut(projectToken: "test_project_token", enableSwizzling: false, capturePushNotificationOpened: true)

            #expect(sut.getPushNotificationIntegration() == nil)

            sut.close()
        }

    #endif

    #if os(iOS)
        @Test("push notification subscription integration installed only once, on first instance")
        func pushNotificationSubscriptionIntegrationInstalledOnce() async {
            guard #available(iOS 14.0, *) else { return }
            let first = getSut(projectToken: "test_project_token", capturePushNotificationSubscriptions: true)
            let second = getSut(projectToken: "test_project_token", capturePushNotificationSubscriptions: true)

            #expect(first.getPushNotificationSubscriptionIntegration() != nil)
            #expect(second.getPushNotificationSubscriptionIntegration() == nil)

            first.close()
            second.close()
        }

        @Test("push notification subscription integration not installed when the flag is disabled")
        func pushNotificationSubscriptionIntegrationNotInstalledWhenDisabled() async {
            guard #available(iOS 14.0, *) else { return }
            let sut = getSut(projectToken: "test_project_token", capturePushNotificationSubscriptions: false)

            #expect(sut.getPushNotificationSubscriptionIntegration() == nil)

            sut.close()
        }

        @Test("push notification subscription integration skipped when swizzling is disabled")
        func pushNotificationSubscriptionIntegrationSkippedWithoutSwizzling() async {
            guard #available(iOS 14.0, *) else { return }
            let sut = getSut(projectToken: "test_project_token", enableSwizzling: false, capturePushNotificationSubscriptions: true)

            #expect(sut.getPushNotificationSubscriptionIntegration() == nil)

            sut.close()
        }
    #endif
}
