//
//  Reachability.swift
//  PostHog
//

import Foundation

#if !os(watchOS)
    import Network

    /// Tracks network connectivity with `NWPathMonitor`.
    final class Reachability {
        enum Connection: CustomStringConvertible {
            case unavailable, wifi, cellular
            var description: String {
                switch self {
                case .cellular: return "Cellular"
                case .wifi: return "WiFi"
                case .unavailable: return "No Connection"
                }
            }
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
        private let lock = NSLock()
        private var latestConnection: Connection?
        private var notifierRunning = false

        init(notificationQueue: DispatchQueue? = .main) {
            self.notificationQueue = notificationQueue
            firstPath.enter()
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
        /// so the first read waits briefly for it. Events captured during SDK setup would
        /// otherwise miss their network properties.
        var connection: Connection? {
            if let connection = lock.withLock({ latestConnection }) {
                return connection
            }
            _ = firstPath.wait(timeout: .now() + .milliseconds(100))
            return lock.withLock { latestConnection }
        }

        /// Starts calling `onReachable` / `onUnreachable` on connectivity changes.
        func startNotifier() {
            lock.withLock { notifierRunning = true }
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

        private func update(_ connection: Connection) {
            let (isFirstPath, shouldNotify) = lock.withLock { () -> (Bool, Bool) in
                let previous = latestConnection
                latestConnection = connection
                return (previous == nil, notifierRunning && previous != connection)
            }
            if isFirstPath {
                firstPath.leave()
            }
            guard shouldNotify else { return }

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
