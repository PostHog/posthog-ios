#if os(iOS) || os(macOS)
    import Foundation
    import UserNotifications

    /// Subscribes to `PushNotificationPublisher.onNotificationResponse` to automatically capture
    /// `$push_notification_opened` when a user taps a notification.
    ///
    /// Swizzle installation and teardown are driven entirely by the publisher (via the subscriber-count
    /// callback), so this integration only owns the subscription token.
    @available(iOS 14.0, macOS 11.0, *)
    final class PostHogPushNotificationOpenIntegration: PostHogIntegration {
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
            // UNUserNotificationCenter needs a real app bundle; skip in test runners / CLI tools.
            let bundleExtension = Bundle.main.bundleURL.pathExtension
            guard bundleExtension == "app" || bundleExtension == "appex" else {
                hedgeLog("Push notification opened integration: skipping setup - not running in an app context")
                return
            }
            token = DI.main.pushNotificationPublisher.onNotificationResponse.subscribe { [weak self] response in
                self?.postHog?.capturePushNotificationOpened(response: response)
            }
        }

        func stop() {
            token = nil
        }
    }

    #if TESTING
        @available(iOS 14.0, macOS 11.0, *)
        extension PostHogPushNotificationOpenIntegration {
            static func clearInstalls() {
                integrationInstallState.clear()
                PushNotificationPublisher.reset()
            }
        }
    #endif
#endif
