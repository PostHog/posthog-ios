//
//  ApplicationViewLayoutPublisher.swift
//  PostHog
//
//  Created by Ioannis Josephides on 19/03/2025.
//

#if os(iOS) || os(tvOS)
    import UIKit

    protocol ViewLayoutPublishing: AnyObject {
        /// Callback for getting notified when a UIView is laid out.
        /// Note: callback guaranteed to be called on main thread
        var onViewLayout: PostHogThrottledMulticastCallback<Void> { get }
    }

    final class ApplicationViewLayoutPublisher: ViewLayoutPublishing {
        static let shared = ApplicationViewLayoutPublisher()

        var onViewLayout: PostHogThrottledMulticastCallback<Void> { callbacks }
        private var callbacks: PostHogThrottledMulticastCallback<Void>!
        private let viewClass: UIView.Type

        private struct LayoutHook {
            let original: IMP
            let replacement: IMP
            let token: NSObject
        }

        // Only accessed by the multicast's serialized subscriber-count callbacks.
        private var installedLayout: LayoutHook?
        private var layoutHooks: [UInt: LayoutHook] = [:]
        private let activeLayoutLock = NSLock()
        private var activeLayoutToken: NSObject?
        private typealias LayoutImplementation = @convention(c) (UIView, Selector, CALayer) -> Void

        init(viewClass: UIView.Type = UIView.self) {
            self.viewClass = viewClass
            // Initialize before publication; Swift lazy properties are not safe on concurrent first access.
            callbacks = PostHogThrottledMulticastCallback<Void> { [weak self] subscriberCount in
                if subscriberCount > 0 {
                    self?.swizzleLayoutSubviews()
                } else {
                    self?.unswizzleLayoutSubviews()
                }
            }
        }

        private let backgroundLayoutWarningLock = NSLock()
        private var hasWarnedAboutBackgroundLayout = false

        private func warnAboutBackgroundLayout() {
            guard hedgeLogEnabled else { return }
            let shouldWarn = backgroundLayoutWarningLock.withLock {
                guard !hasWarnedAboutBackgroundLayout else { return false }
                hasWarnedAboutBackgroundLayout = true
                return true
            }
            if shouldWarn {
                hedgeLog("Warning: UIView.layoutSublayers(of:) was called off the main thread. UIKit layout may crash in this situation. Use Main Thread Checker to investigate off-main view or layer access. PostHog is forwarding the original call unchanged.")
            }
        }

        private func swizzleLayoutSubviews() {
            guard installedLayout == nil,
                  let method = class_getInstanceMethod(viewClass, #selector(UIView.layoutSublayers(of:)))
            else { return }

            let hook = layoutHook(for: method_getImplementation(method))
            activeLayoutLock.withLock { activeLayoutToken = hook.token }
            method_setImplementation(method, hook.replacement)
            installedLayout = hook
        }

        private func unswizzleLayoutSubviews() {
            guard let installedLayout,
                  let method = class_getInstanceMethod(viewClass, #selector(UIView.layoutSublayers(of:)))
            else { return }

            // A newer swizzler may still forward through our IMP. Do not overwrite its hook or wrap it again.
            guard method_getImplementation(method) == installedLayout.replacement else { return }
            method_setImplementation(method, installedLayout.original)
            activeLayoutLock.withLock { activeLayoutToken = nil }
            self.installedLayout = nil
        }

        private func layoutHook(for original: IMP) -> LayoutHook {
            let key = unsafeBitCast(original, to: UInt.self)
            if let hook = layoutHooks[key] {
                return hook
            }

            let forward = unsafeBitCast(original, to: LayoutImplementation.self)
            let selector = #selector(UIView.layoutSublayers(of:))
            let token = NSObject()
            let block: @convention(block) (UIView, CALayer) -> Void = { [weak self] view, layer in
                let isMainThread = Thread.isMainThread
                if !isMainThread {
                    // UIKit can throw inside the original call, before our notification is reached.
                    self?.warnAboutBackgroundLayout()
                }
                forward(view, selector, layer)
                if isMainThread {
                    self?.layoutSubviews(token: token)
                } else {
                    DispatchQueue.main.async { [weak self] in
                        self?.layoutSubviews(token: token)
                    }
                }
            }
            let hook = LayoutHook(original: original, replacement: imp_implementationWithBlock(block), token: token)
            // In-flight dispatches and other swizzlers can retain the IMP after unsubscribe.
            // Keep it valid and reuse it rather than allocating a new block on every restart.
            layoutHooks[key] = hook
            return hook
        }

        private func layoutSubviews(token: NSObject) {
            // An older hook may still be in another swizzler's call chain.
            guard activeLayoutLock.withLock({ activeLayoutToken === token }) else { return }
            onViewLayout.invoke(())
        }

        #if TESTING
            func simulateLayoutSubviews() {
                onViewLayout.invoke(())
            }

            func resetBackgroundLayoutWarning() {
                backgroundLayoutWarningLock.withLock {
                    hasWarnedAboutBackgroundLayout = false
                }
            }
        #endif
    }
#endif
