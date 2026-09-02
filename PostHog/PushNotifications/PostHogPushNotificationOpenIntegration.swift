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

        /// No lifecycle hook says "the app is finished installing its notification delegate", so the
        /// absence of one can only be concluded from a deadline. Long enough for an app that installs
        /// it during launch, short enough that the warning lands in the same debugging session.
        private static let missingDelegateGracePeriod: TimeInterval = 5

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
                self?.capture(response)
            }

            // Draining after subscribing, so a response racing this call is never dropped.
            if let pending = DI.main.pushNotificationPublisher.consumePendingNotificationResponse() {
                capture(pending)
            }

            warnIfNoNotificationDelegate(while: token)
        }

        private func capture(_ response: UNNotificationResponse) {
            // Auto-capture remote pushes only. A local
            // notification (calendar/interval/location trigger, or none) is the app's own, not a
            // delivered push; users who want to capture those can call
            // `capturePushNotificationOpened(response:)` themselves — it stays unfiltered.
            // Exclude dismiss actions: a `.customDismissAction` category invokes this same delegate
            // callback on swipe-to-dismiss, which is not the user "opening" the notification.
            guard response.notification.request.trigger is UNPushNotificationTrigger,
                  response.actionIdentifier != UNNotificationDismissActionIdentifier
            else {
                return
            }
            postHog?.capturePushNotificationOpened(response: response)
        }

        /// Without a `UNUserNotificationCenter` delegate the system never reports a tap to anyone, so
        /// there is nothing to swizzle and no open is ever captured — the integration installs cleanly
        /// and then stays silent forever, which is near-impossible to diagnose from the outside.
        ///
        /// The check is delayed because an app may install its delegate after setup(), which the
        /// swizzled setter handles; only a delegate still missing well after launch is a real problem.
        private func warnIfNoNotificationDelegate(while token: RegistrationToken?) {
            // An app extension is never the notification-center delegate, so the advice below would be
            // wrong there.
            guard Bundle.main.bundleURL.pathExtension == "app" else { return }

            DispatchQueue.main.asyncAfter(deadline: .now() + Self.missingDelegateGracePeriod) { [weak token] in
                // A weak token reads "still subscribed" without racing `stop()` on another thread.
                guard token != nil, UNUserNotificationCenter.current().delegate == nil else { return }
                hedgeLog("""
                Push notification opened integration: no UNUserNotificationCenter delegate is set, so \
                notification taps are never reported to the app and `$push_notification_opened` cannot \
                be captured. Set `UNUserNotificationCenter.current().delegate` in your application \
                delegate, or capture opens yourself with \
                `PostHogSDK.shared.capturePushNotificationOpened(response:)`.
                """)
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
