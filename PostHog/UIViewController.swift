//
//  UIViewController.swift
//  PostHog
//
// Inspired by
// https://raw.githubusercontent.com/segmentio/analytics-swift/e613e09aa1b97144126a923ec408374f914a6f2e/Examples/other_plugins/UIKitScreenTracking.swift
//
//  Created by Manoel Aranda Neto on 23.10.23.
//

import Foundation
#if os(iOS) || os(tvOS)
    import UIKit

    extension UIViewController {
        static func swizzleScreenView() {
            swizzle(forClass: UIViewController.self,
                    original: #selector(UIViewController.viewDidAppear(_:)),
                    new: #selector(UIViewController.viewDidApperOverride))
        }

        static func unswizzleScreenView() {
            swizzle(forClass: UIViewController.self,
                    original: #selector(UIViewController.viewDidApperOverride),
                    new: #selector(UIViewController.viewDidAppear(_:)))
        }

        private func activeController() -> UIViewController? {
            // if a view is being dismissed, this will return nil
            if let root = viewIfLoaded?.window?.rootViewController {
                return root
            } else {
                // preferred way to get active controller in ios 13+
                for scene in UIApplication.shared.connectedScenes where scene.activationState == .foregroundActive {
                    let windowScene = scene as? UIWindowScene
                    let sceneDelegate = windowScene?.delegate as? UIWindowSceneDelegate
                    if let target = sceneDelegate, let window = target.window {
                        return window?.rootViewController
                    }
                }
            }
            return nil
        }

        static func getViewControllerName(_ viewController: UIViewController) -> String? {
            var title: String? = String(describing: viewController.classForCoder).replacingOccurrences(of: "ViewController", with: "")

            if title?.isEmpty == true {
                title = viewController.title ?? nil
            }

            return title
        }

        private func captureScreenView(_ window: UIWindow?) {
            var rootController = window?.rootViewController
            if rootController == nil {
                rootController = activeController()
            }
            guard let top = findVisibleViewController(activeController()) else { return }

            let name = UIViewController.getViewControllerName(top)

            if let name = name {
                PostHogSDK.shared.screen(name)
            }
        }

        @objc func viewDidApperOverride(animated: Bool) {
            captureScreenView(viewIfLoaded?.window)
            // it looks like we're calling ourselves, but we're actually
            // calling the original implementation of viewDidAppear since it's been swizzled.
            viewDidApperOverride(animated: animated)
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
    }
#endif
