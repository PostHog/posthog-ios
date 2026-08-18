// Registration is iOS-only in v1: the backend rejects the `macos` platform (the open integration
// still supports macOS). See the push-notifications shared plan, decision 3.
#if os(iOS)
    import Foundation
    import UIKit
    import UserNotifications

    /// Subscribes to `PushNotificationPublisher.onDeviceToken` to automatically forward APNs tokens
    /// to PostHog.
    ///
    /// Swizzle installation and teardown are driven entirely by the publisher (via the subscriber-count
    /// callback), so this integration only owns the subscription token.
    @available(iOS 14.0, *)
    final class PostHogPushNotificationSubscriptionIntegration: PostHogIntegration {
        var requiresSwizzling: Bool { true }

        private static let integrationInstallState = PostHogIntegrationInstallState()

        private weak var postHog: PostHogSDK?
        private var token: RegistrationToken?

        func install(_ postHog: PostHogSDK) -> PostHogIntegrationInstallResult {
            installIfNeeded(using: Self.integrationInstallState) {
                self.postHog = postHog
                start()
            }
        }

        func uninstall(_ postHog: PostHogSDK) {
            uninstallIfNeeded(from: postHog, installedPostHog: self.postHog, state: Self.integrationInstallState) {
                stop()
                self.postHog = nil
            }
        }

        func start() {
            // App-only: `UIApplication.shared` is unavailable in app extensions, which can't register for
            // remote notifications anyway. This also skips test runners / CLI tools.
            let bundleExtension = Bundle.main.bundleURL.pathExtension
            guard bundleExtension == "app" else {
                hedgeLog("Push subscription integration: skipping setup - not running in an app context")
                return
            }
            token = DI.main.pushNotificationPublisher.onDeviceToken.subscribe { [weak self] tokenString in
                self?.postHog?.registerPushNotificationToken(tokenString)
            }
        }

        func stop() {
            token = nil
        }

        /// Re-requests the APNs device token so opting back in re-arms push without an app restart.
        /// A prior logout unregister clears the stored token, and opt-in only restores consent and the
        /// observer; asking the OS to register again redelivers the token to the swizzled callback, which
        /// re-registers it. Overridable in tests (posthog-ios#746).
        static var requestTokenRefresh: () -> Void = {
            // App-only: `UIApplication.shared` is unavailable in app extensions, which can't register for
            // remote notifications anyway.
            guard Bundle.main.bundleURL.pathExtension == "app" else { return }
            DispatchQueue.main.async {
                UIApplication.shared.registerForRemoteNotifications()
            }
        }
    }

    #if TESTING
        @available(iOS 14.0, *)
        extension PostHogPushNotificationSubscriptionIntegration {
            static func clearInstalls() {
                integrationInstallState.clear()
                PushNotificationPublisher.reset()
            }
        }
    #endif
#endif
