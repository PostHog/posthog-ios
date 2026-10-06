//
//  Reachability.swift
//  PostHog
//

import Foundation

#if !os(watchOS)
    import Network

    /// Tracks network connectivity with `NWPathMonitor`.
    final class Reachability {
        enum Connection {
            case unavailable, wifi, cellular
        }

        /// Multicast hooks: every subscriber gets called on every transition.
        /// Returned `RegistrationToken` unsubscribes on deinit, so callers
        /// just hold it for as long as they want to receive notifications.
        let onReachable = PostHogMulticastCallback<Reachability>()
        let onUnreachable = PostHogMulticastCallback<Reachability>()

        private let monitor = NWPathMonitor()
        private let monitorQueue = DispatchQueue(label: "com.posthog.Reachability")
        private let notificationQueue: DispatchQueue?
        private let firstPath = DispatchGroup()
        private let firstPathDeadline = DispatchTime.now() + .milliseconds(100)
        private let lock = NSLock()
        private var latestConnection: Connection?
        private var notifierRunning = false

        /// - Parameter monitorsPaths: `false` skips `NWPathMonitor` so tests can drive `update(_:)`.
        init(notificationQueue: DispatchQueue? = .main, monitorsPaths: Bool = true) {
            self.notificationQueue = notificationQueue
            firstPath.enter()
            guard monitorsPaths else { return }
            monitor.pathUpdateHandler = { [weak self] path in
                self?.update(Self.connection(for: path))
            }
            monitor.start(queue: monitorQueue)
        }

        deinit {
            monitor.cancel()
        }

        /// The current connection, or `nil` if the monitor hasn't reported a path yet.
        ///
        /// `NWPathMonitor` delivers its first path asynchronously right after it starts,
        /// so reads wait for it, up to 100 ms after init in total. Events captured during
        /// SDK setup would otherwise miss their network properties.
        var connection: Connection? {
            if let connection = lock.withLock({ latestConnection }) {
                return connection
            }
            _ = firstPath.wait(timeout: firstPathDeadline)
            return lock.withLock { latestConnection }
        }

        /// Starts calling `onReachable` / `onUnreachable` on connectivity changes.
        ///
        /// Like the old `SCNetworkReachability` initial check, the first start also reports
        /// the current connection, so subscribers flush anything queued while the app was closed.
        func startNotifier() {
            let (started, connection) = lock.withLock { () -> (Bool, Connection?) in
                defer { notifierRunning = true }
                return (!notifierRunning, latestConnection)
            }
            // If no path has arrived yet, `update(_:)` reports the first one.
            if started, let connection {
                notify(connection)
            }
        }

        func stopNotifier() {
            lock.withLock { notifierRunning = false }
        }

        /// Wi-Fi means "reachable and not cellular", so wired connections count as Wi-Fi.
        /// `.requiresConnection` (e.g. VPN on demand) counts as reachable, since sending a
        /// request brings the connection up.
        private static func connection(for path: NWPath) -> Connection {
            guard path.status != .unsatisfied else { return .unavailable }
            return path.usesInterfaceType(.cellular) ? .cellular : .wifi
        }

        func update(_ connection: Connection) {
            // Notify on every path update, like the old `SCNetworkReachability` callback did on
            // every flags change. Paths also update for changes that keep the same connection
            // (e.g. DNS), which only costs a no-op flush.
            let (isFirstPath, shouldNotify) = lock.withLock { () -> (Bool, Bool) in
                let isFirstPath = latestConnection == nil
                latestConnection = connection
                return (isFirstPath, notifierRunning)
            }
            if isFirstPath {
                firstPath.leave()
            }
            if shouldNotify {
                notify(connection)
            }
        }

        private func notify(_ connection: Connection) {
            let notify = { [weak self] in
                guard let self else { return }
                if connection != .unavailable {
                    self.onReachable.invoke(self)
                } else {
                    self.onUnreachable.invoke(self)
                }
            }

            // notify on the configured `notificationQueue`, or the monitor's queue
            notificationQueue?.async(execute: notify) ?? notify()
        }
    }
#endif
