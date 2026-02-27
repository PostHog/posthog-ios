//
//  PostHogIntegrationInstallationTest.swift
//  PostHog
//
//  Created by Yiannis Josephides on 19/02/2025.
//

@testable import PostHog
import Testing

@Suite("Test integration installation", .serialized)
class PostHogIntegrationInstallationTest: PostHogSDKBaseTest {
    init() {
        super.init()
        #if os(iOS)
            PostHogReplayIntegration.clearInstalls()
        #endif
        #if os(iOS) || targetEnvironment(macCatalyst)
            PostHogAutocaptureIntegration.clearInstalls()
        #endif
        PostHogAppLifeCycleIntegration.clearInstalls()
        PostHogScreenViewIntegration.clearInstalls()
    }

    private func getSut(
        apiKey: String = uniqueApiKey(),
        sessionReplay: Bool = false,
        captureApplicationLifecycleEvents: Bool = false,
        captureScreenViews: Bool = false,
        captureElementInteractions: Bool = false
    ) -> PostHogSDK {
        let config = makeConfig(apiKey: apiKey)
        config.captureApplicationLifecycleEvents = captureApplicationLifecycleEvents

        #if os(iOS)
            config.sessionReplay = sessionReplay
        #endif

        #if os(iOS) || targetEnvironment(macCatalyst)
            config.captureElementInteractions = captureElementInteractions
        #endif

        config.captureScreenViews = captureScreenViews
        return makeSDK(config: config)
    }

    #if os(iOS)
        @Test("replay integration installed only once, on first instance")
        func replayIntegrationInstalledOnce() {
            let first = getSut(apiKey: "123", sessionReplay: true)
            let second = getSut(apiKey: "345", sessionReplay: true)

            #expect(first.getReplayIntegration() != nil)
            #expect(second.getReplayIntegration() == nil)

            first.close()
            second.close()
        }
    #endif

    #if os(iOS) || targetEnvironment(macCatalyst)
        @Test("autocapture integration installed only once, on first instance")
        func autocaptureIntegrationInstalledOnce() async {
            let first = getSut(apiKey: "123", captureElementInteractions: true)
            let second = getSut(apiKey: "345", captureElementInteractions: true)

            #expect(first.getAutocaptureIntegration() != nil)
            #expect(second.getAutocaptureIntegration() == nil)

            first.close()
            second.close()
        }
    #endif

    @Test("app life cycle integration installed only once, on first instance")
    func appLifeCycleIntegrationInstalledOnce() async {
        let first = getSut(apiKey: "123", captureApplicationLifecycleEvents: true)
        let second = getSut(apiKey: "345", captureApplicationLifecycleEvents: true)

        #expect(first.getAppLifeCycleIntegration() != nil)
        #expect(second.getAppLifeCycleIntegration() == nil)

        first.close()
        second.close()
    }

    @Test("screen view integration installed only once, on first instance")
    func screenViewIntegrationInstalledOnce() async {
        let first = getSut(apiKey: "123", captureScreenViews: true)
        let second = getSut(apiKey: "345", captureScreenViews: true)

        #expect(first.getScreenViewIntegration() != nil)
        #expect(second.getScreenViewIntegration() == nil)

        first.close()
        second.close()
    }
}
