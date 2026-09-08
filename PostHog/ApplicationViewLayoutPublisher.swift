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
            // Core Animation can call `layoutSublayers(of:)` on a background thread when it commits a
            // thread-local transaction during thread cleanup (`CA::Transaction::release_thread`).
            // UIKit's implementation is main-thread only: it runs Auto Layout, and `NSISEngine` raises
            // `NSInternalInconsistencyException` off the main thread, which terminates the host app.
            // Do not forward the call here. Mark the layer instead, so the layout pass and the
            // notification both run on the main thread on the next Core Animation commit.
            guard Thread.isMainThread else {
                DispatchQueue.main.async { layer.setNeedsLayout() }
                return
            }

            ph_swizzled_layoutSublayers(of: layer) // call original, not altering execution logic
            ApplicationViewLayoutPublisher.shared.layoutSubviews()
        }
    }
#endif
