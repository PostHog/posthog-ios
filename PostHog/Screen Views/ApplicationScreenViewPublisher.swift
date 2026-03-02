//
//  ApplicationScreenViewPublisher.swift
//  PostHog
//
//  Created by Ioannis Josephides on 20/02/2025.
//

import Foundation

#if os(iOS) || os(tvOS)
    import UIKit
#endif

protocol ScreenViewPublishing: AnyObject {
    /// Registers a callback for a view appeared event
    var onScreenView: PostHogMulticastCallback<String> { get }
}

final class ApplicationScreenViewPublisher: ScreenViewPublishing {
    private(set) lazy var onScreenView = PostHogMulticastCallback<String> { [weak self] subscriberCount in
        if subscriberCount > 0 {
            self?.swizzleViewDidAppear()
        } else {
            self?.unswizzleViewDidAppear()
        }
    }

    static let shared = ApplicationScreenViewPublisher()

    private var hasSwizzled: Bool = false

    #if os(iOS) || os(tvOS)
        private func swizzleViewDidAppear() {
            guard !hasSwizzled else { return }
            hasSwizzled = true
            swizzle(
                forClass: UIViewController.self,
                original: #selector(UIViewController.viewDidAppear(_:)),
                new: #selector(UIViewController.viewDidAppearOverride)
            )
        }

        private func unswizzleViewDidAppear() {
            guard hasSwizzled else { return }
            hasSwizzled = false

            // swizzling twice will exchange implementations back to original
            swizzle(
                forClass: UIViewController.self,
                original: #selector(UIViewController.viewDidAppear(_:)),
                new: #selector(UIViewController.viewDidAppearOverride)
            )
        }

        // Called from swizzled `viewDidAppearOverride`
        fileprivate func viewDidAppear(in viewController: UIViewController?) {
            // ignore views from keyboard window
            guard let window = viewController?.viewIfLoaded?.window, !window.isKeyboardWindow else {
                return
            }

            guard let top = findVisibleViewController(viewController) else { return }

            if let name = UIViewController.getViewControllerName(top) {
                onScreenView.invoke(name)
            }
        }

        private func findVisibleViewController(_ controller: UIViewController?) -> UIViewController? {
            if let navigationController = controller as? UINavigationController {
                return findVisibleViewController(navigationController.visibleViewController)
            }
            if let tabController = controller as? UITabBarController {
                if let selected = tabController.selectedViewController {
                    return findVisibleViewController(selected)
                }
            }
            if let presented = controller?.presentedViewController {
                return findVisibleViewController(presented)
            }
            return controller
        }
    #else
        private func swizzleViewDidAppear() {
            // no-op if not UIKit
        }

        private func unswizzleViewDidAppear() {
            // no-op if not UIKit
        }
    #endif
}

#if os(iOS) || os(tvOS)
    private extension UIViewController {
        @objc func viewDidAppearOverride(animated: Bool) {
            ApplicationScreenViewPublisher.shared.viewDidAppear(in: activeController)

            // it looks like we're calling ourselves, but we're actually
            // calling the original implementation of viewDidAppear since it's been swizzled.
            viewDidAppearOverride(animated: animated)
        }

        private var activeController: UIViewController? {
            // if a view is being dismissed, this will return nil
            if let root = viewIfLoaded?.window?.rootViewController {
                return root
            }
            // TODO: handle container controllers (see ph_topViewController)
            return UIApplication.getCurrentWindow()?.rootViewController
        }
    }
#endif
