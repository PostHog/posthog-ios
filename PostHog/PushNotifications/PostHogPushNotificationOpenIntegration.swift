#if os(iOS) || os(macOS)
    import Foundation
    import UserNotifications

    /// Subscribes to `PushNotificationPublisher.onNotificationResponse` to automatically
    /// capture `$push_notification_opened` when a user taps a notification.
    ///
    /// Swizzle installation and teardown are driven entirely by the publisher via
    /// `PostHogMulticastCallback.onSubscriberCountChanged` — this integration only
    /// manages a `RegistrationToken`.
    @available(iOS 14.0, macOS 11.0, *)
    final class PostHogPushNotificationOpenIntegration: PostHogIntegration {
        var requiresSwizzling: Bool { true }

        private static var integrationInstalledLock = NSLock()
        private static var integrationInstalled = false

        private weak var postHog: PostHogSDK?
        private var token: RegistrationToken?

        func install(_ postHog: PostHogSDK) -> PostHogIntegrationInstallResult {
            let didInstall = Self.integrationInstalledLock.withLock {
                if Self.integrationInstalled { return false }
                Self.integrationInstalled = true
                return true
            }
            guard didInstall else { return .skipped(.alreadyInstalled) }
            self.postHog = postHog
            start()
            return .installed
        }

        func uninstall(_ postHog: PostHogSDK) {
            guard self.postHog === postHog || self.postHog == nil else { return }
            stop()
            self.postHog = nil
            Self.integrationInstalledLock.withLock {
                Self.integrationInstalled = false
            }
        }

        func start() {
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
                integrationInstalledLock.withLock {
                    integrationInstalled = false
                }
                PushNotificationPublisher.reset()
            }
        }
    #endif
#endif
