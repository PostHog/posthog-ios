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

    private final class OriginalDelegateIMP {
        let lock = NSLock()
        var value: IMP?

        init(_ value: IMP?) {
            self.value = value
        }
    }

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
        private static let didReceiveResponseSelector = #selector(
            UNUserNotificationCenterDelegate.userNotificationCenter(_:didReceive:withCompletionHandler:)
        )

        private func swizzleNotificationCenterDelegateSetter() {
            swizzle(forClass: UNUserNotificationCenter.self, original: Self.delegateSetterOriginal, new: Self.delegateSetterSwizzled)
        }

        private func unswizzleNotificationCenterDelegateSetter() {
            // Calling swizzle() again reverses the setter exchange. `swizzledDelegateClasses` is
            // deliberately NOT cleared: the per-class `didReceive` replacements stay in place for the
            // process lifetime (invoking an empty multicast is a no-op), and clearing the set would wrap
            // an already-replaced method on re-install.
            swizzle(forClass: UNUserNotificationCenter.self, original: Self.delegateSetterOriginal, new: Self.delegateSetterSwizzled)
        }

        func swizzleNotificationDelegateMethods(on delegateClass: AnyClass) {
            delegateClassesLock.withLock {
                let classId = ObjectIdentifier(delegateClass)
                guard !swizzledDelegateClasses.contains(classId) else { return }

                let selector = Self.didReceiveResponseSelector
                let originalMethod = class_getInstanceMethod(delegateClass, selector)
                let originalImplementation = originalMethod.map(method_getImplementation)
                let ownsMethod = originalMethod != class_getSuperclass(delegateClass).flatMap {
                    class_getInstanceMethod($0, selector)
                }
                if !ownsMethod {
                    var superclass: AnyClass? = class_getSuperclass(delegateClass)
                    while let current = superclass {
                        if swizzledDelegateClasses.contains(ObjectIdentifier(current)) {
                            swizzledDelegateClasses.insert(classId)
                            return
                        }
                        superclass = class_getSuperclass(current)
                    }
                }

                let typeEncoding: UnsafePointer<CChar>?
                if let originalMethod {
                    typeEncoding = method_getTypeEncoding(originalMethod)
                } else {
                    guard let delegateProtocol = objc_getProtocol("UNUserNotificationCenterDelegate") else {
                        hedgeLog("Push notification publisher: UNUserNotificationCenterDelegate protocol not found")
                        return
                    }
                    typeEncoding = protocol_getMethodDescription(delegateProtocol, selector, false, true).types.map {
                        UnsafePointer<CChar>($0)
                    }
                }
                guard let typeEncoding else {
                    hedgeLog("Push notification publisher: type encoding not found for \(selector)")
                    return
                }

                typealias CompletionHandler = @convention(block) () -> Void
                typealias OriginalImplementation = @convention(c) (
                    AnyObject,
                    Selector,
                    UNUserNotificationCenter,
                    UNNotificationResponse,
                    CompletionHandler
                ) -> Void
                typealias ReplacementBlock = @convention(block) (
                    AnyObject,
                    UNUserNotificationCenter,
                    UNNotificationResponse,
                    CompletionHandler
                ) -> Void

                let implementationHolder = OriginalDelegateIMP(originalImplementation)
                let replacement: ReplacementBlock = { delegate, center, response, completionHandler in
                    DI.main.pushNotificationPublisher.onNotificationResponse.invoke(response)
                    guard let originalImplementation = implementationHolder.lock.withLock({ implementationHolder.value }) else {
                        completionHandler()
                        return
                    }
                    // Call the captured IMP with its original selector. Aliasing it under a synthetic
                    // selector breaks call-through for some Objective-C delegates (see #748).
                    let callOriginal = unsafeBitCast(originalImplementation, to: OriginalImplementation.self)
                    callOriginal(delegate, selector, center, response, completionHandler)
                }
                let replacementImplementation = imp_implementationWithBlock(replacement)

                // Keep replacement invocations from observing the pre-replacement fallback while the
                // runtime atomically returns a newer direct implementation installed by another swizzler.
                implementationHolder.lock.lock()
                let replacedImplementation = class_replaceMethod(delegateClass, selector, replacementImplementation, typeEncoding)
                implementationHolder.value = replacedImplementation ?? originalImplementation
                implementationHolder.lock.unlock()
                swizzledDelegateClasses.insert(classId)
            }
        }

        // MARK: - App Delegate Swizzling

        private func swizzleAppDelegateMethods() {
            // UIApplication.shared / NSApplication.shared are main-thread-only, and setup() may run
            // off-main. Always hop (never call synchronously even if already on main) so install and
            // uninstall land on the main queue in the same order they were requested — an on-main
            // close() can otherwise unswizzle synchronously ahead of an off-main setup()'s already
            // -enqueued deferred swizzle, leaving the delegate swizzled with subscriber count 0.
            DispatchQueue.main.async { [weak self] in
                self?.performSwizzleAppDelegateMethods()
            }
        }

        private func performSwizzleAppDelegateMethods() {
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
            DispatchQueue.main.async { [weak self] in
                self?.performUnswizzleAppDelegateMethods()
            }
        }

        private func performUnswizzleAppDelegateMethods() {
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
            /// Test isolation only. Production delegate swizzles are skipped by the integrations'
            /// bundle guard; swizzling tests use process-unique Objective-C fixture classes.
            static func reset() {
                shared.swizzledAppDelegateClass = nil
                shared.delegateClassesLock.withLock {
                    shared.swizzledDelegateClasses.removeAll()
                }
            }
        }
    #endif
#endif
