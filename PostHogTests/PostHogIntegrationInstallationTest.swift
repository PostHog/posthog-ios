//
//  PostHogIntegrationInstallationTest.swift
//  PostHog
//
//  Created by Yiannis Josephides on 19/02/2025.
//

@testable import PostHog
import Testing

@Suite("PostHog integration installation tests", .serialized)
class PostHogIntegrationInstallationTest {
    var firstInstance: PostHogSDK!
    var secondInstance: PostHogSDK!

    init() {
        firstInstance = PostHogSDK.with(PostHogConfig(apiKey: "123"))
        secondInstance = PostHogSDK.with(PostHogConfig(apiKey: "1234"))
    }

    deinit {
        firstInstance.close()
        secondInstance.close()
    }

    #if os(iOS)
        @Test("replay integration installed only once, on first instance")
        func replayIntegrationInstalledOnce() {
            #expect(firstInstance.getReplayIntegration() != nil)
            #expect(secondInstance.getReplayIntegration() == nil)
        }
    #endif

    #if os(iOS) || targetEnvironment(macCatalyst)
        @Test("autocapture integration installed only once, on first instance")
        func autocaptureIntegrationInstalledOnce() async {
            #expect(secondInstance.getAutocaptureIntegration() == nil)
            #expect(firstInstance.getAutocaptureIntegration() != nil)
        }
    #endif

    @Test("app life cycle integration installed only once, on first instance")
    func appLifeCycleIntegrationInstalledOnce() async {
        #expect(secondInstance.getAppLifeCycleIntegration() == nil)
        #expect(firstInstance.getAppLifeCycleIntegration() != nil)
    }
}
