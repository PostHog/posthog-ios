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

typealias ScreenViewHandler = (String) -> Void

protocol ScreenViewPublishing: AnyObject {
    /// Registers a callback for a view appeared event
    func onScreenView(_ callback: @escaping ScreenViewHandler) -> RegistrationToken
}

final class ApplicationScreenViewPublisher: BaseScreenViewPublisher {
    static let shared = ApplicationScreenViewPublisher()

    private var hasSwizzled: Bool = false

    func start() {
        // no-op if not UIKit
        #if os(iOS) || os(tvOS)
            swizzleViewDidAppear()
        #endif
    }

    func stop() {
        // no-op if not UIKit
        #if os(iOS) || os(tvOS)
            unswizzleViewDidAppear()
        #endif
    }

    override func onScreenView(_ callback: @escaping ScreenViewHandler) -> RegistrationToken {
        let id = UUID()
        registrationLock.withLock {
            self.onScreenViewCallbacks[id] = callback
        }

        // start on first callback registration
        if !hasSwizzled {
            start()
        }

        return RegistrationToken { [weak self] in
            // Registration token deallocated here
            guard let self else { return }
            let handlerCount = self.registrationLock.withLock {
                self.onScreenViewCallbacks[id] = nil
                return self.onScreenViewCallbacks.values.count
            }
            // stop when there are no more callbacks
            if handlerCount <= 0 {
                stop()
            }
        }
    }

    #if os(iOS) || os(tvOS)
        func swizzleViewDidAppear() {
            guard !hasSwizzled else { return }
            hasSwizzled = true
            swizzle(
                forClass: UIViewController.self,
                original: #selector(UIViewController.viewDidAppear(_:)),
                new: #selector(UIViewController.viewDidAppearOverride)
            )
        }

        func unswizzleViewDidAppear() {
            guard hasSwizzled else { return }
            hasSwizzled = false
            swizzle(
                forClass: UIViewController.self,
                original: #selector(UIViewController.viewDidAppearOverride),
                new: #selector(UIViewController.viewDidAppear(_:))
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
                notifyHandlers(screen: name)
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
    #endif
}

class BaseScreenViewPublisher: ScreenViewPublishing {
    fileprivate let registrationLock = NSLock()

    var onScreenViewCallbacks: [UUID: ScreenViewHandler] = [:]

    func onScreenView(_ callback: @escaping ScreenViewHandler) -> RegistrationToken {
        let id = UUID()
        registrationLock.withLock {
            self.onScreenViewCallbacks[id] = callback
        }

        return RegistrationToken { [weak self] in
            // Registration token deallocated here
            guard let self else { return }
            self.registrationLock.withLock {
                self.onScreenViewCallbacks[id] = nil
            }
        }
    }

    func notifyHandlers(screen: String) {
        let handlers = registrationLock.withLock { onScreenViewCallbacks.values }
        for handler in handlers {
            notifyHander(handler, screen: screen)
        }
    }

    private func notifyHander(_ handler: @escaping ScreenViewHandler, screen: String) {
        if Thread.isMainThread {
            handler(screen)
        } else {
            DispatchQueue.main.async { handler(screen) }
        }
    }
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
