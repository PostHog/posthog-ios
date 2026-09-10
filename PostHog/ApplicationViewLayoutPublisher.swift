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

        private(set) lazy var onViewLayout = PostHogThrottledMulticastCallback<Void> { [weak self] subscriberCount in
            if subscriberCount > 0 {
                self?.swizzleLayoutSubviews()
            } else {
                self?.unswizzleLayoutSubviews()
            }
        }

        private var hasSwizzled: Bool = false
        private let backgroundLayoutWarningLock = NSLock()
        private var hasWarnedAboutBackgroundLayout = false

        fileprivate func warnAboutBackgroundLayout() {
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
            guard !hasSwizzled else { return }
            hasSwizzled = true

            swizzle(
                forClass: UIView.self,
                original: #selector(UIView.layoutSublayers(of:)),
                new: #selector(UIView.ph_swizzled_layoutSublayers(of:))
            )
        }

        private func unswizzleLayoutSubviews() {
            guard hasSwizzled else { return }
            hasSwizzled = false

            // swizzling twice will exchange implementations back to original
            swizzle(
                forClass: UIView.self,
                original: #selector(UIView.layoutSublayers(of:)),
                new: #selector(UIView.ph_swizzled_layoutSublayers(of:))
            )
        }

        // Called from swizzled `UIView.layoutSubviews`
        fileprivate func layoutSubviews() {
            onViewLayout.invoke(())
        }

        #if TESTING
            func simulateLayoutSubviews() {
                layoutSubviews()
            }

            func resetBackgroundLayoutWarning() {
                backgroundLayoutWarningLock.withLock {
                    hasWarnedAboutBackgroundLayout = false
                }
            }
        #endif
    }

    extension UIView {
        @objc func ph_swizzled_layoutSublayers(of layer: CALayer) {
            let isMainThread = Thread.isMainThread
            if !isMainThread {
                // UIKit can throw inside the original call, before our notification is reached.
                ApplicationViewLayoutPublisher.shared.warnAboutBackgroundLayout()
            }
            ph_swizzled_layoutSublayers(of: layer) // call original, not altering execution logic
            if isMainThread {
                ApplicationViewLayoutPublisher.shared.layoutSubviews()
            } else {
                DispatchQueue.main.async {
                    ApplicationViewLayoutPublisher.shared.layoutSubviews()
                }
            }
        }
    }
#endif
