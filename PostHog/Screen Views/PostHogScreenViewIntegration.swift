//
//  PostHogScreenViewIntegration.swift
//  PostHog
//
//  Created by Ioannis Josephides on 20/02/2025.
//

import Foundation

final class PostHogScreenViewIntegration: PostHogIntegration {
    private static var integrationInstalledLock = NSLock()
    private static var integrationInstalled = false

    private weak var postHog: PostHogSDK?
    private var screenViewToken: RegistrationToken?

    func install(_ postHog: PostHogSDK) throws {
        try PostHogScreenViewIntegration.integrationInstalledLock.withLock {
            if PostHogScreenViewIntegration.integrationInstalled {
                throw InternalPostHogError(description: "Autocapture integration already installed to another PostHogSDK instance.")
            }
            PostHogScreenViewIntegration.integrationInstalled = true
        }

        self.postHog = postHog

        start()
    }

    func uninstall(_ postHog: PostHogSDK) {
        // uninstall only for integration instance
        if self.postHog === postHog || self.postHog == nil {
            stop()
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
        guard let postHog else { return }

        if postHog.config.captureScreenViews {
            postHog.screen(screenName)
        } else {
            hedgeLog("Skipping $screen event - captureScreenViews is disabled in configuration")
        }
    }
}

#if TESTING
    extension PostHogScreenViewIntegration {
        static func clearInstalls() {
            integrationInstalledLock.withLock {
                integrationInstalled = false
            }
        }
    }
#endif
