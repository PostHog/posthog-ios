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
        /// Registers a callback for a `UIApplication.sendEvent`
        var onApplicationEvent: PostHogMulticastCallback<ApplicationEventData> { get }
    }

    typealias ApplicationEventData = (UIEvent, Date)

    final class ApplicationEventPublisher: ApplicationEventPublishing {
        private(set) lazy var onApplicationEvent = PostHogMulticastCallback<ApplicationEventData> { [weak self] subscriberCount in
            if subscriberCount > 0 {
                self?.swizzleSendEvent()
            } else {
                self?.unswizzleSendEvent()
            }
        }

        static let shared = ApplicationEventPublisher()

        private var hasSwizzled: Bool = false

        private func swizzleSendEvent() {
            guard !hasSwizzled else { return }
            hasSwizzled = true

            swizzle(
                forClass: UIApplication.self,
                original: #selector(UIApplication.sendEvent(_:)),
                new: #selector(UIApplication.sendEventOverride)
            )
        }

        private func unswizzleSendEvent() {
            guard hasSwizzled else { return }
            hasSwizzled = false

            // swizzling twice will exchange implementations back to original
            swizzle(
                forClass: UIApplication.self,
                original: #selector(UIApplication.sendEvent(_:)),
                new: #selector(UIApplication.sendEventOverride)
            )
        }

        // Called from swizzled `UIApplication.sendEvent`
        fileprivate func sendEvent(event: UIEvent, date: Date) {
            onApplicationEvent.invoke((event, date))
        }
    }

    extension UIApplication {
        @objc func sendEventOverride(_ event: UIEvent) {
            sendEventOverride(event)
            ApplicationEventPublisher.shared.sendEvent(event: event, date: Date())
        }
    }

#elseif os(macOS)
    import AppKit

    protocol ApplicationEventPublishing: AnyObject {
        /// Registers a callback for mouse events on macOS
        var onApplicationEvent: PostHogMulticastCallback<ApplicationEventData> { get }
    }

    typealias ApplicationEventData = (NSEvent, Date)

    final class ApplicationEventPublisher: ApplicationEventPublishing {
        private(set) lazy var onApplicationEvent = PostHogMulticastCallback<ApplicationEventData> { [weak self] subscriberCount in
            if subscriberCount > 0 {
                self?.startMonitoring()
            } else {
                self?.stopMonitoring()
            }
        }

        static let shared = ApplicationEventPublisher()

        private var localMonitor: Any?

        private func startMonitoring() {
            guard localMonitor == nil else { return }
            localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .leftMouseUp, .rightMouseDown, .rightMouseUp]) { [weak self] event in
                self?.onApplicationEvent.invoke((event, Date()))
                return event
            }
        }

        private func stopMonitoring() {
            if let monitor = localMonitor {
                NSEvent.removeMonitor(monitor)
                localMonitor = nil
            }
        }
    }

#endif
