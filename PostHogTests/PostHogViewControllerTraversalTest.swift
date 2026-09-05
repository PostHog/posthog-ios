//
//  PostHogViewControllerTraversalTest.swift
//  PostHogTests
//

#if os(iOS) || os(tvOS)
    @testable import PostHog
    import Testing
    import UIKit

    @Suite("Screen view controller traversal", .serialized)
    @MainActor
    struct PostHogViewControllerTraversalTest {
        private final class InitialViewController: UIViewController {}
        private final class OneViewController: UIViewController {}
        private final class TwoViewController: UIViewController {}
        private final class ThreeViewController: UIViewController {}

        private func add(_ child: UIViewController, to parent: UIViewController) {
            parent.addChild(child)
            parent.view.addSubview(child.view)
            child.view.frame = parent.view.bounds
            child.didMove(toParent: parent)
        }

        private func withWindow(root: UIViewController, body: (UIWindow) throws -> Void) rethrows {
            let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
            window.rootViewController = root
            window.isHidden = false
            defer {
                window.isHidden = true
                window.rootViewController = nil
            }
            try body(window)
        }

        @Test("Screen autocapture follows navigation inside a custom container", arguments: [false, true], [false, true])
        func capturesNavigationScreens(customContainer: Bool, titledControllers: Bool) {
            let navigation = UINavigationController(rootViewController: OneViewController())
            let root: UIViewController
            if customContainer {
                root = InitialViewController()
                add(navigation, to: root)
            } else {
                root = navigation
            }

            withWindow(root: root) { window in
                var names: [String] = []
                ApplicationScreenViewPublisher.shared.startAutoCapture { names.append($0) }
                defer { ApplicationScreenViewPublisher.shared.stopAutoCapture() }

                let screens: [(UIViewController, String)] = [
                    (OneViewController(), "One"),
                    (TwoViewController(), "Two"),
                    (ThreeViewController(), "Three"),
                ]
                for (customScreen, name) in screens {
                    // The issue's storyboard uses plain UIViewControllers with titles.
                    // Custom classes should continue to take precedence over titles.
                    let screen = titledControllers ? UIViewController() : customScreen
                    screen.title = titledControllers ? name : "Custom title"
                    navigation.setViewControllers([screen], animated: false)
                    navigation.view.layoutIfNeeded()
                    #expect(screen.view.window === window)
                    names.removeAll()
                    // Exercise the real swizzle without relying on transition timing.
                    screen.viewDidAppear(false)
                    #expect(names == [name])
                    #expect(UIViewController.ph_topViewController(base: root) === screen)
                }
            }
        }

        @Test("Nested custom containers preserve selected tab and navigation behavior")
        func nestedContainers() {
            let root = InitialViewController()
            let nested = InitialViewController()
            let screen = OneViewController()
            let navigation = UINavigationController(rootViewController: screen)
            let tabs = UITabBarController()
            tabs.viewControllers = [TwoViewController(), navigation]
            tabs.selectedIndex = 1
            add(nested, to: root)
            add(tabs, to: nested)

            withWindow(root: root) { _ in
                #expect(UIViewController.ph_topViewController(base: root) === screen)
                tabs.selectedIndex = 0
                #expect(UIViewController.ph_topViewController(base: root) === tabs.selectedViewController)
            }
        }

        @Test("Custom containers follow replacement children")
        func replacesChild() {
            let root = InitialViewController()
            let first = OneViewController()
            let second = TwoViewController()
            add(first, to: root)

            withWindow(root: root) { _ in
                #expect(UIViewController.ph_topViewController(base: root) === first)
                first.willMove(toParent: nil)
                first.view.removeFromSuperview()
                first.removeFromParent()
                add(second, to: root)
                #expect(UIViewController.ph_topViewController(base: root) === second)
            }
        }

        @Test("Multiple visible children keep the container name")
        func ambiguousChildren() {
            let root = InitialViewController()
            add(OneViewController(), to: root)
            add(TwoViewController(), to: root)
            withWindow(root: root) { _ in
                #expect(UIViewController.ph_topViewController(base: root) === root)
            }
        }

        @Test("Inactive children are ignored", arguments: ["hidden", "transparent", "detached", "unloaded", "hidden ancestor"])
        func ignoresInactiveChildren(state: String) {
            let root = InitialViewController()
            let visible = OneViewController()
            let inactive = TwoViewController()
            add(visible, to: root)
            if state == "unloaded" {
                root.addChild(inactive)
                inactive.didMove(toParent: root)
            } else {
                add(inactive, to: root)
                switch state {
                case "hidden": inactive.view.isHidden = true
                case "transparent": inactive.view.alpha = 0
                case "detached": inactive.view.removeFromSuperview()
                case "hidden ancestor":
                    let wrapper = UIView(frame: root.view.bounds)
                    root.view.addSubview(wrapper)
                    wrapper.addSubview(inactive.view)
                    wrapper.isHidden = true
                default: break
                }
            }

            withWindow(root: root) { _ in
                #expect(UIViewController.ph_topViewController(base: root) === visible)
                if state == "unloaded" {
                    #expect(!inactive.isViewLoaded)
                }
                visible.view.isHidden = true
                #expect(UIViewController.ph_topViewController(base: root) === root)
            }
        }

        @Test("Offscreen, empty, and clipped children are ignored", arguments: ["offscreen", "zero width", "zero height", "clipped ancestor"])
        func ignoresInvisibleGeometry(state: String) {
            let root = InitialViewController()
            withWindow(root: root) { window in
                let inactive = TwoViewController()
                add(inactive, to: root)
                switch state {
                case "offscreen":
                    inactive.view.frame = root.view.bounds.offsetBy(dx: window.bounds.width, dy: 0)
                case "zero width":
                    inactive.view.frame = CGRect(x: 0, y: 0, width: 0, height: 50)
                case "zero height":
                    inactive.view.frame = CGRect(x: 0, y: 0, width: 50, height: 0)
                case "clipped ancestor":
                    let wrapper = UIView(frame: CGRect(x: 20, y: 20, width: 50, height: 50))
                    wrapper.clipsToBounds = true
                    root.view.addSubview(wrapper)
                    wrapper.addSubview(inactive.view)
                    // Still inside the window, but outside the clipping wrapper.
                    inactive.view.frame = CGRect(x: 80, y: 0, width: 20, height: 20)
                default: break
                }
                #expect(inactive.view.window === window)
                #expect(UIViewController.ph_topViewController(base: root) === root)

                let visible = OneViewController()
                add(visible, to: root)
                #expect(UIViewController.ph_topViewController(base: root) === visible)
            }
        }

        @Test("Partially visible children remain eligible", arguments: [false, true])
        func partiallyVisibleChild(clippedByWrapper: Bool) {
            let root = InitialViewController()
            withWindow(root: root) { window in
                let child = OneViewController()
                add(child, to: root)
                if clippedByWrapper {
                    let wrapper = UIView(frame: CGRect(x: 20, y: 20, width: 50, height: 50))
                    wrapper.clipsToBounds = true
                    root.view.addSubview(wrapper)
                    wrapper.addSubview(child.view)
                    child.view.frame = CGRect(x: 40, y: 0, width: 20, height: 20)
                } else {
                    child.view.frame = CGRect(x: window.bounds.width - 10, y: 0, width: 20, height: 20)
                }
                #expect(UIViewController.ph_topViewController(base: root) === child)
            }
        }

        @Test("Overflow is visible only when its ancestor does not clip", arguments: [false, true])
        func respectsAncestorClipping(clips: Bool) {
            let root = InitialViewController()
            withWindow(root: root) { _ in
                let child = OneViewController()
                add(child, to: root)
                let wrapper = UIView(frame: CGRect(x: 20, y: 20, width: 50, height: 50))
                wrapper.clipsToBounds = clips
                // Exercise bounds conversion as used by scrolling containers.
                wrapper.bounds.origin.x = 30
                root.view.addSubview(wrapper)
                wrapper.addSubview(child.view)
                child.view.frame = CGRect(x: 90, y: 0, width: 20, height: 20)
                #expect(UIViewController.ph_topViewController(base: root) === (clips ? root : child))
            }
        }

        @Test("Presented controllers still take precedence over custom children")
        func presentedController() {
            let root = InitialViewController()
            add(OneViewController(), to: root)
            let presented = TwoViewController()
            withWindow(root: root) { _ in
                root.present(presented, animated: false)
                defer { root.dismiss(animated: false) }
                #expect(root.presentedViewController === presented)
                #expect(UIViewController.ph_topViewController(base: root) === presented)
            }
        }

        @Test("Traversal does not load detached controller views")
        func detachedController() {
            let root = InitialViewController()
            let child = OneViewController()
            root.addChild(child)
            child.didMove(toParent: root)
            #expect(UIViewController.ph_topViewController(base: root) === root)
            #expect(!root.isViewLoaded)
            #expect(!child.isViewLoaded)
            #expect(UIViewController.ph_topViewController(base: nil) == nil)
        }
    }
#endif
