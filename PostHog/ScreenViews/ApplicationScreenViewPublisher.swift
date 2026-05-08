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
    /// Fanout for screen changes — fired by `PostHogSDK.screen()` (which
    /// covers both manual calls and the SwiftUI `.postHogScreenView`
    /// modifier). Subscribers must not re-enter `screen()` from the callback.
    var onScreenView: PostHogMulticastCallback<String> { get }

    /// Owned by `PostHogScreenViewIntegration`; activates the
    /// `viewDidAppear` swizzle and routes each visible-VC name to `handler`.
    /// Idempotent.
    func startAutoCapture(_ handler: @escaping (String) -> Void)
    func stopAutoCapture()
}

final class ApplicationScreenViewPublisher: ScreenViewPublishing {
    static let shared = ApplicationScreenViewPublisher()
    private init() {}

    private(set) lazy var onScreenView = PostHogMulticastCallback<String>()

    private let handlerLock = NSLock()
    private var autoCaptureHandler: ((String) -> Void)?
    private var hasSwizzled: Bool = false

    func startAutoCapture(_ handler: @escaping (String) -> Void) {
        handlerLock.withLock { autoCaptureHandler = handler }
        swizzleViewDidAppear()
    }

    func stopAutoCapture() {
        unswizzleViewDidAppear()
        handlerLock.withLock { autoCaptureHandler = nil }
    }

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

        // Called from swizzled `viewDidAppearOverride`. Hands the visible
        // VC's name to the integration's handler, which calls screen() — that
        // is what fans out via onScreenView. Going direct (not via
        // onScreenView) keeps the auto-capture path loop-free.
        fileprivate func viewDidAppear(in viewController: UIViewController?) {
            // ignore views from keyboard window
            guard let window = viewController?.viewIfLoaded?.window, !window.isKeyboardWindow else {
                return
            }

            guard let top = findVisibleViewController(viewController) else { return }

            guard let name = UIViewController.getViewControllerName(top) else { return }

            let handler = handlerLock.withLock { autoCaptureHandler }
            handler?(name)
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
