//
//  PostHogScreenViewIntegration.swift
//  PostHog
//
//  Created by Ioannis Josephides on 20/02/2025.
//

import Foundation

final class PostHogScreenViewIntegration: PostHogIntegration {
    var requiresSwizzling: Bool { true }

    private static let integrationInstallState = PostHogIntegrationInstallState()

    private weak var postHog: PostHogSDK?

    func install(_ postHog: PostHogSDK) -> PostHogIntegrationInstallResult {
        installIfNeeded(using: Self.integrationInstallState) {
            self.postHog = postHog

            start()
        }
    }

    func uninstall(_ postHog: PostHogSDK) {
        uninstallIfNeeded(from: postHog, installedPostHog: self.postHog, state: Self.integrationInstallState) {
            // uninstall only for integration instance
            stop()
            self.postHog = nil
        }
    }

    func start() {
        // We own the swizzle directly via startAutoCapture rather than
        // subscribing to onScreenView. Subscribing would put us downstream of
        // PostHogSDK.screen()'s own publisher invoke, so every manual
        // screen() call would fire two events instead of one.
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
            integrationInstallState.clear()
        }
    }
#endif
