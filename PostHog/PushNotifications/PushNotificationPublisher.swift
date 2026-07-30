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
        /// Fires when APNs delivers a device token (already converted to a lowercase-hex string).
        var onDeviceToken: PostHogMulticastCallback<String> { get }
    }

    // MARK: - Publisher

    /// Owns all push-notification swizzling and publishes events to subscribers.
    ///
    /// Swizzles are installed when the first subscriber attaches and removed when the last one detaches,
    /// driven by `PostHogMulticastCallback.onSubscriberCountChanged` — matching `ApplicationEventPublisher`.
    final class PushNotificationPublisher: PushNotificationPublishing {
        static let shared = PushNotificationPublisher()

        let onNotificationResponse: PostHogMulticastCallback<UNNotificationResponse>
        let onDeviceToken: PostHogMulticastCallback<String>

        private var swizzledAppDelegateClass: AnyClass?
        /// Guards `swizzledDelegateClasses` — mutated from the subscriber-count callback and from the
        /// swizzled `UNUserNotificationCenter.delegate` setter, which can run on any thread.
        private let delegateClassesLock = NSLock()
        private var swizzledDelegateClasses = Set<ObjectIdentifier>()

        private init() {
            // weakSelf avoids capturing self in the subscriber-count closures before init completes.
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
            weakSelf = self
        }

        // MARK: - Notification Center Delegate Swizzling

        private static let delegateSetterOriginal = #selector(setter: UNUserNotificationCenter.delegate)
        private static let delegateSetterSwizzled = #selector(UNUserNotificationCenter.ph_swizzled_setDelegate(_:))

        private func swizzleNotificationCenterDelegateSetter() {
            swizzle(forClass: UNUserNotificationCenter.self, original: Self.delegateSetterOriginal, new: Self.delegateSetterSwizzled)
        }

        private func unswizzleNotificationCenterDelegateSetter() {
            // Calling swizzle() again reverses the exchange. `swizzledDelegateClasses` is deliberately
            // NOT cleared: the per-class `didReceive` swaps stay in place for the process lifetime
            // (invoking an empty multicast is a no-op), and clearing the set would make a re-install
            // exchange the implementations a second time — swapping our handler back OUT.
            swizzle(forClass: UNUserNotificationCenter.self, original: Self.delegateSetterOriginal, new: Self.delegateSetterSwizzled)
        }

        func swizzleNotificationDelegateMethods(on delegateClass: AnyClass) {
            let classId = ObjectIdentifier(delegateClass)
            let alreadySwizzled = delegateClassesLock.withLock {
                !swizzledDelegateClasses.insert(classId).inserted
            }
            if alreadySwizzled {
                return
            }
            swizzleAddingIfNeeded(
                on: delegateClass,
                original: #selector(UNUserNotificationCenterDelegate.userNotificationCenter(_:didReceive:withCompletionHandler:)),
                swizzled: #selector(NSObject.ph_swizzled_userNotificationCenter(_:didReceive:withCompletionHandler:)),
                noop: #selector(NSObject.ph_noop_userNotificationCenter(_:didReceive:withCompletionHandler:))
            )
        }

        // MARK: - App Delegate Swizzling

        private func swizzleAppDelegateMethods() {
            // UIApplication.shared / NSApplication.shared are main-thread-only, and setup() may run
            // off-main. Both install and uninstall hop to main so they also stay ordered.
            guard Thread.isMainThread else {
                DispatchQueue.main.async { self.swizzleAppDelegateMethods() }
                return
            }

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
            guard Thread.isMainThread else {
                DispatchQueue.main.async { self.unswizzleAppDelegateMethods() }
                return
            }

            guard let appDelegateClass = swizzledAppDelegateClass else { return }
            // Reverses the exchange. Methods added by swizzleAddingIfNeeded stay on the class — their
            // IMPs are swapped back but the method entries remain. Known, harmless limitation.
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

        /// Call-through target when the host delegate never implemented `didReceive`: the system still
        /// expects its completion handler to be invoked.
        @objc func ph_noop_userNotificationCenter(
            _: UNUserNotificationCenter,
            didReceive _: UNNotificationResponse,
            withCompletionHandler completionHandler: @escaping () -> Void
        ) {
            completionHandler()
        }

        #if os(iOS)
            @objc func ph_swizzled_application(
                _ application: UIApplication,
                didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
            ) {
                DI.main.pushNotificationPublisher.onDeviceToken.invoke(deviceToken.hexEncodedString())
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
                DI.main.pushNotificationPublisher.onDeviceToken.invoke(deviceToken.hexEncodedString())
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

    private extension Data {
        /// APNs tokens are transmitted as a lowercase-hex string.
        func hexEncodedString() -> String {
            map { String(format: "%02x", $0) }.joined()
        }
    }

    #if TESTING
        extension PushNotificationPublisher {
            /// Test isolation only — safe because the bundle guard in the integrations means no
            /// swizzle is ever actually installed under a test runner.
            static func reset() {
                shared.swizzledAppDelegateClass = nil
                shared.delegateClassesLock.withLock {
                    shared.swizzledDelegateClasses.removeAll()
                }
            }
        }
    #endif
#endif
