//
//  PostHogScreenViewIntegration.swift
//  PostHog
//
//  Created by Ioannis Josephides on 20/02/2025.
//

import Foundation

final class PostHogScreenViewIntegration {
    private static var integrationInstalledLock = NSLock()
    private static var integrationInstalled = false

    private weak var postHog: PostHogSDK?
    private var screenViewToken: RegistrationToken?

    init?(_ posthog: PostHogSDK) {
        let wasInstalled = PostHogScreenViewIntegration.integrationInstalledLock.withLock {
            if PostHogScreenViewIntegration.integrationInstalled {
                hedgeLog("Autocapture integration already installed to another PostHogSDK instance.")
                return true
            }
            PostHogScreenViewIntegration.integrationInstalled = true
            return false
        }

        guard !wasInstalled else { return nil }

        postHog = posthog
    }

    func uninstall(_ postHog: PostHogSDK) {
        // uninstall only for integration instance
        if self.postHog === postHog || self.postHog == nil {
            self.postHog = nil
            PostHogScreenViewIntegration.integrationInstalledLock.withLock {
                PostHogScreenViewIntegration.integrationInstalled = false
            }
        }
    }

    /**
     Start capturing screen view events
     */
    func start() {
        let screenViewPublisher = DI.main.screenViewPublisher
        screenViewToken = screenViewPublisher.onScreenView { [weak self] screen in
            self?.captureScreenView(screen: screen)
        }
    }

    /**
     Stop capturing screen view events
     */
    func stop() {
        screenViewToken = nil
    }

    private func captureScreenView(screen screenName: String) {
        guard let postHog, postHog.config.captureScreenViews else { return }

        postHog.screen(screenName)
    }
}
