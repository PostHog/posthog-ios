//
//  PostHogPushNotificationEngagementIntegration.swift
//  PostHog
//
//  Created on 02/04/2026.
//

#if os(iOS) || os(macOS)
    import Foundation
    import UserNotifications

    #if os(iOS)
        import UIKit
    #elseif os(macOS)
        import AppKit
    #endif

    @available(iOS 14.0, macOS 11.0, *)
    final class PostHogPushNotificationEngagementIntegration: PostHogIntegration {
        var requiresSwizzling: Bool { true }

        private static var integrationInstalledLock = NSLock()
        private static var integrationInstalled = false

        private weak var postHog: PostHogSDK?

        // Track which notification delegate classes we've already swizzled to avoid double-swizzling
        private static var swizzledDelegateClasses = Set<ObjectIdentifier>()
        private static var swizzledDelegateClassesLock = NSLock()

        // Track the app delegate class we swizzled so we can restore it
        private static var swizzledAppDelegateClass: AnyClass?

        func install(_ postHog: PostHogSDK) throws {
            try Self.integrationInstalledLock.withLock {
                if Self.integrationInstalled {
                    throw InternalPostHogError(description: "Push notification engagement integration already installed to another PostHogSDK instance.")
                }
                Self.integrationInstalled = true
            }

            self.postHog = postHog

            start()
        }

        func uninstall(_ postHog: PostHogSDK) {
            if self.postHog === postHog || self.postHog == nil {
                stop()
                self.postHog = nil
                Self.integrationInstalledLock.withLock {
                    Self.integrationInstalled = false
                }
            }
        }

        func start() {
            swizzleNotificationCenterDelegateSetter()
            swizzleAppDelegateMethods()
            // If a notification delegate is already set before we installed, swizzle it now
            if let existingDelegate = UNUserNotificationCenter.current().delegate {
                Self.swizzleNotificationDelegateMethods(on: type(of: existingDelegate))
            }
        }

        func stop() {
            unswizzleNotificationCenterDelegateSetter()
            unswizzleAppDelegateMethods()
        }

        // MARK: - UNUserNotificationCenter Delegate Setter Swizzling

        /// Swizzle the `delegate` property setter on UNUserNotificationCenter
        /// so we can intercept whenever any code sets a new delegate.
        private func swizzleNotificationCenterDelegateSetter() {
            let originalSelector = #selector(setter: UNUserNotificationCenter.delegate)
            let swizzledSelector = #selector(UNUserNotificationCenter.ph_swizzled_setDelegate(_:))

            guard let originalMethod = class_getInstanceMethod(UNUserNotificationCenter.self, originalSelector),
                  let swizzledMethod = class_getInstanceMethod(UNUserNotificationCenter.self, swizzledSelector)
            else {
                hedgeLog("Failed to swizzle UNUserNotificationCenter.delegate setter")
                return
            }

            method_exchangeImplementations(originalMethod, swizzledMethod)
        }

        private func unswizzleNotificationCenterDelegateSetter() {
            let originalSelector = #selector(setter: UNUserNotificationCenter.delegate)
            let swizzledSelector = #selector(UNUserNotificationCenter.ph_swizzled_setDelegate(_:))

            guard let originalMethod = class_getInstanceMethod(UNUserNotificationCenter.self, originalSelector),
                  let swizzledMethod = class_getInstanceMethod(UNUserNotificationCenter.self, swizzledSelector)
            else {
                return
            }

            method_exchangeImplementations(originalMethod, swizzledMethod)

            Self.swizzledDelegateClassesLock.withLock {
                Self.swizzledDelegateClasses.removeAll()
            }
        }

        // MARK: - UNUserNotificationCenterDelegate Method Swizzling

        /// Swizzle `userNotificationCenter(_:didReceive:withCompletionHandler:)` on the notification delegate class
        fileprivate static func swizzleNotificationDelegateMethods(on delegateClass: AnyClass) {
            swizzledDelegateClassesLock.withLock {
                let classId = ObjectIdentifier(delegateClass)
                guard !swizzledDelegateClasses.contains(classId) else { return }
                swizzledDelegateClasses.insert(classId)
            }

            let originalSelector = #selector(
                UNUserNotificationCenterDelegate.userNotificationCenter(_:didReceive:withCompletionHandler:)
            )
            let swizzledSelector = #selector(
                (NSObject).ph_swizzled_userNotificationCenter(_:didReceive:withCompletionHandler:)
            )

            guard let swizzledMethod = class_getInstanceMethod(NSObject.self, swizzledSelector) else {
                hedgeLog("Push notification engagement: swizzled method not found")
                return
            }

            if let originalMethod = class_getInstanceMethod(delegateClass, originalSelector) {
                let didAdd = class_addMethod(
                    delegateClass,
                    swizzledSelector,
                    method_getImplementation(originalMethod),
                    method_getTypeEncoding(originalMethod)
                )
                if didAdd {
                    class_replaceMethod(
                        delegateClass,
                        originalSelector,
                        method_getImplementation(swizzledMethod),
                        method_getTypeEncoding(swizzledMethod)
                    )
                } else {
                    method_exchangeImplementations(originalMethod, swizzledMethod)
                }
            } else {
                // The class doesn't implement the method — add our implementation directly
                class_addMethod(
                    delegateClass,
                    originalSelector,
                    method_getImplementation(swizzledMethod),
                    method_getTypeEncoding(swizzledMethod)
                )
            }
        }

        // MARK: - App Delegate Swizzling

        private func swizzleAppDelegateMethods() {
            #if os(iOS)
                guard let appDelegate = UIApplication.shared.delegate,
                      let appDelegateClass = object_getClass(appDelegate)
                else {
                    hedgeLog("Push notifications: no app delegate found to swizzle")
                    return
                }
            #elseif os(macOS)
                guard let appDelegate = NSApplication.shared.delegate,
                      let appDelegateClass = object_getClass(appDelegate)
                else {
                    hedgeLog("Push notifications: no app delegate found to swizzle")
                    return
                }
            #endif

            Self.swizzledAppDelegateClass = appDelegateClass

            // Swizzle didRegisterForRemoteNotificationsWithDeviceToken
            swizzleMethod(
                on: appDelegateClass,
                original: Self.didRegisterSelector,
                swizzled: Self.swizzledDidRegisterSelector
            )

            // Swizzle didFailToRegisterForRemoteNotificationsWithError
            swizzleMethod(
                on: appDelegateClass,
                original: Self.didFailSelector,
                swizzled: Self.swizzledDidFailSelector
            )
        }

        private func unswizzleAppDelegateMethods() {
            guard let appDelegateClass = Self.swizzledAppDelegateClass else { return }

            if let original = class_getInstanceMethod(appDelegateClass, Self.didRegisterSelector),
               let swizzled = class_getInstanceMethod(appDelegateClass, Self.swizzledDidRegisterSelector)
            {
                method_exchangeImplementations(original, swizzled)
            }

            if let original = class_getInstanceMethod(appDelegateClass, Self.didFailSelector),
               let swizzled = class_getInstanceMethod(appDelegateClass, Self.swizzledDidFailSelector)
            {
                method_exchangeImplementations(original, swizzled)
            }

            Self.swizzledAppDelegateClass = nil
        }

        /// Swizzle a single method on a target class, handling the case where the class
        /// doesn't already implement the method.
        private func swizzleMethod(on targetClass: AnyClass, original: Selector, swizzled: Selector) {
            guard let swizzledMethod = class_getInstanceMethod(NSObject.self, swizzled) else {
                hedgeLog("Push notifications: swizzled method not found for \(swizzled)")
                return
            }

            if let originalMethod = class_getInstanceMethod(targetClass, original) {
                let didAdd = class_addMethod(
                    targetClass,
                    swizzled,
                    method_getImplementation(originalMethod),
                    method_getTypeEncoding(originalMethod)
                )
                if didAdd {
                    class_replaceMethod(
                        targetClass,
                        original,
                        method_getImplementation(swizzledMethod),
                        method_getTypeEncoding(swizzledMethod)
                    )
                } else {
                    method_exchangeImplementations(originalMethod, swizzledMethod)
                }
            } else {
                // Target class doesn't implement the method — add our version directly
                class_addMethod(
                    targetClass,
                    original,
                    method_getImplementation(swizzledMethod),
                    method_getTypeEncoding(swizzledMethod)
                )
            }
        }

        // MARK: - Selectors

        #if os(iOS)
            private static let didRegisterSelector = #selector(
                UIApplicationDelegate.application(_:didRegisterForRemoteNotificationsWithDeviceToken:)
            )
            private static let swizzledDidRegisterSelector = #selector(
                (NSObject).ph_swizzled_application(_:didRegisterForRemoteNotificationsWithDeviceToken:)
            )
            private static let didFailSelector = #selector(
                UIApplicationDelegate.application(_:didFailToRegisterForRemoteNotificationsWithError:)
            )
            private static let swizzledDidFailSelector = #selector(
                (NSObject).ph_swizzled_application(_:didFailToRegisterForRemoteNotificationsWithError:)
            )
        #elseif os(macOS)
            private static let didRegisterSelector = #selector(
                NSApplicationDelegate.application(_:didRegisterForRemoteNotificationsWithDeviceToken:)
            )
            private static let swizzledDidRegisterSelector = #selector(
                (NSObject).ph_swizzled_application(_:didRegisterForRemoteNotificationsWithDeviceToken:)
            )
            private static let didFailSelector = #selector(
                NSApplicationDelegate.application(_:didFailToRegisterForRemoteNotificationsWithError:)
            )
            private static let swizzledDidFailSelector = #selector(
                (NSObject).ph_swizzled_application(_:didFailToRegisterForRemoteNotificationsWithError:)
            )
        #endif

        // MARK: - Event Capture

        fileprivate static func captureNotificationEngagement(response: UNNotificationResponse) {
            guard let postHog = getInstalledPostHog() else { return }

            let content = response.notification.request.content
            let userInfo = content.userInfo

            var properties: [String: Any] = [
                "$notification_title": content.title,
            ]

            if !content.subtitle.isEmpty {
                properties["$notification_subtitle"] = content.subtitle
            }

            if !content.body.isEmpty {
                properties["$notification_body"] = content.body
            }

            // Include PostHog-specific payload fields if present
            if let posthogData = userInfo["posthog"] as? [String: Any] {
                for (key, value) in posthogData {
                    properties["$notification_\(key)"] = value
                }
            }

            let actionIdentifier = response.actionIdentifier
            if actionIdentifier != UNNotificationDefaultActionIdentifier {
                properties["$notification_action"] = actionIdentifier
            }

            postHog.capture("$push_notification_opened", properties: properties)
        }

        private static func getInstalledPostHog() -> PostHogSDK? {
            PostHogSDK.shared
        }
    }

    // MARK: - UNUserNotificationCenter Swizzled Setter

    @available(iOS 14.0, macOS 11.0, *)
    extension UNUserNotificationCenter {
        @objc func ph_swizzled_setDelegate(_ delegate: UNUserNotificationCenterDelegate?) {
            if let delegate {
                PostHogPushNotificationEngagementIntegration.swizzleNotificationDelegateMethods(on: type(of: delegate))
            }
            // Call the original implementation (which is now at the swizzled selector)
            ph_swizzled_setDelegate(delegate)
        }
    }

    // MARK: - NSObject Swizzled Methods

    @available(iOS 14.0, macOS 11.0, *)
    extension NSObject {
        // MARK: UNUserNotificationCenterDelegate

        @objc func ph_swizzled_userNotificationCenter(
            _ center: UNUserNotificationCenter,
            didReceive response: UNNotificationResponse,
            withCompletionHandler completionHandler: @escaping () -> Void
        ) {
            PostHogPushNotificationEngagementIntegration.captureNotificationEngagement(response: response)
            // Call the original implementation
            ph_swizzled_userNotificationCenter(center, didReceive: response, withCompletionHandler: completionHandler)
        }

        // MARK: App Delegate - Device Token

        #if os(iOS)
            @objc func ph_swizzled_application(
                _ application: UIApplication,
                didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
            ) {
                PostHogSDK.shared.handlePushNotificationDeviceToken(deviceToken)
                // Call the original implementation if it existed
                ph_swizzled_application(application, didRegisterForRemoteNotificationsWithDeviceToken: deviceToken)
            }

            @objc func ph_swizzled_application(
                _ application: UIApplication,
                didFailToRegisterForRemoteNotificationsWithError error: Error
            ) {
                hedgeLog("Failed to register for remote notifications: \(error.localizedDescription)")
                // Call the original implementation if it existed
                ph_swizzled_application(application, didFailToRegisterForRemoteNotificationsWithError: error)
            }
        #elseif os(macOS)
            @objc func ph_swizzled_application(
                _ application: NSApplication,
                didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
            ) {
                PostHogSDK.shared.handlePushNotificationDeviceToken(deviceToken)
                // Call the original implementation if it existed
                ph_swizzled_application(application, didRegisterForRemoteNotificationsWithDeviceToken: deviceToken)
            }

            @objc func ph_swizzled_application(
                _ application: NSApplication,
                didFailToRegisterForRemoteNotificationsWithError error: Error
            ) {
                hedgeLog("Failed to register for remote notifications: \(error.localizedDescription)")
                // Call the original implementation if it existed
                ph_swizzled_application(application, didFailToRegisterForRemoteNotificationsWithError: error)
            }
        #endif
    }

    #if TESTING
        @available(iOS 14.0, macOS 11.0, *)
        extension PostHogPushNotificationEngagementIntegration {
            static func clearInstalls() {
                integrationInstalledLock.withLock {
                    integrationInstalled = false
                }
                swizzledDelegateClassesLock.withLock {
                    swizzledDelegateClasses.removeAll()
                }
                swizzledAppDelegateClass = nil
            }
        }
    #endif
#endif
