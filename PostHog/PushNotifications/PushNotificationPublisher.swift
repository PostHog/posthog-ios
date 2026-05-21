#if os(iOS) || os(macOS)
    import Foundation
    import UserNotifications

    #if os(iOS)
        import UIKit
    #elseif os(macOS)
        import AppKit
    #endif

    // MARK: - Protocol

    protocol PushNotificationPublishing: AnyObject {
        /// Fires when the user opens a push notification (taps it or it launches the app).
        var onNotificationResponse: PostHogMulticastCallback<UNNotificationResponse> { get }
        /// Fires when APNS delivers a device token.
        var onDeviceToken: PostHogMulticastCallback<String> { get }
    }

    // MARK: - Publisher

    /// Owns all push-notification swizzling and publishes events to subscribers.
    ///
    /// Swizzles are installed automatically when the first subscriber attaches and removed
    /// when the last subscriber detaches, driven by `PostHogMulticastCallback.onSubscriberCountChanged`.
    final class PushNotificationPublisher: PushNotificationPublishing {
        static let shared = PushNotificationPublisher()

        let onNotificationResponse: PostHogMulticastCallback<UNNotificationResponse>
        let onDeviceToken: PostHogMulticastCallback<String>

        private var swizzledAppDelegateClass: AnyClass?
        private var swizzledDelegateClasses = Set<ObjectIdentifier>()

        private init() {
            // Use weak references via a box to avoid capturing self before init completes.
            weak var weakSelf: PushNotificationPublisher?
            onNotificationResponse = PostHogMulticastCallback(onSubscriberCountChanged: { count in
                guard let self = weakSelf else { return }
                if count == 1 {
                    self.swizzleNotificationCenterDelegateSetter()
                    if let existing = UNUserNotificationCenter.current().delegate {
                        self.swizzleNotificationDelegateMethods(on: type(of: existing))
                    }
                } else if count == 0 {
                    self.unswizzleNotificationCenterDelegateSetter()
                }
            })
            onDeviceToken = PostHogMulticastCallback(onSubscriberCountChanged: { count in
                guard let self = weakSelf else { return }
                if count == 1 {
                    self.swizzleAppDelegateMethods()
                } else if count == 0 {
                    self.unswizzleAppDelegateMethods()
                }
            })
            // Now self is fully initialized — wire up the weak reference.
            weakSelf = self
        }

        // MARK: - Notification Center Delegate Swizzling

        private static let delegateSetterOriginal = #selector(setter: UNUserNotificationCenter.delegate)
        private static let delegateSetterSwizzled = #selector(UNUserNotificationCenter.ph_swizzled_setDelegate(_:))

        private func swizzleNotificationCenterDelegateSetter() {
            swizzle(forClass: UNUserNotificationCenter.self, original: Self.delegateSetterOriginal, new: Self.delegateSetterSwizzled)
        }

        private func unswizzleNotificationCenterDelegateSetter() {
            swizzle(forClass: UNUserNotificationCenter.self, original: Self.delegateSetterOriginal, new: Self.delegateSetterSwizzled)
            swizzledDelegateClasses.removeAll()
        }

        func swizzleNotificationDelegateMethods(on delegateClass: AnyClass) {
            let classId = ObjectIdentifier(delegateClass)
            guard !swizzledDelegateClasses.contains(classId) else { return }
            swizzledDelegateClasses.insert(classId)
            swizzleAddingIfNeeded(
                on: delegateClass,
                original: #selector(UNUserNotificationCenterDelegate.userNotificationCenter(_:didReceive:withCompletionHandler:)),
                swizzled: #selector(NSObject.ph_swizzled_userNotificationCenter(_:didReceive:withCompletionHandler:))
            )
        }

        // MARK: - App Delegate Swizzling

        private func swizzleAppDelegateMethods() {
            #if os(iOS)
                guard let appDelegate = UIApplication.shared.delegate,
                      let appDelegateClass = object_getClass(appDelegate)
                else {
                    hedgeLog("Push notification publisher: no app delegate found to swizzle")
                    return
                }
            #elseif os(macOS)
                guard let appDelegate = NSApplication.shared.delegate,
                      let appDelegateClass = object_getClass(appDelegate)
                else {
                    hedgeLog("Push notification publisher: no app delegate found to swizzle")
                    return
                }
            #endif

            swizzledAppDelegateClass = appDelegateClass
            swizzleAddingIfNeeded(on: appDelegateClass, original: Self.didRegisterSelector, swizzled: Self.swizzledDidRegisterSelector)
            swizzleAddingIfNeeded(on: appDelegateClass, original: Self.didFailSelector, swizzled: Self.swizzledDidFailSelector)
        }

        private func unswizzleAppDelegateMethods() {
            guard let appDelegateClass = swizzledAppDelegateClass else { return }
            // Calling swizzle() reverses the exchange. Methods added by swizzleAddingIfNeeded are not
            // removed from the class — their IMPs are swapped back but the methods remain. Known limitation.
            swizzle(forClass: appDelegateClass, original: Self.didRegisterSelector, new: Self.swizzledDidRegisterSelector)
            swizzle(forClass: appDelegateClass, original: Self.didFailSelector, new: Self.swizzledDidFailSelector)
            swizzledAppDelegateClass = nil
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

    // MARK: - UNUserNotificationCenter Swizzled Setter

    extension UNUserNotificationCenter {
        @objc func ph_swizzled_setDelegate(_ delegate: UNUserNotificationCenterDelegate?) {
            if let delegate, let publisher = DI.main.pushNotificationPublisher as? PushNotificationPublisher {
                publisher.swizzleNotificationDelegateMethods(on: type(of: delegate))
            }
            ph_swizzled_setDelegate(delegate)
        }
    }

    // MARK: - NSObject Swizzled Methods

    extension NSObject {
        @objc func ph_swizzled_userNotificationCenter(
            _ center: UNUserNotificationCenter,
            didReceive response: UNNotificationResponse,
            withCompletionHandler completionHandler: @escaping () -> Void
        ) {
            DI.main.pushNotificationPublisher.onNotificationResponse.invoke(response)
            ph_swizzled_userNotificationCenter(center, didReceive: response, withCompletionHandler: completionHandler)
        }

        #if os(iOS)
            @objc func ph_swizzled_application(
                _ application: UIApplication,
                didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
            ) {
                let tokenString = deviceToken.map { String(format: "%02x", $0) }.joined()
                DI.main.pushNotificationPublisher.onDeviceToken.invoke(tokenString)
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
                let tokenString = deviceToken.map { String(format: "%02x", $0) }.joined()
                DI.main.pushNotificationPublisher.onDeviceToken.invoke(tokenString)
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
        extension PushNotificationPublisher {
            static func reset() {
                shared.swizzledAppDelegateClass = nil
                shared.swizzledDelegateClasses.removeAll()
            }
        }
    #endif
#endif
