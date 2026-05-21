#if os(iOS) || os(macOS)
    import Foundation
    import UserNotifications

    #if os(iOS)
        import UIKit
    #elseif os(macOS)
        import AppKit
    #endif

    /// Swizzles `UNUserNotificationCenterDelegate` to automatically capture
    /// `$push_notification_opened` when a user taps a notification.
    ///
    /// `UNUserNotificationCenter.delegate` is a stored property whose setter is always present,
    /// so `swizzle()` (not `swizzleAddingIfNeeded`) is used. The set of already-swizzled
    /// delegate classes is tracked to avoid double-swizzling if the same class is assigned
    /// to the notification center more than once.
    ///
    /// **Cold-start buffering:** If a notification tap launches the app before `PostHog.setup()`
    /// is called, the response is buffered and replayed in `install(_:)`.
    @available(iOS 14.0, macOS 11.0, *)
    final class PostHogPushNotificationOpenIntegration: PostHogIntegration {
        var requiresSwizzling: Bool { true }

        private static var integrationInstalledLock = NSLock()
        private static var integrationInstalled = false

        // Guards both `current` and `pendingResponse` as a single consistent unit:
        // a notification response and the integration that will consume it must be
        // observed/mutated atomically to avoid a TOCTOU gap between the two.
        private static var stateLock = NSLock()
        private static weak var current: PostHogPushNotificationOpenIntegration?
        private static var pendingResponse: UNNotificationResponse?

        private weak var postHog: PostHogSDK?

        // Tracks which delegate classes have already been swizzled so we never
        // double-swizzle if the same class is set as the notification center delegate again.
        private static var swizzledDelegateClasses = Set<ObjectIdentifier>()
        private static var swizzledDelegateClassesLock = NSLock()

        func install(_ postHog: PostHogSDK) -> PostHogIntegrationInstallResult {
            let didInstall = Self.integrationInstalledLock.withLock {
                if Self.integrationInstalled { return false }
                Self.integrationInstalled = true
                return true
            }
            guard didInstall else { return .skipped(.alreadyInstalled) }

            self.postHog = postHog

            // Atomically register as current and drain any buffered cold-start response.
            let pending = Self.stateLock.withLock {
                Self.current = self
                defer { Self.pendingResponse = nil }
                return Self.pendingResponse
            }
            if let pending {
                postHog.capturePushNotificationOpened(response: pending)
            }

            start()
            return .installed
        }

        func uninstall(_ postHog: PostHogSDK) {
            guard self.postHog === postHog || self.postHog == nil else { return }
            stop()
            self.postHog = nil
            Self.stateLock.withLock { Self.current = nil }
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

            swizzleNotificationCenterDelegateSetter()
            if let existingDelegate = UNUserNotificationCenter.current().delegate {
                Self.swizzleNotificationDelegateMethods(on: type(of: existingDelegate))
            }
        }

        func stop() {
            unswizzleNotificationCenterDelegateSetter()
        }

        private static let delegateSetterOriginal = #selector(setter: UNUserNotificationCenter.delegate)
        private static let delegateSetterSwizzled = #selector(UNUserNotificationCenter.ph_swizzled_setDelegate(_:))

        private func swizzleNotificationCenterDelegateSetter() {
            // UNUserNotificationCenter.delegate setter always exists — use swizzle(), not swizzleAddingIfNeeded().
            swizzle(forClass: UNUserNotificationCenter.self, original: Self.delegateSetterOriginal, new: Self.delegateSetterSwizzled)
        }

        private func unswizzleNotificationCenterDelegateSetter() {
            swizzle(forClass: UNUserNotificationCenter.self, original: Self.delegateSetterOriginal, new: Self.delegateSetterSwizzled)
            Self.swizzledDelegateClassesLock.withLock {
                Self.swizzledDelegateClasses.removeAll()
            }
        }

        fileprivate static func swizzleNotificationDelegateMethods(on delegateClass: AnyClass) {
            swizzledDelegateClassesLock.withLock {
                let classId = ObjectIdentifier(delegateClass)
                guard !swizzledDelegateClasses.contains(classId) else { return }
                swizzledDelegateClasses.insert(classId)
            }

            swizzleAddingIfNeeded(
                on: delegateClass,
                original: #selector(
                    UNUserNotificationCenterDelegate.userNotificationCenter(_:didReceive:withCompletionHandler:)
                ),
                swizzled: #selector(
                    NSObject.ph_swizzled_userNotificationCenter(_:didReceive:withCompletionHandler:)
                )
            )
        }

        fileprivate static func captureNotificationEngagement(response: UNNotificationResponse) {
            // Atomically check for a live integration; if none, buffer for cold-start replay.
            let integration: PostHogPushNotificationOpenIntegration? = stateLock.withLock {
                if let current {
                    return current
                }
                pendingResponse = response
                return nil
            }
            integration?.postHog?.capturePushNotificationOpened(response: response)
        }
    }

    // MARK: - UNUserNotificationCenter Swizzled Setter

    @available(iOS 14.0, macOS 11.0, *)
    extension UNUserNotificationCenter {
        @objc func ph_swizzled_setDelegate(_ delegate: UNUserNotificationCenterDelegate?) {
            if let delegate {
                PostHogPushNotificationOpenIntegration.swizzleNotificationDelegateMethods(on: type(of: delegate))
            }
            ph_swizzled_setDelegate(delegate)
        }
    }

    // MARK: - NSObject Swizzled Methods

    @available(iOS 14.0, macOS 11.0, *)
    extension NSObject {
        @objc func ph_swizzled_userNotificationCenter(
            _ center: UNUserNotificationCenter,
            didReceive response: UNNotificationResponse,
            withCompletionHandler completionHandler: @escaping () -> Void
        ) {
            PostHogPushNotificationOpenIntegration.captureNotificationEngagement(response: response)
            ph_swizzled_userNotificationCenter(center, didReceive: response, withCompletionHandler: completionHandler)
        }
    }

    #if TESTING
        @available(iOS 14.0, macOS 11.0, *)
        extension PostHogPushNotificationOpenIntegration {
            static func clearInstalls() {
                integrationInstalledLock.withLock {
                    integrationInstalled = false
                }
                stateLock.withLock {
                    current = nil
                    pendingResponse = nil
                }
                swizzledDelegateClassesLock.withLock {
                    swizzledDelegateClasses.removeAll()
                }
            }
        }
    #endif
#endif
