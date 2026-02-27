//
//  PostHogMulticastCallback.swift
//  PostHog
//
//  Created by Ioannis Josephides on 23/01/2025.
//

import Foundation

/// A thread-safe callback that allows multiple subscribers.
/// Subscribers receive a `RegistrationToken` that automatically unsubscribes when deallocated.
///
/// Usage:
/// ```swift
/// let onConfigLoaded = PostHogMulticastCallback<[String: Any]?>()
///
/// // Subscribe
/// let token = onConfigLoaded.subscribe { config in
///     print("Config loaded: \(config)")
/// }
///
/// // Invoke all subscribers
/// onConfigLoaded.invoke(someConfig)
///
/// // Token automatically unsubscribes when deallocated
/// ```
final class PostHogMulticastCallback<T> {
    private var callbacks: [UUID: (T) -> Void] = [:]
    private let lock = NSLock()
    private let onSubscriberCountChanged: ((Int) -> Void)?

    /// Creates a new multicast callback.
    /// - Parameter onSubscriberCountChanged: Optional closure called when subscriber count changes.
    init(onSubscriberCountChanged: ((Int) -> Void)? = nil) {
        self.onSubscriberCountChanged = onSubscriberCountChanged
    }

    /// Subscribe to this callback.
    /// - Parameter callback: The callback to invoke when `invoke()` is called.
    /// - Returns: A `RegistrationToken` that unsubscribes when deallocated.
    func subscribe(_ callback: @escaping (T) -> Void) -> RegistrationToken {
        let id = UUID()
        let newCount = lock.withLock {
            callbacks[id] = callback
            return callbacks.count
        }
        onSubscriberCountChanged?(newCount)
        return RegistrationToken { [weak self] in
            guard let self else { return }
            let newCount = self.lock.withLock {
                self.callbacks[id] = nil
                return self.callbacks.count
            }
            self.onSubscriberCountChanged?(newCount)
        }
    }

    /// Invoke all subscribed callbacks with the given value.
    /// - Parameter value: The value to pass to all callbacks.
    func invoke(_ value: T) {
        let callbacks = lock.withLock { Array(self.callbacks.values) }
        for callback in callbacks {
            callback(value)
        }
    }

    /// Returns the number of active subscribers.
    var subscriberCount: Int {
        lock.withLock { callbacks.count }
    }
}
