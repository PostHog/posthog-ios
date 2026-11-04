//
//  ApplicationEventPublisher.swift
//  PostHog
//
//  Created by Ioannis Josephides on 24/02/2025.
//

import Foundation

#if os(iOS) || os(tvOS)
    import UIKit

    protocol ApplicationEventPublishing: AnyObject {
        /// Invoked for each `UIApplication.sendEvent`, before UIKit dispatches the event.
        var onApplicationEventWillDispatch: PostHogMulticastCallback<ApplicationEventData> { get }
        /// Invoked for each `UIApplication.sendEvent`, after UIKit dispatches the event.
        var onApplicationEvent: PostHogMulticastCallback<ApplicationEventData> { get }
    }

    typealias ApplicationEventData = (UIEvent, Date)

    final class ApplicationEventPublisher: ApplicationEventPublishing {
        static let shared = ApplicationEventPublisher()

        var onApplicationEventWillDispatch: PostHogMulticastCallback<ApplicationEventData> { willDispatchCallbacks }
        var onApplicationEvent: PostHogMulticastCallback<ApplicationEventData> { didDispatchCallbacks }
        private var willDispatchCallbacks: PostHogMulticastCallback<ApplicationEventData>!
        private var didDispatchCallbacks: PostHogMulticastCallback<ApplicationEventData>!

        private let swizzleLock = NSLock()
        private var hasSwizzled = false
        private let exchangeSendEvent: () -> Void

        init(exchangeSendEvent: @escaping () -> Void = ApplicationEventPublisher.exchangeSendEventImplementations) {
            self.exchangeSendEvent = exchangeSendEvent
            // Initialize before publication; Swift lazy properties are not safe on concurrent first access.
            willDispatchCallbacks = PostHogMulticastCallback { [weak self] _ in
                self?.updateSwizzle()
            }
            didDispatchCallbacks = PostHogMulticastCallback { [weak self] _ in
                self?.updateSwizzle()
            }
        }

        private func updateSwizzle() {
            swizzleLock.withLock {
                let hasSubscribers = willDispatchCallbacks.subscriberCount + didDispatchCallbacks.subscriberCount > 0
                guard hasSubscribers != hasSwizzled else { return }
                hasSwizzled = hasSubscribers
                exchangeSendEvent()
            }
        }

        // Exchanging twice restores the original implementation.
        private static func exchangeSendEventImplementations() {
            swizzle(
                forClass: UIApplication.self,
                original: #selector(UIApplication.sendEvent(_:)),
                new: #selector(UIApplication.sendEventOverride)
            )
        }

        func publish(_ event: UIEvent, dispatch: () -> Void) {
            onApplicationEventWillDispatch.invoke((event, Date()))
            dispatch()
            onApplicationEvent.invoke((event, Date()))
        }
    }

    extension UIApplication {
        @objc func sendEventOverride(_ event: UIEvent) {
            ApplicationEventPublisher.shared.publish(event) {
                sendEventOverride(event)
            }
        }
    }
#endif
