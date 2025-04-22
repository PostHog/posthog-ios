//
//  ApplicationViewLayoutPublisher.swift
//  PostHog
//
//  Created by Ioannis Josephides on 19/03/2025.
//

#if os(iOS) || os(tvOS)
    import UIKit

    typealias ApplicationViewLayoutHandler = () -> Void

    protocol ViewLayoutPublishing: AnyObject {
        /// Registers a callback for getting notified when a UIView is laid out.
        /// Note: callback guaranteed to be called on main thread
        func onViewLayout(throttle: TimeInterval, _ callback: @escaping ApplicationViewLayoutHandler) -> RegistrationToken
    }

    final class ApplicationViewLayoutPublisher: BaseApplicationViewLayoutPublisher {
        static let shared = ApplicationViewLayoutPublisher()

        private var hasSwizzled: Bool = false

        func start() {
            swizzleLayoutSubviews()
        }

        func stop() {
            unswizzleLayoutSubviews()
        }

        func swizzleLayoutSubviews() {
            guard !hasSwizzled else { return }
            hasSwizzled = true

            swizzle(
                forClass: UIViewController.self,
                original: #selector(UIViewController.viewDidLayoutSubviews),
                new: #selector(UIViewController.ph_swizzled_LayoutSubviews)
            )
        }

        func unswizzleLayoutSubviews() {
            guard hasSwizzled else { return }
            hasSwizzled = false

            // swizzling twice will exchange implementations back to original
            swizzle(
                forClass: UIViewController.self,
                original: #selector(UIViewController.viewDidLayoutSubviews),
                new: #selector(UIViewController.ph_swizzled_LayoutSubviews)
            )
        }

        override func onViewLayout(throttle interval: TimeInterval, _ callback: @escaping ApplicationViewLayoutHandler) -> RegistrationToken {
            let id = UUID()
            registrationLock.withLock {
                self.onViewLayoutCallbacks[id] = ThrottledHandler(handler: callback, interval: interval)
            }

            // start on first callback registration
            if !hasSwizzled {
                start()
            }

            return RegistrationToken { [weak self] in
                // Registration token deallocated here
                guard let self else { return }
                let handlerCount = self.registrationLock.withLock {
                    self.onViewLayoutCallbacks[id] = nil
                    return self.onViewLayoutCallbacks.values.count
                }

                // stop when there are no more callbacks
                if handlerCount <= 0 {
                    self.stop()
                }
            }
        }

        // Called from swizzled `UIView.layoutSubviews`
        fileprivate func layoutSubviews() {
            notifyHandlers()
        }

        #if TESTING
            func simulateLayoutSubviews() {
                layoutSubviews()
            }
        #endif
    }

    class BaseApplicationViewLayoutPublisher: ViewLayoutPublishing {
        fileprivate let registrationLock = NSLock()

        var onViewLayoutCallbacks: [UUID: ThrottledHandler] = [:]

        static let dispatchQueue = DispatchQueue(label: "com.posthog.PostHogReplayIntegration",
                                                 target: .global(qos: .utility))

        final class ThrottledHandler {
            let interval: TimeInterval
            let handler: ApplicationViewLayoutHandler

            private var lastFired: Date = .distantPast

            init(handler: @escaping ApplicationViewLayoutHandler, interval: TimeInterval) {
                self.handler = handler
                self.interval = interval
            }

            func throttleHandler() {
                let runThrottle = { [weak self] in
                    guard let self else { return }
                    let now = now()
                    let timeSinceLastFired = now.timeIntervalSince(lastFired)

                    if timeSinceLastFired >= interval {
                        lastFired = now
                        handler()
                    }
                }

                if Thread.isMainThread {
                    runThrottle()
                } else {
                    DispatchQueue.main.async {
                        runThrottle()
                    }
                }
            }
        }

        func onViewLayout(throttle interval: TimeInterval, _ callback: @escaping ApplicationViewLayoutHandler) -> RegistrationToken {
            let id = UUID()
            registrationLock.withLock {
                self.onViewLayoutCallbacks[id] = ThrottledHandler(
                    handler: callback,
                    interval: interval
                )
            }

            return RegistrationToken { [weak self] in
                // Registration token deallocated here
                guard let self else { return }
                self.registrationLock.withLock {
                    self.onViewLayoutCallbacks[id] = nil
                }
            }
        }

        func notifyHandlers() {
            let handlers = registrationLock.withLock { onViewLayoutCallbacks.values }
            for handler in handlers {
                handler.throttleHandler()
            }
        }
    }

    extension UIViewController {
        @objc func ph_swizzled_LayoutSubviews() {
            ph_swizzled_LayoutSubviews() // call original, not altering execution logic
            if Thread.isMainThread {
                ApplicationViewLayoutPublisher.shared.layoutSubviews()
            }
        }
    }
#endif
