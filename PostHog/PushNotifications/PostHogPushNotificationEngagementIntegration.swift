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

        // Track which delegate classes we've already swizzled to avoid double-swizzling
        private static var swizzledDelegateClasses = Set<ObjectIdentifier>()
        private static var swizzledDelegateClassesLock = NSLock()

        // Keep a reference to the original delegate setter IMP so we can restore it
        private static var originalDelegateSetterIMP: IMP?

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
            swizzleDelegateSetter()
            // If a delegate is already set before we installed, swizzle it now
            if let existingDelegate = UNUserNotificationCenter.current().delegate {
                Self.swizzleDelegateMethods(on: type(of: existingDelegate))
            }
        }

        func stop() {
            // Unswizzle the delegate setter
            unswizzleDelegateSetter()
        }

        // MARK: - Delegate Setter Swizzling

        /// Swizzle the `delegate` property setter on UNUserNotificationCenter
        /// so we can intercept whenever any code sets a new delegate.
        private func swizzleDelegateSetter() {
            let originalSelector = #selector(setter: UNUserNotificationCenter.delegate)
            let swizzledSelector = #selector(UNUserNotificationCenter.ph_swizzled_setDelegate(_:))

            guard let originalMethod = class_getInstanceMethod(UNUserNotificationCenter.self, originalSelector) else {
                hedgeLog("Failed to swizzle UNUserNotificationCenter.delegate setter: original method not found")
                return
            }

            Self.originalDelegateSetterIMP = method_getImplementation(originalMethod)

            guard let swizzledMethod = class_getInstanceMethod(UNUserNotificationCenter.self, swizzledSelector) else {
                hedgeLog("Failed to swizzle UNUserNotificationCenter.delegate setter: swizzled method not found")
                return
            }

            method_exchangeImplementations(originalMethod, swizzledMethod)
        }

        private func unswizzleDelegateSetter() {
            // Re-exchange to restore the original
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

        // MARK: - Delegate Method Swizzling

        /// Swizzle `userNotificationCenter(_:didReceive:withCompletionHandler:)` on the delegate class
        fileprivate static func swizzleDelegateMethods(on delegateClass: AnyClass) {
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

            // If the delegate class doesn't implement the method, add it directly
            guard let swizzledMethod = class_getInstanceMethod(NSObject.self, swizzledSelector) else {
                hedgeLog("Push notification engagement: swizzled method not found")
                return
            }

            if let originalMethod = class_getInstanceMethod(delegateClass, originalSelector) {
                // The class already implements the method — exchange implementations
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
            // Access the shared instance — the integration holds a weak reference
            // but we need a reliable way to get it during the swizzled method call
            PostHogSDK.shared
        }
    }

    // MARK: - UNUserNotificationCenter Swizzled Methods

    @available(iOS 14.0, macOS 11.0, *)
    extension UNUserNotificationCenter {
        @objc func ph_swizzled_setDelegate(_ delegate: UNUserNotificationCenterDelegate?) {
            if let delegate {
                PostHogPushNotificationEngagementIntegration.swizzleDelegateMethods(on: type(of: delegate))
            }
            // Call the original implementation (which is now at the swizzled selector)
            ph_swizzled_setDelegate(delegate)
        }
    }

    // MARK: - NSObject Swizzled Methods for Notification Delegate

    @available(iOS 14.0, macOS 11.0, *)
    extension NSObject {
        @objc func ph_swizzled_userNotificationCenter(
            _ center: UNUserNotificationCenter,
            didReceive response: UNNotificationResponse,
            withCompletionHandler completionHandler: @escaping () -> Void
        ) {
            PostHogPushNotificationEngagementIntegration.captureNotificationEngagement(response: response)

            // Call the original implementation
            ph_swizzled_userNotificationCenter(center, didReceive: response, withCompletionHandler: completionHandler)
        }
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
            }
        }
    #endif
#endif
