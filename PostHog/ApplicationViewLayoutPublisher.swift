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
                forClass: UIView.self,
                original: #selector(UIView.layoutSublayers(of:)),
                new: #selector(UIView.ph_swizzled_layoutSublayers(of:))
            )
        }

        func unswizzleLayoutSubviews() {
            guard hasSwizzled else { return }
            hasSwizzled = false

            // swizzling twice will exchange implementations back to original
            swizzle(
                forClass: UIView.self,
                original: #selector(UIView.layoutSublayers(of:)),
                new: #selector(UIView.ph_swizzled_layoutSublayers(of:))
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

        final class ThrottledHandler {
            static let throttleQueue = DispatchQueue(label: "com.posthog.ThrottledHandler",
                                                     target: .global(qos: .utility))

            let interval: TimeInterval
            let handler: ApplicationViewLayoutHandler

            private var lastFired: Date = .distantPast

            init(handler: @escaping ApplicationViewLayoutHandler, interval: TimeInterval) {
                self.handler = handler
                self.interval = interval
            }

            func throttleHandler() {
                let now = now()
                let timeSinceLastFired = now.timeIntervalSince(lastFired)

                if timeSinceLastFired >= interval {
                    lastFired = now
                    // notify on main
                    DispatchQueue.main.async(execute: handler)
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
            ThrottledHandler.throttleQueue.async {
                // Don't lock on main
                let handlers = self.registrationLock.withLock { self.onViewLayoutCallbacks.values }
                for handler in handlers {
                    handler.throttleHandler()
                }
            }
        }
    }

    extension UIView {
        @objc func ph_swizzled_layoutSublayers(of layer: CALayer) {
            ph_swizzled_layoutSublayers(of: layer) // call original, not altering execution logic
            ApplicationViewLayoutPublisher.shared.layoutSubviews()
        }
    }
#endif
