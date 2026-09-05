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

                // A child's view may be inside a hidden or transparent wrapper.
                var view: UIView? = childView
                while let current = view, current !== containerView {
                    if current.isHidden || current.alpha <= 0 {
                        return false
                    }
                    view = current.superview
                }
                return true
            }
            if visibleChildren.count == 1 {
                return ph_topViewController(base: visibleChildren[0])
            }
            return base
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
