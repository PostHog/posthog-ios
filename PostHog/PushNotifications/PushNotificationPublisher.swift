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
        /// Installs the notification-delegate swizzles before the SDK is configured, so a response
        /// delivered during launch is held until an integration subscribes. A no-op once a subscriber
        /// exists — setup() has already run, so there is nothing to hold for it.
        func prewarmNotificationResponseCapture()
        /// Publishes a response to subscribers. With no subscriber it is held only while prewarmed,
        /// and otherwise dropped.
        func deliver(notificationResponse: UNNotificationResponse)
        /// Returns and clears a response buffered before any subscriber attached.
        func consumePendingNotificationResponse() -> UNNotificationResponse?
        /// Undoes a prewarm that setup() turned out not to want, so an app that disabled push-open
        /// capture is not left permanently swizzled.
        func discardPrewarmedNotificationResponseCapture()
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

        /// Guards the setter-swizzle install state and the pre-subscriber response buffer.
        private let stateLock = NSLock()
        private var isDelegateSetterSwizzled = false
        private var isPrewarmed = false
        private var pendingResponse: (response: UNNotificationResponse, capturedAt: Date)?

        /// A buffered response stands for the launch that is happening now. Anything older than this
        /// belongs to a launch the app never configured the SDK for, and would be reported with a
        /// misleading timestamp.
        private static let pendingResponseTTL: TimeInterval = 30

        private init() {
            // weakSelf avoids capturing self in the subscriber-count closures before init completes.
            weak var weakSelf: PushNotificationPublisher?
            onNotificationResponse = PostHogMulticastCallback(onSubscriberCountChanged: { count in
                guard let self = weakSelf else { return }
                if count == 1 {
                    // The prewarm window ends at the first subscriber: from here the publisher tears
                    // down normally on the way out, and a response arriving with no subscriber is
                    // dropped rather than buffered for a later setup().
                    self.stateLock.withLock { self.isPrewarmed = false }
                    self.installNotificationDelegateSwizzles()
                } else if count == 0 {
                    self.uninstallNotificationDelegateSwizzles()
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

        /// Installs the setter swizzle and covers a delegate that is already set.
        ///
        /// `isDelegateSetterSwizzled` is what makes this idempotent, and it is load-bearing: the
        /// swizzle is a method exchange, so an unguarded second call would reverse the first.
        private func installNotificationDelegateSwizzles() {
            // Reachable from public API, so it can run outside an app.
            guard Self.isRunningInAppContext else { return }

            let shouldInstall = stateLock.withLock {
                guard !isDelegateSetterSwizzled else { return false }
                isDelegateSetterSwizzled = true
                return true
            }
            guard shouldInstall else { return }

            swizzle(forClass: UNUserNotificationCenter.self, original: Self.delegateSetterOriginal, new: Self.delegateSetterSwizzled)
            if let existing = UNUserNotificationCenter.current().delegate {
                swizzleNotificationDelegateMethods(on: type(of: existing))
            }
        }

        private func uninstallNotificationDelegateSwizzles() {
            let shouldUninstall = stateLock.withLock {
                guard isDelegateSetterSwizzled else { return false }
                isDelegateSetterSwizzled = false
                return true
            }
            guard shouldUninstall else { return }

            // Calling swizzle() again reverses the setter exchange. `swizzledDelegateClasses` is
            // deliberately NOT cleared: the per-class `didReceive` replacements stay in place for the
            // process lifetime (invoking an empty multicast is a no-op), and clearing the set would wrap
            // an already-replaced method on re-install.
            swizzle(forClass: UNUserNotificationCenter.self, original: Self.delegateSetterOriginal, new: Self.delegateSetterSwizzled)
        }

        func prewarmNotificationResponseCapture() {
            // A live subscriber means setup() already ran, so there is nothing to hold for it.
            // Read outside `stateLock` — `subscriberCount` takes the multicast's own lock. A prewarm
            // racing the very first subscribe can still set the flag; the TTL bounds that.
            guard onNotificationResponse.subscriberCount == 0 else { return }

            let alreadyPrewarmed = stateLock.withLock {
                let wasPrewarmed = isPrewarmed
                isPrewarmed = true
                return wasPrewarmed
            }
            guard !alreadyPrewarmed else { return }
            installNotificationDelegateSwizzles()
        }

        func deliver(notificationResponse response: UNNotificationResponse) {
            if onNotificationResponse.subscriberCount == 0 {
                let buffered = stateLock.withLock { () -> Bool in
                    guard isPrewarmed else { return false }
                    pendingResponse = (response, Date())
                    return true
                }
                if buffered {
                    // A subscriber that arrived while this ran already drained an empty buffer, so
                    // hand the response over here instead of stranding it. `consume` clears under
                    // the lock, so it cannot be delivered twice.
                    if onNotificationResponse.subscriberCount > 0,
                       let pending = consumePendingNotificationResponse()
                    {
                        onNotificationResponse.invoke(pending)
                    }
                    return
                }
                // The count read above can already be stale, and invoking an empty multicast is a
                // no-op, so falling through cannot drop a response that a subscriber arriving
                // mid-call should have seen.
            }
            onNotificationResponse.invoke(response)
        }

        func consumePendingNotificationResponse() -> UNNotificationResponse? {
            stateLock.withLock {
                guard let pending = pendingResponse else { return nil }
                pendingResponse = nil
                guard Date().timeIntervalSince(pending.capturedAt) <= Self.pendingResponseTTL else {
                    return nil
                }
                return pending.response
            }
        }

        func discardPrewarmedNotificationResponseCapture() {
            stateLock.withLock {
                pendingResponse = nil
                isPrewarmed = false
            }
            // A live subscriber means another PostHogSDK instance still needs these swizzles.
            guard onNotificationResponse.subscriberCount == 0 else { return }
            uninstallNotificationDelegateSwizzles()
        }

        /// `UNUserNotificationCenter` needs a real app bundle; it traps in test runners and CLI tools.
        private static var isRunningInAppContext: Bool {
            let bundleExtension = Bundle.main.bundleURL.pathExtension
            return bundleExtension == "app" || bundleExtension == "appex"
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
                    DI.main.pushNotificationPublisher.deliver(notificationResponse: response)
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

            swizzleAppDelegateMethods(on: appDelegateClass)
        }

        func swizzleAppDelegateMethods(on appDelegateClass: AnyClass) {
            swizzledAppDelegateClass = appDelegateClass
            #if os(iOS)
                swizzleAddingIfNeeded(
                    on: appDelegateClass,
                    original: Self.didRegisterSelector,
                    swizzled: Self.swizzledDidRegisterSelector,
                    noop: Self.forwardedDidRegisterSelector
                )
                swizzleAddingIfNeeded(
                    on: appDelegateClass,
                    original: Self.didFailSelector,
                    swizzled: Self.swizzledDidFailSelector,
                    noop: Self.forwardedDidFailSelector
                )
            #elseif os(macOS)
                swizzleAddingIfNeeded(on: appDelegateClass, original: Self.didRegisterSelector, swizzled: Self.swizzledDidRegisterSelector)
                swizzleAddingIfNeeded(on: appDelegateClass, original: Self.didFailSelector, swizzled: Self.swizzledDidFailSelector)
            #endif
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
            private static let forwardedDidRegisterSelector = #selector(
                NSObject.ph_forwarded_application(_:didRegisterForRemoteNotificationsWithDeviceToken:)
            )
            private static let didFailSelector = #selector(
                UIApplicationDelegate.application(_:didFailToRegisterForRemoteNotificationsWithError:)
            )
            private static let swizzledDidFailSelector = #selector(
                NSObject.ph_swizzled_application(_:didFailToRegisterForRemoteNotificationsWithError:)
            )
            private static let forwardedDidFailSelector = #selector(
                NSObject.ph_forwarded_application(_:didFailToRegisterForRemoteNotificationsWithError:)
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

            @objc func ph_forwarded_application(
                _ application: UIApplication,
                didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
            ) {
                let selector = #selector(UIApplicationDelegate.application(_:didRegisterForRemoteNotificationsWithDeviceToken:))
                let target = forwardingTarget(for: selector) as? UIApplicationDelegate
                target?.application?(application, didRegisterForRemoteNotificationsWithDeviceToken: deviceToken)
            }

            @objc func ph_forwarded_application(
                _ application: UIApplication,
                didFailToRegisterForRemoteNotificationsWithError error: Error
            ) {
                let selector = #selector(UIApplicationDelegate.application(_:didFailToRegisterForRemoteNotificationsWithError:))
                let target = forwardingTarget(for: selector) as? UIApplicationDelegate
                target?.application?(application, didFailToRegisterForRemoteNotificationsWithError: error)
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
                let wasSwizzled = shared.stateLock.withLock {
                    let wasSwizzled = shared.isDelegateSetterSwizzled
                    shared.isDelegateSetterSwizzled = false
                    shared.isPrewarmed = false
                    shared.pendingResponse = nil
                    return wasSwizzled
                }
                // Clearing the flag without reversing the exchange would leave the next install
                // un-swizzling a setter it never swizzled.
                if wasSwizzled {
                    swizzle(forClass: UNUserNotificationCenter.self, original: delegateSetterOriginal, new: delegateSetterSwizzled)
                }
            }
        }
    #endif
#endif
