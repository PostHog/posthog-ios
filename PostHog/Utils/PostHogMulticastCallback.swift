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

final class RegistrationToken {
    private let onDealloc: () -> Void

    init(_ onDealloc: @escaping () -> Void) {
        self.onDealloc = onDealloc
    }

    deinit {
        onDealloc()
    }
}

/// A thread-safe callback that allows multiple subscribers with per-subscriber throttling.
/// Each subscriber can specify their own throttle interval.
///
/// Usage:
/// ```swift
/// let onViewLayout = PostHogThrottledMulticastCallback<Void>()
///
/// // Subscribe with throttle
/// let token = onViewLayout.subscribe(throttle: 0.5) {
///     print("View laid out (throttled)")
/// }
///
/// // Invoke all subscribers (each respects its own throttle)
/// onViewLayout.invoke(())
/// ```
final class PostHogThrottledMulticastCallback<T> {
    private var callbacks: [UUID: ThrottledCallback] = [:]
    private let lock = NSLock()
    private let onSubscriberCountChanged: ((Int) -> Void)?

    /// Serial queue that drains throttled callbacks. Stored per instance: generic types
    /// cannot have stored static properties, and a computed static would allocate a fresh
    /// queue on every `invoke()` — besides the allocation cost, separate queues would also
    /// void the serialization that `ThrottledCallback.lastFired` relies on.
    private let throttleQueue = DispatchQueue(
        label: "com.posthog.ThrottledMulticastCallback",
        target: .global(qos: .utility)
    )

    /// Earliest instant at which any subscriber becomes eligible to fire again. Guarded by
    /// `lock`. May be stale-early (worst case: one extra no-op dispatch), but never
    /// stale-late: `subscribe` resets it, and only the drain on `throttleQueue` moves it
    /// forward from the live subscriber map.
    private var nextEligibleFire: Date = .distantPast

    /// Creates a new throttled multicast callback.
    /// - Parameter onSubscriberCountChanged: Optional closure called when subscriber count changes.
    init(onSubscriberCountChanged: ((Int) -> Void)? = nil) {
        self.onSubscriberCountChanged = onSubscriberCountChanged
    }

    /// Subscribe to this callback with a throttle interval.
    /// - Parameters:
    ///   - throttle: The minimum interval between callback invocations for this subscriber.
    ///   - callback: The callback to invoke when `invoke()` is called (on main thread).
    /// - Returns: A `RegistrationToken` that unsubscribes when deallocated.
    func subscribe(throttle interval: TimeInterval, _ callback: @escaping (T) -> Void) -> RegistrationToken {
        let id = UUID()
        let newCount = lock.withLock {
            callbacks[id] = ThrottledCallback(handler: callback, interval: interval)
            // A new subscriber is immediately eligible; without this reset the invoke()
            // gate could suppress its first fire until the other subscribers' windows open.
            nextEligibleFire = .distantPast
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

    /// Invoke all subscribed callbacks, respecting each subscriber's throttle interval.
    /// - Parameter value: The value to pass to all callbacks.
    func invoke(_ value: T) {
        // Synchronous cheap gate: skip the dispatch (queue hop + closure allocation)
        // entirely when nobody is subscribed or no subscriber's throttle window has
        // elapsed yet. This is the steady state when invoked per view layout.
        let shouldDispatch = lock.withLock {
            !callbacks.isEmpty && now() >= nextEligibleFire
        }
        guard shouldDispatch else { return }

        throttleQueue.async { [weak self] in
            guard let self else { return }
            let callbacks = self.lock.withLock { Array(self.callbacks.values) }
            for callback in callbacks {
                callback.invokeIfReady(value)
            }
            // Recompute from the live subscriber map (not the drained copy) so a
            // subscriber added mid-drain — eligible immediately — is not gated out.
            // `lastFired` is only mutated on this serial queue, so reading it here is safe.
            self.lock.withLock {
                self.nextEligibleFire = self.callbacks.values.map(\.nextEligibleTime).min() ?? .distantFuture
            }
        }
    }

    /// Returns the number of active subscribers.
    var subscriberCount: Int {
        lock.withLock { callbacks.count }
    }

    private final class ThrottledCallback {
        let interval: TimeInterval
        let handler: (T) -> Void
        private var lastFired: Date = .distantPast

        /// Read only on the owning callback's `throttleQueue` (same place `lastFired` mutates).
        var nextEligibleTime: Date {
            lastFired.addingTimeInterval(interval)
        }

        init(handler: @escaping (T) -> Void, interval: TimeInterval) {
            self.handler = handler
            self.interval = interval
        }

        func invokeIfReady(_ value: T) {
            let currentTime = now()
            let timeSinceLastFired = currentTime.timeIntervalSince(lastFired)

            if timeSinceLastFired >= interval {
                lastFired = currentTime
                DispatchQueue.main.async { [handler] in
                    handler(value)
                }
            }
        }
    }
}
