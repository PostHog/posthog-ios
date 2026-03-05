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

    private init() {
        let defaultCenter = NotificationCenter.default

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
                NotificationCenter.default.addObserver(self,
                                                       selector: #selector(appDidBecomeActive),
                                                       name: WKApplication.didBecomeActiveNotification,
                                                       object: nil)
            } else {
                NotificationCenter.default.addObserver(self,
                                                       selector: #selector(appDidBecomeActive),
                                                       name: .init("UIApplicationDidBecomeActiveNotification"),
                                                       object: nil)
            }
        #endif
    }

    @objc private func appDidEnterBackground() {
        onDidEnterBackground.invoke(())
    }

    @objc private func appDidBecomeActive() {
        onDidBecomeActive.invoke(())
    }

    @objc private func appDidFinishLaunching() {
        onDidFinishLaunching.invoke(())
    }
}
