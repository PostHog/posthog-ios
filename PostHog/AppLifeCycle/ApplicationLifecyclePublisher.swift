//
//  ApplicationLifecyclePublisher.swift
//  PostHog
//
//  Created by Yiannis Josephides on 16/12/2024.
//

#if os(iOS) || os(tvOS) || os(visionOS)
    import UIKit
#elseif os(macOS)
    import AppKit
#elseif os(watchOS)
    import WatchKit
#endif

protocol AppLifecyclePublishing: AnyObject {
    /// Callback for the `didBecomeActive` event.
    var onDidBecomeActive: PostHogMulticastCallback<Void> { get }
    /// Callback for the `didEnterBackground` event.
    var onDidEnterBackground: PostHogMulticastCallback<Void> { get }
    /// Callback for the `didFinishLaunching` event.
    var onDidFinishLaunching: PostHogMulticastCallback<Void> { get }
    /// Snapshot of the current background state. NotificationCenter doesn't
    /// replay past lifecycle events, so consumers that care about the value
    /// at subscription time should seed from this rather than waiting for
    /// the next state-change callback.
    var isInBackground: Bool { get }
    /// Current native activity, sampled on main; returns false off-main.
    var isActive: Bool { get }
    /// Whether the app has already been active, including before a consumer subscribes.
    /// Off-main reads use observed activations without synchronously querying the UI.
    var hasBecomeActive: Bool { get }
}

/**
 A publisher that handles application lifecycle events and allows registering callbacks for them.

 This class provides a way to observe application lifecycle events like when the app becomes active,
 enters background, or finishes launching. Callbacks can be registered for each event type and will
 be automatically unregistered when their registration token is deallocated.

 Example usage:
 ```
 let token = ApplicationLifecyclePublisher.shared.onDidBecomeActive.subscribe {
     // App became active logic
 }
 // Keep `token` in memory to keep the registration active
 // When token is deallocated, the callback will be automatically unregistered
 ```
 */
final class ApplicationLifecyclePublisher: AppLifecyclePublishing {
    /// Shared instance to allow easy access across the app.
    static let shared = ApplicationLifecyclePublisher()

    let onDidBecomeActive = PostHogMulticastCallback<Void>()
    let onDidEnterBackground = PostHogMulticastCallback<Void>()
    let onDidFinishLaunching = PostHogMulticastCallback<Void>()

    /// UIKit's live state is only queried on main. Elsewhere, use observed
    /// transitions without blocking callers that may hold SDK locks needed by main.
    var isInBackground: Bool {
        #if os(iOS) || os(tvOS) || os(visionOS)
            if Thread.isMainThread, let state = applicationState() {
                return state == .background
            }
        #endif
        return stateLock.withLock { isBackgrounded }
    }

    private let stateLock = NSLock()
    private var hasObservedActivation = false
    private var isBackgrounded = false

    #if os(iOS) || os(tvOS) || os(visionOS)
        /// Nil until UIKit creates the shared app, for example in a SwiftUI `App.init`.
        /// `UIApplication.shared` would then message nil and read `.active`.
        private var applicationState: () -> UIApplication.State? = ApplicationLifecyclePublisher.sharedApplicationState

        private static func sharedApplicationState() -> UIApplication.State? {
            let sharedApplication = UIApplication.perform(NSSelectorFromString("sharedApplication"))?.takeUnretainedValue()
            return (sharedApplication as? UIApplication)?.applicationState
        }
    #endif

    var isActive: Bool {
        guard Thread.isMainThread else { return false }
        #if os(iOS) || os(tvOS) || os(visionOS)
            return applicationState() == .active
        #elseif os(macOS)
            return NSApplication.shared.isActive
        #elseif os(watchOS)
            if #available(watchOS 7.0, *) {
                return WKApplication.shared().applicationState == .active
            } else {
                return WKExtension.shared().applicationState == .active
            }
        #else
            return false
        #endif
    }

    var hasBecomeActive: Bool {
        if stateLock.withLock({ hasObservedActivation }) {
            return true
        }
        let isActive = self.isActive

        return stateLock.withLock {
            hasObservedActivation = hasObservedActivation || isActive
            return hasObservedActivation
        }
    }

    init(notificationCenter defaultCenter: NotificationCenter = .default) {
        #if os(iOS) || os(tvOS)
            defaultCenter.addObserver(self,
                                      selector: #selector(appDidFinishLaunching),
                                      name: UIApplication.didFinishLaunchingNotification,
                                      object: nil)
            defaultCenter.addObserver(self,
                                      selector: #selector(appDidEnterBackground),
                                      name: UIApplication.didEnterBackgroundNotification,
                                      object: nil)
            defaultCenter.addObserver(self,
                                      selector: #selector(appDidBecomeActive),
                                      name: UIApplication.didBecomeActiveNotification,
                                      object: nil)
        #elseif os(visionOS)
            defaultCenter.addObserver(self,
                                      selector: #selector(appDidFinishLaunching),
                                      name: UIApplication.didFinishLaunchingNotification,
                                      object: nil)
            defaultCenter.addObserver(self,
                                      selector: #selector(appDidEnterBackground),
                                      name: UIScene.willDeactivateNotification,
                                      object: nil)
            defaultCenter.addObserver(self,
                                      selector: #selector(appDidBecomeActive),
                                      name: UIScene.didActivateNotification,
                                      object: nil)
        #elseif os(macOS)
            defaultCenter.addObserver(self,
                                      selector: #selector(appDidFinishLaunching),
                                      name: NSApplication.didFinishLaunchingNotification,
                                      object: nil)
            // macOS does not have didEnterBackgroundNotification, so we use didResignActiveNotification
            defaultCenter.addObserver(self,
                                      selector: #selector(appDidEnterBackground),
                                      name: NSApplication.didResignActiveNotification,
                                      object: nil)
            defaultCenter.addObserver(self,
                                      selector: #selector(appDidBecomeActive),
                                      name: NSApplication.didBecomeActiveNotification,
                                      object: nil)
        #elseif os(watchOS)
            if #available(watchOS 7.0, *) {
                defaultCenter.addObserver(self,
                                          selector: #selector(appDidBecomeActive),
                                          name: WKApplication.didBecomeActiveNotification,
                                          object: nil)
            } else {
                defaultCenter.addObserver(self,
                                          selector: #selector(appDidBecomeActive),
                                          name: .init("UIApplicationDidBecomeActiveNotification"),
                                          object: nil)
            }
        #endif
    }

    #if os(iOS) || os(tvOS) || os(visionOS)
        convenience init(notificationCenter: NotificationCenter, applicationState: @escaping () -> UIApplication.State?) {
            self.init(notificationCenter: notificationCenter)
            self.applicationState = applicationState
        }
    #endif

    @objc private func appDidEnterBackground() {
        stateLock.withLock { isBackgrounded = true }
        onDidEnterBackground.invoke(())
    }

    @objc private func appDidBecomeActive() {
        stateLock.withLock {
            hasObservedActivation = true
            isBackgrounded = false
        }
        onDidBecomeActive.invoke(())
    }

    @objc private func appDidFinishLaunching() {
        onDidFinishLaunching.invoke(())
    }
}
