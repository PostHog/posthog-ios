//
//  ApplicationEventPublisher.swift
//  PostHog
//
//  Created by Ioannis Josephides on 24/02/2025.
//

import Foundation

#if os(iOS) || os(tvOS)
    import UIKit

    typealias ApplicationEventHandler = (_ event: UIEvent, _ date: Date) -> Void

    protocol ApplicationEventPublishing: AnyObject {
        /// Registers a callback for a `UIApplication.sendEvent`
        func onApplicationEvent(_ callback: @escaping ApplicationEventHandler) -> RegistrationToken
    }

    final class ApplicationEventPublisher: BaseApplicationEventPublisher {
        static let shared = ApplicationEventPublisher()

        private var hasSwizzled: Bool = false

        func start() {
            swizzleSendEvent()
        }

        func stop() {
            unswizzleSendEvent()
        }

        func swizzleSendEvent() {
            guard !hasSwizzled else { return }
            hasSwizzled = true

            swizzle(
                forClass: UIApplication.self,
                original: #selector(UIApplication.sendEvent(_:)),
                new: #selector(UIApplication.sendEventOverride)
            )
        }

        func unswizzleSendEvent() {
            guard hasSwizzled else { return }
            hasSwizzled = false

            // swizzling twice will exchange implementations back to original
            swizzle(
                forClass: UIApplication.self,
                original: #selector(UIApplication.sendEvent(_:)),
                new: #selector(UIApplication.sendEventOverride)
            )
        }

        override func onApplicationEvent(_ callback: @escaping ApplicationEventHandler) -> RegistrationToken {
            let id = UUID()
            registrationLock.withLock {
                self.onApplicationEventCallbacks[id] = callback
            }

            // start on first callback registration
            if !hasSwizzled {
                start()
            }

            return RegistrationToken { [weak self] in
                // Registration token deallocated here
                guard let self else { return }
                let handlerCount = self.registrationLock.withLock {
                    self.onApplicationEventCallbacks[id] = nil
                    return self.onApplicationEventCallbacks.values.count
                }

                // stop when there are no more callbacks
                if handlerCount <= 0 {
                    self.stop()
                }
            }
        }

        // Called from swizzled `UIApplication.sendEvent`
        fileprivate func sendEvent(event: UIEvent, date: Date) {
            notifyHandlers(uiEvent: event, date: date)
        }
    }

    class BaseApplicationEventPublisher: ApplicationEventPublishing {
        fileprivate let registrationLock = NSLock()

        var onApplicationEventCallbacks: [UUID: ApplicationEventHandler] = [:]

        func onApplicationEvent(_ callback: @escaping ApplicationEventHandler) -> RegistrationToken {
            let id = UUID()
            registrationLock.withLock {
                self.onApplicationEventCallbacks[id] = callback
            }

            return RegistrationToken { [weak self] in
                // Registration token deallocated here
                guard let self else { return }
                self.registrationLock.withLock {
                    self.onApplicationEventCallbacks[id] = nil
                }
            }
        }

        func notifyHandlers(uiEvent: UIEvent, date: Date) {
            let handlers = registrationLock.withLock { onApplicationEventCallbacks.values }
            for handler in handlers {
                notifyHander(handler, uiEvent: uiEvent, date: date)
            }
        }

        private func notifyHander(_ handler: @escaping ApplicationEventHandler, uiEvent: UIEvent, date: Date) {
            if Thread.isMainThread {
                handler(uiEvent, date)
            } else {
                DispatchQueue.main.async { handler(uiEvent, date) }
            }
        }
    }

    extension UIApplication {
        @objc func sendEventOverride(_ event: UIEvent) {
            sendEventOverride(event)
            ApplicationEventPublisher.shared.sendEvent(event: event, date: Date())
        }
    }
#endif
