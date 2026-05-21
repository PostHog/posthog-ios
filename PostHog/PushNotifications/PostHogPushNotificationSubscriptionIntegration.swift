#if os(iOS) || os(macOS)
    import Foundation
    import UserNotifications

    #if os(iOS)
        import UIKit
    #elseif os(macOS)
        import AppKit
    #endif

    // MARK: - Subscription Integration (app delegate token swizzling)

    /// Swizzles `application(_:didRegisterForRemoteNotificationsWithDeviceToken:)` on the
    /// app delegate to automatically forward APNS tokens to PostHog.
    ///
    /// The app delegate selector is an optional protocol requirement and may not exist on
    /// the concrete delegate class, so `swizzleAddingIfNeeded` is used to inject it first
    /// before exchanging implementations.
    @available(iOS 14.0, macOS 11.0, *)
    final class PostHogPushNotificationSubscriptionIntegration: PostHogIntegration {
        var requiresSwizzling: Bool { true }

        private static var integrationInstalledLock = NSLock()
        private static var integrationInstalled = false
        private static var swizzledAppDelegateClass: AnyClass?

        // Weak reference to the live instance so static swizzled methods can route
        // through it instead of coupling to PostHogSDK.shared.
        private static weak var current: PostHogPushNotificationSubscriptionIntegration?
        private static var currentLock = NSLock()

        private weak var postHog: PostHogSDK?

        func install(_ postHog: PostHogSDK) -> PostHogIntegrationInstallResult {
            let didInstall = Self.integrationInstalledLock.withLock {
                if Self.integrationInstalled { return false }
                Self.integrationInstalled = true
                return true
            }
            guard didInstall else { return .skipped(.alreadyInstalled) }
            self.postHog = postHog
            Self.currentLock.withLock { Self.current = self }
            start()
            return .installed
        }

        func uninstall(_ postHog: PostHogSDK) {
            guard self.postHog === postHog || self.postHog == nil else { return }
            stop()
            self.postHog = nil
            Self.currentLock.withLock { Self.current = nil }
            Self.integrationInstalledLock.withLock {
                Self.integrationInstalled = false
            }
        }

        func start() {
            let bundleExtension = Bundle.main.bundleURL.pathExtension
            guard bundleExtension == "app" || bundleExtension == "appex" else {
                hedgeLog("Push subscription integration: skipping setup - not running in an app context")
                return
            }
            swizzleAppDelegateMethods()
        }

        func stop() {
            unswizzleAppDelegateMethods()
        }

        private func swizzleAppDelegateMethods() {
            #if os(iOS)
                guard let appDelegate = UIApplication.shared.delegate,
                      let appDelegateClass = object_getClass(appDelegate)
                else {
                    hedgeLog("Push subscription integration: no app delegate found to swizzle")
                    return
                }
            #elseif os(macOS)
                guard let appDelegate = NSApplication.shared.delegate,
                      let appDelegateClass = object_getClass(appDelegate)
                else {
                    hedgeLog("Push subscription integration: no app delegate found to swizzle")
                    return
                }
            #endif

            Self.swizzledAppDelegateClass = appDelegateClass
            // Use swizzleAddingIfNeeded: app delegate token methods are optional protocol
            // requirements and may not be present on the concrete delegate class.
            swizzleAddingIfNeeded(on: appDelegateClass, original: Self.didRegisterSelector, swizzled: Self.swizzledDidRegisterSelector)
            swizzleAddingIfNeeded(on: appDelegateClass, original: Self.didFailSelector, swizzled: Self.swizzledDidFailSelector)
        }

        private func unswizzleAppDelegateMethods() {
            guard let appDelegateClass = Self.swizzledAppDelegateClass else { return }
            // Calling swizzle() reverses the exchange. If swizzleAddingIfNeeded *added* the
            // method (it did not originally exist), this swaps the IMPs back but does not
            // remove the added methods from the class — that is a known limitation.
            swizzle(forClass: appDelegateClass, original: Self.didRegisterSelector, new: Self.swizzledDidRegisterSelector)
            swizzle(forClass: appDelegateClass, original: Self.didFailSelector, new: Self.swizzledDidFailSelector)
            Self.swizzledAppDelegateClass = nil
        }

        fileprivate static func handleDeviceToken(_ deviceToken: Data) {
            let tokenString = deviceToken.map { String(format: "%02x", $0) }.joined()
            currentLock.withLock { current }?.postHog?.handlePushNotificationDeviceToken(tokenString)
        }

        #if os(iOS)
            private static let didRegisterSelector = #selector(
                UIApplicationDelegate.application(_:didRegisterForRemoteNotificationsWithDeviceToken:)
            )
            private static let swizzledDidRegisterSelector = #selector(
                NSObject.ph_swizzled_application(_:didRegisterForRemoteNotificationsWithDeviceToken:)
            )
            private static let didFailSelector = #selector(
                UIApplicationDelegate.application(_:didFailToRegisterForRemoteNotificationsWithError:)
            )
            private static let swizzledDidFailSelector = #selector(
                NSObject.ph_swizzled_application(_:didFailToRegisterForRemoteNotificationsWithError:)
            )
        #elseif os(macOS)
            private static let didRegisterSelector = #selector(
                NSApplicationDelegate.application(_:didRegisterForRemoteNotificationsWithDeviceToken:)
            )
            private static let swizzledDidRegisterSelector = #selector(
                NSObject.ph_swizzled_application(_:didRegisterForRemoteNotificationsWithDeviceToken:)
            )
            private static let didFailSelector = #selector(
                NSApplicationDelegate.application(_:didFailToRegisterForRemoteNotificationsWithError:)
            )
            private static let swizzledDidFailSelector = #selector(
                NSObject.ph_swizzled_application(_:didFailToRegisterForRemoteNotificationsWithError:)
            )
        #endif
    }

    // MARK: - NSObject Swizzled Token Methods

    @available(iOS 14.0, macOS 11.0, *)
    extension NSObject {
        #if os(iOS)
            @objc func ph_swizzled_application(
                _ application: UIApplication,
                didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
            ) {
                PostHogPushNotificationSubscriptionIntegration.handleDeviceToken(deviceToken)
                ph_swizzled_application(application, didRegisterForRemoteNotificationsWithDeviceToken: deviceToken)
            }

            @objc func ph_swizzled_application(
                _ application: UIApplication,
                didFailToRegisterForRemoteNotificationsWithError error: Error
            ) {
                hedgeLog("Failed to register for remote notifications: \(error.localizedDescription)")
                ph_swizzled_application(application, didFailToRegisterForRemoteNotificationsWithError: error)
            }
        #elseif os(macOS)
            @objc func ph_swizzled_application(
                _ application: NSApplication,
                didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
            ) {
                PostHogPushNotificationSubscriptionIntegration.handleDeviceToken(deviceToken)
                ph_swizzled_application(application, didRegisterForRemoteNotificationsWithDeviceToken: deviceToken)
            }

            @objc func ph_swizzled_application(
                _ application: NSApplication,
                didFailToRegisterForRemoteNotificationsWithError error: Error
            ) {
                hedgeLog("Failed to register for remote notifications: \(error.localizedDescription)")
                ph_swizzled_application(application, didFailToRegisterForRemoteNotificationsWithError: error)
            }
        #endif
    }

    #if TESTING
        @available(iOS 14.0, macOS 11.0, *)
        extension PostHogPushNotificationSubscriptionIntegration {
            static func clearInstalls() {
                integrationInstalledLock.withLock {
                    integrationInstalled = false
                }
                currentLock.withLock { current = nil }
                swizzledAppDelegateClass = nil
            }
        }
    #endif
#endif
