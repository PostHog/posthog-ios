//
//  PostHogScreenViewIntegration.swift
//  PostHog
//
//  Created by Ioannis Josephides on 20/02/2025.
//

import Foundation

final class PostHogScreenViewIntegration: PostHogIntegration {
    var requiresSwizzling: Bool { true }

    private static var integrationInstalledLock = NSLock()
    private static var integrationInstalled = false

    private weak var postHog: PostHogSDK?

    func install(_ postHog: PostHogSDK) -> PostHogIntegrationInstallResult {
        let didInstall = PostHogScreenViewIntegration.integrationInstalledLock.withLock {
            if PostHogScreenViewIntegration.integrationInstalled {
                return false
            }
            PostHogScreenViewIntegration.integrationInstalled = true
            return true
        }

        guard didInstall else {
            return .skipped(.alreadyInstalled)
        }

        self.postHog = postHog

        start()
        return .installed
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

    func start() {
        DI.main.screenViewPublisher.startAutoCapture { [weak self] screenName in
            self?.postHog?.screen(screenName)
        }
    }

    func stop() {
        DI.main.screenViewPublisher.stopAutoCapture()
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
