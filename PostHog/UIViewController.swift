//
//  UIViewController.swift
//  PostHog
//
// Inspired by
// https://raw.githubusercontent.com/segmentio/analytics-swift/e613e09aa1b97144126a923ec408374f914a6f2e/Examples/other_plugins/UIKitScreenTracking.swift
//
//  Created by Manoel Aranda Neto on 23.10.23.
//

#if os(iOS) || os(tvOS)
    import Foundation
    import UIKit

    extension UIViewController {
        class func ph_topViewController(base: UIViewController? = UIApplication.getCurrentWindow()?.rootViewController) -> UIViewController? {
            if let nav = base as? UINavigationController {
                return ph_topViewController(base: nav.visibleViewController)
            } else if let tab = base as? UITabBarController, let selected = tab.selectedViewController {
                return ph_topViewController(base: selected)
            } else if let presented = base?.presentedViewController {
                return ph_topViewController(base: presented)
            } else if let split = base as? UISplitViewController, let screen = splitScreen(split) {
                return screen
            }

            guard let base, let containerView = base.viewIfLoaded, let window = containerView.window else {
                return base
            }

            // Custom containers have no selected/visibleViewController API. Only
            // descend when one child is unambiguously visible; keep the container
            // name for multi-pane layouts and overlapping transition views.
            let visibleChildren = base.children.filter { child in
                guard let childView = child.viewIfLoaded,
                      childView.window === window,
                      childView.isDescendant(of: containerView)
                else {
                    return false
                }

                return isViewVisible(childView, in: window)
            }
            if visibleChildren.count == 1 {
                return ph_topViewController(base: visibleChildren[0])
            }
            return base
        }

        private enum SplitLayout {
            case collapsed, expanded, transitioning
        }

        /// Rotating or unfolding re-lays out a split's columns one at a time, so
        /// mid-change it can show a single column it is about to hide or join:
        /// on a foldable, SwiftUI shows one column while the window is still at its
        /// folded width; UIKit reports collapsed after its size class is already
        /// regular; and during rotation the split carries its own layout
        /// transition coordinator while it still reports collapsed and compact.
        private static func splitLayout(_ split: UISplitViewController) -> SplitLayout {
            // A split also inherits the coordinator of a push or presentation
            // around it. Those move between two view controllers; the split's
            // own layout change has neither.
            if let coordinator = split.transitionCoordinator,
               coordinator.viewController(forKey: .from) == nil,
               coordinator.viewController(forKey: .to) == nil
            {
                return .transitioning
            }
            guard split.isCollapsed else { return .expanded }
            return split.traitCollection.horizontalSizeClass == .compact ? .collapsed : .transitioning
        }

        /// The screen a split shows, or nil to find its one visible column like
        /// any other container.
        private static func splitScreen(_ split: UISplitViewController) -> UIViewController? {
            switch splitLayout(split) {
            case .transitioning:
                return split
            case .collapsed:
                return nil
            case .expanded:
                // Several columns keep the container name, like the custom
                // containers in ph_topViewController.
                guard split.displayMode == .secondaryOnly, let secondary = secondaryViewController(of: split) else {
                    return split
                }
                return ph_topViewController(base: secondary)
            }
        }

        private static func secondaryViewController(of split: UISplitViewController) -> UIViewController? {
            if split.style != .unspecified {
                let secondary = split.viewController(for: .secondary)
                // Column-style splits wrap a plain column controller in a navigation
                // controller that holds the pushed screens. `navigationController` can also
                // find an app navigation controller outside the split, so only take the split's own.
                if let wrapper = secondary?.navigationController, wrapper.parent === split { return wrapper }
                return secondary
            }
            return split.viewControllers.last
        }

        private static func isViewVisible(_ childView: UIView, in window: UIWindow) -> Bool {
            guard !childView.bounds.isEmpty else { return false }
            var visibleRect = childView.convert(childView.bounds, to: window).intersection(window.bounds)
            guard !visibleRect.isEmpty else { return false }

            // Check the whole ancestor chain: attached paging views can be
            // offscreen or clipped, even when they are not hidden/transparent.
            var view: UIView? = childView
            while let current = view {
                if current.isHidden || current.alpha <= 0 {
                    return false
                }
                if current.clipsToBounds {
                    visibleRect = visibleRect.intersection(current.convert(current.bounds, to: window))
                    if visibleRect.isEmpty { return false }
                }
                if current === window { break }
                view = current.superview
            }
            return true
        }

        static func getViewControllerName(_ viewController: UIViewController) -> String? {
            var title: String? = String(describing: viewController.classForCoder).replacingOccurrences(of: "ViewController", with: "")

            // Plain storyboard controllers have no meaningful class name (stripping
            // "ViewController" from "UIViewController" would otherwise leave "UI").
            if title?.isEmpty == true || viewController.classForCoder == UIViewController.self {
                title = viewController.title ?? nil
            }

            return title
        }
    }
#endif
