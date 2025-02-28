//
//  ApplicationLifecyclePublisher.swift
//  PostHog
//
//  Created by Yiannis Josephides on 16/12/2024.
//

#if os(iOS) || os(tvOS)
    import UIKit
#elseif os(macOS)
    import AppKit
#elseif os(watchOS)
    import WatchKit
#endif

typealias AppLifecycleHandler = () -> Void

protocol AppLifecyclePublishing: AnyObject {
    /// Registers a callback for the `didBecomeActive` event.
    func onDidBecomeActive(_ callback: @escaping AppLifecycleHandler) -> RegistrationToken
    /// Registers a callback for the `didEnterBackground` event.
    func onDidEnterBackground(_ callback: @escaping AppLifecycleHandler) -> RegistrationToken
    /// Registers a callback for the `didFinishLaunching` event.
    func onDidFinishLaunching(_ callback: @escaping AppLifecycleHandler) -> RegistrationToken
}

/**
 A publisher that handles application lifecycle events and allows registering callbacks for them.

 This class provides a way to observe application lifecycle events like when the app becomes active,
 enters background, or finishes launching. Callbacks can be registered for each event type and will
 be automatically unregistered when their registration token is deallocated.

 Example usage:
 ```
 let token = ApplicationLifecyclePublisher.shared.onDidBecomeActive {
     // App became active logic
 }
 // Keep `token` in memory to keep the registration active
 // When token is deallocated, the callback will be automatically unregistered
 ```
 */
final class ApplicationLifecyclePublisher: BaseApplicationLifecyclePublisher {
    /// Shared instance to allow easy access across the app.
    static let shared = ApplicationLifecyclePublisher()

    override private init() {
        super.init()

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

    // MARK: - Handlers

    @objc private func appDidEnterBackground() {
        notifyHandlers(didEnterBackgroundHandlers)
    }

    @objc private func appDidBecomeActive() {
        notifyHandlers(didBecomeActiveHandlers)
    }

    @objc private func appDidFinishLaunching() {
        notifyHandlers(didFinishLaunchingHandlers)
    }

    private func notifyHandlers(_ handlers: [AppLifecycleHandler]) {
        for handler in handlers {
            notifyHander(handler)
        }
    }

    private func notifyHander(_ handler: @escaping AppLifecycleHandler) {
        if Thread.isMainThread {
            handler()
        } else {
            DispatchQueue.main.async(execute: handler)
        }
    }
}

class BaseApplicationLifecyclePublisher: AppLifecyclePublishing {
    private let registrationLock = NSLock()

    private var didBecomeActiveCallbacks: [UUID: AppLifecycleHandler] = [:]
    private var didEnterBackgroundCallbacks: [UUID: AppLifecycleHandler] = [:]
    private var didFinishLaunchingCallbacks: [UUID: AppLifecycleHandler] = [:]

    var didBecomeActiveHandlers: [AppLifecycleHandler] {
        registrationLock.withLock { Array(didBecomeActiveCallbacks.values) }
    }

    var didEnterBackgroundHandlers: [AppLifecycleHandler] {
        registrationLock.withLock { Array(didEnterBackgroundCallbacks.values) }
    }

    var didFinishLaunchingHandlers: [AppLifecycleHandler] {
        registrationLock.withLock { Array(didFinishLaunchingCallbacks.values) }
    }

    /// Registers a callback for the `didBecomeActive` event.
    func onDidBecomeActive(_ callback: @escaping AppLifecycleHandler) -> RegistrationToken {
        register(handler: callback, on: \.didBecomeActiveCallbacks)
    }

    /// Registers a callback for the `didEnterBackground` event.
    func onDidEnterBackground(_ callback: @escaping AppLifecycleHandler) -> RegistrationToken {
        register(handler: callback, on: \.didEnterBackgroundCallbacks)
    }

    /// Registers a callback for the `didFinishLaunching` event.
    func onDidFinishLaunching(_ callback: @escaping AppLifecycleHandler) -> RegistrationToken {
        register(handler: callback, on: \.didFinishLaunchingCallbacks)
    }

    func register(
        handler callback: @escaping AppLifecycleHandler,
        on keyPath: ReferenceWritableKeyPath<BaseApplicationLifecyclePublisher, [UUID: AppLifecycleHandler]>
    ) -> RegistrationToken {
        let id = UUID()
        registrationLock.withLock {
            self[keyPath: keyPath][id] = callback
        }

        return RegistrationToken { [weak self] in
            // Registration token deallocated here
            guard let self else { return }
            self.registrationLock.withLock {
                self[keyPath: keyPath][id] = nil
            }
        }
    }
}

final class RegistrationToken {
    private let onDealloc: () -> Void

    init(_ onDealloc: @escaping () -> Void) {
        self.onDealloc = onDealloc
    }

    deinit {
        onDealloc()
    }
}
