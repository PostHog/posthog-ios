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
            } else if let split = base as? UISplitViewController, !isShowingOneColumn(split) {
                // An expanded split shows several columns, so it keeps the container
                // name, like other multi-pane containers below.
                return split
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

        /// Rotating or unfolding re-lays out a split's columns one at a time, so
        /// mid-change it can show a single column it is about to hide or join.
        /// Treat it as collapsed only once it has settled on one column.
        private static func isShowingOneColumn(_ split: UISplitViewController) -> Bool {
            guard split.isCollapsed, split.traitCollection.horizontalSizeClass == .compact else {
                return false
            }
            // A presentation coordinator carries a modal style; the split's own
            // layout change uses `.none`.
            if let coordinator = split.transitionCoordinator, coordinator.presentationStyle == .none {
                return false
            }
            return true
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
