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
        errorTrackingAutoCapture: Bool = false
    ) -> PostHogSDK {
        let config = PostHogConfig(projectToken: projectToken, host: "http://localhost:9001")
        config.captureApplicationLifecycleEvents = captureApplicationLifecycleEvents
        config.disableRemoteConfigForTesting = disableRemoteConfig
        config.disableFlushOnBackgroundForTesting = true
        config.disableReachabilityForTesting = true

        #if os(iOS)
            config.sessionReplay = sessionReplay
        #endif

        #if os(iOS) || targetEnvironment(macCatalyst)
            config.captureElementInteractions = captureElementInteractions
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

        @Test("error tracking integration not installed when remote config already loaded and disabled")
        func errorTrackingNotInstalledWhenRemoteConfigDisables() async {
            // Seed the cached remote config with autocaptureExceptions=false so hasFetchedRemoteConfig
            // is true and the gate blocks installation.
            let token = "test_error_tracking_\(UUID().uuidString)"
            let config = PostHogConfig(projectToken: token, host: "http://localhost:9001")
            config.disableRemoteConfigForTesting = true
            config.disableFlushOnBackgroundForTesting = true
            config.disableReachabilityForTesting = true
            config.errorTrackingConfig.autoCapture = true

            let storage = PostHogStorage(config)
            defer { storage.reset() }
            // Seed cached config with autocapture disabled so hasFetchedRemoteConfig → true
            storage.setDictionary(forKey: .remoteConfig, contents: ["errorTracking": ["autocaptureExceptions": false]])

            let sut = PostHogSDK.with(config)
            defer { sut.close() }

            #expect(sut.getErrorTrackingIntegration() == nil)
        }

        @Test("error tracking integration uninstalls when remote config loads with autocapture disabled")
        func errorTrackingUninstallsWhenRemoteConfigDisables() async {
            // Start with no cached config (hasFetchedRemoteConfig=false) → integration installs.
            // Then simulate remote config arriving with autocaptureExceptions=false → integration uninstalls.
            server.configResponseDelay = 0.5
            server.remoteConfigErrorTracking = ["autocaptureExceptions": false]

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

            // Wait for /config to arrive
            let remoteConfigLoaded = AsyncLatch()
            let token2 = sut.remoteConfig?.onRemoteConfigLoaded.subscribe { _ in remoteConfigLoaded.signal() }
            await remoteConfigLoaded.wait()
            _ = token2

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

            let remoteConfigLoaded = AsyncLatch()
            let token2 = sut.remoteConfig?.onRemoteConfigLoaded.subscribe { _ in remoteConfigLoaded.signal() }
            await remoteConfigLoaded.wait()
            _ = token2

            #expect(sut.getErrorTrackingIntegration() != nil)
        }
    #endif
}
