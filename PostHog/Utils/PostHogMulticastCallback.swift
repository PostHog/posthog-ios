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

    /// Earliest instant at which any leading-only subscriber becomes eligible to fire again. Guarded by
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
    ///   - trailing: Deliver the latest value received inside a window when that window closes.
    ///     Values are coalesced while delivery is waiting for the main thread.
    ///   - callback: The callback to invoke when `invoke()` is called (on main thread).
    /// - Returns: A `RegistrationToken` that unsubscribes when deallocated.
    func subscribe(throttle interval: TimeInterval, trailing: Bool = false, _ callback: @escaping (T) -> Void) -> RegistrationToken {
        let id = UUID()
        let newCount = lock.withLock {
            callbacks[id] = ThrottledCallback(handler: callback, interval: interval, trailing: trailing)
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
        let shouldDispatch = lock.withLock {
            // Record trailing values before the eligibility gate. Updating an already pending
            // value does not allocate another work item or dispatch for every view layout.
            for callback in callbacks.values where callback.trailing {
                callback.invokeTrailing(value)
            }
            return callbacks.values.contains { !$0.trailing } && now() >= nextEligibleFire
        }
        guard shouldDispatch else { return }

        throttleQueue.async { [weak self] in
            guard let self else { return }
            let callbacks = self.lock.withLock { self.callbacks.values.filter { !$0.trailing } }
            for callback in callbacks {
                callback.invokeIfReady(value)
            }
            // Recompute from the live subscriber map (not the drained copy) so a
            // subscriber added mid-drain — eligible immediately — is not gated out.
            // Leading-only subscribers' `lastFired` is only mutated on this serial queue.
            self.lock.withLock {
                self.nextEligibleFire = self.callbacks.values.filter { !$0.trailing }.map(\.nextEligibleTime).min() ?? .distantFuture
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
        let trailing: Bool
        private var lastFired: Date = .distantPast

        // Trailing subscriptions accept values synchronously, rather than queueing every layout.
        // Their state is shared with the delayed main-queue delivery and guarded by this lock.
        private let trailingLock = NSLock()
        private var pendingValue: T?
        private var pendingWork: DispatchWorkItem?

        /// Used only for leading-only subscriptions on the owning callback's `throttleQueue`.
        var nextEligibleTime: Date {
            lastFired.addingTimeInterval(interval)
        }

        init(handler: @escaping (T) -> Void, interval: TimeInterval, trailing: Bool) {
            self.handler = handler
            self.interval = interval
            self.trailing = trailing
        }

        deinit {
            // Scheduled work only weakly references this subscription, so dropping its token
            // (including replay stop/reset) releases the handler and cancels pending delivery.
            pendingWork?.cancel()
        }

        func invokeTrailing(_ value: T) {
            guard interval > 0 else {
                DispatchQueue.main.async { [weak self] in
                    self?.handler(value)
                }
                return
            }
            trailingLock.withLock {
                // .some preserves a pending nil when T itself is Optional.
                pendingValue = .some(value)
                guard pendingWork == nil else { return }
                let remaining = max(0, interval - now().timeIntervalSince(lastFired))
                let work = DispatchWorkItem { [weak self] in
                    self?.fireTrailing()
                }
                pendingWork = work
                DispatchQueue.main.asyncAfter(deadline: .now() + remaining, execute: work)
            }
        }

        private func fireTrailing() {
            let value: T? = trailingLock.withLock {
                let value = pendingValue
                pendingValue = nil
                pendingWork = nil
                // Start the next window at delivery, not scheduling: a busy main thread must
                // not accumulate snapshots that then fire back-to-back when it becomes free.
                lastFired = now()
                return value
            }
            if let value {
                handler(value)
            }
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
