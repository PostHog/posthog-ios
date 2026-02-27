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
        #endif
    }

    extension UIView {
        @objc func ph_swizzled_layoutSublayers(of layer: CALayer) {
            ph_swizzled_layoutSublayers(of: layer) // call original, not altering execution logic
            ApplicationViewLayoutPublisher.shared.layoutSubviews()
        }
    }
#endif
