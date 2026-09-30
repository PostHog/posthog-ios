//
//  PostHogHingeStatusObserver.swift
//  PostHog
//
//  Created by Anna Garcia on 28/09/2026.
//

import Foundation

// `UIHinge` first ships in the iOS 27.1 SDK, whose UIKit is 9127.0.85. The UIKit version is the only
// compile-time signal that separates it from the 27.0 SDK: both ship the same Swift compiler, and
// `canImport(UIKit.UIHinge)` never matches because UIHinge isn't an explicit submodule.
#if os(iOS) && !targetEnvironment(macCatalyst) && canImport(UIKit, _version: 9127.0.85)
    import UIKit
#endif

/// Tracks the hinge of a foldable device, reported as `$hinge_status` on every event.
///
/// One per process: the interaction rides on the key window and is shared by every SDK instance.
final class PostHogHingeStatusObserver: NSObject {
    static let shared = PostHogHingeStatusObserver()

    private let lock = NSLock()
    private var currentStatus: String?

    /// `closed`, `partially_open` or `fully_open`; `nil` when the device has no hinge or doesn't know.
    var status: String? {
        lock.withLock { currentStatus }
    }

    func setStatus(_ status: String?) {
        lock.withLock { currentStatus = status }
    }

    #if os(iOS) && !targetEnvironment(macCatalyst) && canImport(UIKit, _version: 9127.0.85)
        /// Main thread only.
        private var interaction: UIInteraction?

        /// Starts following the hinge. Safe to call repeatedly and from any thread.
        func start() {
            guard #available(iOS 27.1, *) else { return }
            onMain { self.startOnMain() }
        }

        @available(iOS 27.1, *)
        @MainActor
        private func startOnMain() {
            guard interaction == nil else { return }

            // Called with the initial state and on every change, many times per fold with angle
            // updates, so it only stores the status. `hinge` is nil once the window leaves the screen.
            interaction = UIHingeInteraction { [weak self] _, update in
                self?.setStatus(update.hinge.flatMap { Self.value(for: $0.status) })
            }
            NotificationCenter.default.addObserver(self,
                                                   selector: #selector(keyWindowDidChange(_:)),
                                                   name: UIWindow.didBecomeKeyNotification,
                                                   object: nil)
            // A foreground key window first: set up late in a multi-scene app, the unfiltered lookup
            // can return a background scene's window, and no key-window change may follow.
            if let window = UIApplication.getCurrentWindow() ?? UIApplication.getCurrentWindow(filterForegrounded: false) {
                attach(to: window)
            }
        }

        @objc private func keyWindowDidChange(_ notification: Notification) {
            guard let window = notification.object as? UIWindow else { return }
            onMain { self.attach(to: window) }
        }

        private func onMain(_ body: @escaping @MainActor () -> Void) {
            if Thread.isMainThread {
                MainActor.assumeIsolated(body)
            } else {
                DispatchQueue.main.async { MainActor.assumeIsolated(body) }
            }
        }

        /// Moves the interaction onto `window`; the window owns it, we don't own the window.
        @MainActor
        private func attach(to window: UIWindow) {
            guard let interaction, interaction.view !== window else { return }
            interaction.view?.removeInteraction(interaction)
            window.addInteraction(interaction)
        }

        /// `nil` for `.unknown`, so the property is left out rather than guessed.
        @available(iOS 27.1, *)
        static func value(for status: UIHinge.Status) -> String? {
            switch status {
            case .closed:
                return "closed"
            case .partiallyOpen:
                return "partially_open"
            case .fullyOpen:
                return "fully_open"
            case .unknown:
                return nil
            @unknown default:
                return nil
            }
        }
    #else
        func start() {}
    #endif
}
