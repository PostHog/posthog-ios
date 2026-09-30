//
//  PostHogViewControllerTraversalTest.swift
//  PostHogTests
//

#if os(iOS) || os(tvOS)
    @testable import PostHog
    import SwiftUI
    import Testing
    import UIKit

    private struct PlainView: View {
        var body: some View { EmptyView() }
    }

    private struct OtherView: View {
        var body: some View { EmptyView() }
    }

    // An if/else root, e.g. home or login, is hosted as `_ConditionalContent<…>`.
    @ViewBuilder private func conditionalRoot(_ plain: Bool) -> some View {
        if plain { PlainView() } else { OtherView() }
    }

    @Suite("Screen view controller traversal", .serialized)
    @MainActor
    struct PostHogViewControllerTraversalTest {
        private final class InitialViewController: UIViewController {}
        private final class OneViewController: UIViewController {}
        private final class TwoViewController: UIViewController {}
        private final class ThreeViewController: UIViewController {}
        private final class SplitViewController: UISplitViewController {
            var reportsCollapsed = false
            var displayModeOverride: UISplitViewController.DisplayMode?
            var stubCoordinator: UIViewControllerTransitionCoordinator?
            override var isCollapsed: Bool { reportsCollapsed || super.isCollapsed }
            override var displayMode: UISplitViewController.DisplayMode { displayModeOverride ?? super.displayMode }
            override var transitionCoordinator: UIViewControllerTransitionCoordinator? { stubCoordinator ?? super.transitionCoordinator }
        }

        private final class StubTransitionCoordinator: NSObject, UIViewControllerTransitionCoordinator {
            private let from: UIViewController?
            private let to: UIViewController?
            init(from: UIViewController? = nil, to: UIViewController? = nil) {
                self.from = from
                self.to = to
            }

            var presentationStyle: UIModalPresentationStyle { .none }
            var isAnimated: Bool { true }
            var initiallyInteractive: Bool { false }
            var isInterruptible: Bool { false }
            var isInteractive: Bool { false }
            var isCancelled: Bool { false }
            var transitionDuration: TimeInterval { 0.3 }
            var percentComplete: CGFloat { 0 }
            var completionVelocity: CGFloat { 1 }
            var completionCurve: UIView.AnimationCurve { .easeInOut }
            var containerView: UIView { UIView() }
            var targetTransform: CGAffineTransform { .identity }
            func viewController(forKey key: UITransitionContextViewControllerKey) -> UIViewController? {
                key == .from ? from : key == .to ? to : nil
            }
            func view(forKey _: UITransitionContextViewKey) -> UIView? {
                nil
            }
            func animate(alongsideTransition _: ((UIViewControllerTransitionCoordinatorContext) -> Void)?, completion _: ((UIViewControllerTransitionCoordinatorContext) -> Void)? = nil) -> Bool {
                false
            }
            func animateAlongsideTransition(in _: UIView?, animation _: ((UIViewControllerTransitionCoordinatorContext) -> Void)?, completion _: ((UIViewControllerTransitionCoordinatorContext) -> Void)? = nil) -> Bool {
                false
            }
            func notifyWhenInteractionEnds(_: @escaping (UIViewControllerTransitionCoordinatorContext) -> Void) {}
            func notifyWhenInteractionChanges(_: @escaping (UIViewControllerTransitionCoordinatorContext) -> Void) {}
        }

        /// A classic split with plain column controllers, hosted in a container
        /// that forces its horizontal size class.
        private func makeSplit(sizeClass: UIUserInterfaceSizeClass) -> (root: UIViewController, split: SplitViewController, primary: UIViewController, secondary: UIViewController) {
            let root = InitialViewController()
            let split = SplitViewController()
            let primary = OneViewController()
            let secondary = TwoViewController()
            split.viewControllers = [primary, secondary]
            add(split, to: root)
            root.setOverrideTraitCollection(UITraitCollection(horizontalSizeClass: sizeClass), forChild: split)
            return (root, split, primary, secondary)
        }

        private func add(_ child: UIViewController, to parent: UIViewController) {
            parent.addChild(child)
            parent.view.addSubview(child.view)
            child.view.frame = parent.view.bounds
            child.didMove(toParent: parent)
        }

        private func withWindow(root: UIViewController, width: CGFloat = 390, body: (UIWindow) throws -> Void) rethrows {
            let window = UIWindow(frame: CGRect(x: 0, y: 0, width: width, height: 844))
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
                    names.removeAll()
                    navigation.setViewControllers([screen], animated: false)
                    navigation.view.layoutIfNeeded()
                    #expect(screen.view.window === window)
                    // Exercise the real swizzle without relying on transition timing.
                    // A repeated appearance of the same screen is captured once.
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

        @Test("Repeated appearances of the same screen are captured once")
        func deduplicatesRepeatedAppearances() {
            let first = OneViewController()
            let navigation = UINavigationController(rootViewController: first)

            withWindow(root: navigation) { _ in
                var names: [String] = []
                ApplicationScreenViewPublisher.shared.startAutoCapture { names.append($0) }
                defer { ApplicationScreenViewPublisher.shared.stopAutoCapture() }
                navigation.view.layoutIfNeeded()

                // A size-class change re-runs viewDidAppear on containers and children.
                navigation.viewDidAppear(false)
                first.viewDidAppear(false)
                first.viewDidAppear(false)
                #expect(names == ["One"])

                // A new controller with the same name is still a navigation.
                let second = OneViewController()
                navigation.setViewControllers([first, second], animated: false)
                navigation.view.layoutIfNeeded()
                second.viewDidAppear(false)
                #expect(names == ["One", "One"])

                // Returning to an earlier screen is captured again.
                navigation.setViewControllers([first], animated: false)
                navigation.view.layoutIfNeeded()
                first.viewDidAppear(false)
                #expect(names == ["One", "One", "One"])
            }
        }

        @Test("Returning from an unnamed screen captures the earlier screen again")
        func returnsFromUnnamedScreen() {
            let first = OneViewController()
            let navigation = UINavigationController(rootViewController: first)

            withWindow(root: navigation) { _ in
                var names: [String] = []
                ApplicationScreenViewPublisher.shared.startAutoCapture { names.append($0) }
                defer { ApplicationScreenViewPublisher.shared.stopAutoCapture() }
                navigation.view.layoutIfNeeded()
                first.viewDidAppear(false)
                #expect(names == ["One"])

                let untitled = UIViewController()
                #expect(UIViewController.getViewControllerName(untitled) == nil)
                navigation.pushViewController(untitled, animated: false)
                navigation.view.layoutIfNeeded()
                untitled.viewDidAppear(false)
                #expect(names == ["One"])

                navigation.popViewController(animated: false)
                navigation.view.layoutIfNeeded()
                first.viewDidAppear(false)
                #expect(names == ["One", "One"])
            }
        }

        @Test("Returning from a full-screen presentation captures the earlier screen again")
        func returnsFromFullScreenPresentation() {
            let first = OneViewController()
            let navigation = UINavigationController(rootViewController: first)

            withWindow(root: navigation) { window in
                var names: [String] = []
                ApplicationScreenViewPublisher.shared.startAutoCapture { names.append($0) }
                defer { ApplicationScreenViewPublisher.shared.stopAutoCapture() }
                navigation.view.layoutIfNeeded()
                first.viewDidAppear(false)
                #expect(names == ["One"])

                // A full-screen presentation puts the presented view in the window
                // and takes the root's view out, which UIKit only does after the
                // transition; do the same by hand.
                let presented = TwoViewController()
                window.addSubview(presented.view)
                navigation.view.removeFromSuperview()
                presented.viewDidAppear(false)
                #expect(names == ["One"])

                presented.view.removeFromSuperview()
                window.addSubview(navigation.view)
                first.viewDidAppear(false)
                #expect(names == ["One", "One"])
            }
        }

        @Test("Collapsed split views resolve to their visible column unless mid-layout", arguments: ["none", "navigation", "appearing", "layout"])
        func collapsedSplitView(transition: String) {
            let (root, split, primary, _) = makeSplit(sizeClass: .compact)
            switch transition {
            // A push or presentation moves between two view controllers.
            case "navigation": split.stubCoordinator = StubTransitionCoordinator(from: InitialViewController(), to: root)
            case "appearing": split.stubCoordinator = StubTransitionCoordinator(to: root)
            // Rotation: the split's own layout transition has neither.
            case "layout": split.stubCoordinator = StubTransitionCoordinator()
            default: break
            }

            withWindow(root: root, width: 1024) { _ in
                root.view.layoutIfNeeded()
                #expect(split.isCollapsed)
                let expected: UIViewController = transition == "layout" ? split : primary
                #expect(UIViewController.ph_topViewController(base: root) === expected)
            }
        }

        @Test("Expanded split views follow a lone secondary column", arguments: [
            UISplitViewController.DisplayMode.oneBesideSecondary,
            .oneOverSecondary,
            .secondaryOnly,
        ])
        func expandedSplitView(displayMode: UISplitViewController.DisplayMode) {
            let (root, split, _, secondary) = makeSplit(sizeClass: .regular)
            split.displayModeOverride = displayMode

            withWindow(root: root, width: 1024) { _ in
                root.view.layoutIfNeeded()
                #expect(!split.isCollapsed)
                let expected: UIViewController = displayMode == .secondaryOnly ? secondary : split
                #expect(UIViewController.ph_topViewController(base: root) === expected)
            }
        }

        @Test("Split views keep the container name while expanding")
        func expandingSplitView() {
            let (root, split, primary, secondary) = makeSplit(sizeClass: .regular)
            // UIKit re-shows columns before it reports being expanded.
            split.reportsCollapsed = true

            withWindow(root: root, width: 1024) { _ in
                root.view.layoutIfNeeded()
                // Unfolding lays the columns out one at a time, so at first only
                // one column is on screen.
                primary.view.isHidden = true
                #expect(secondary.view.window != nil)
                #expect(UIViewController.ph_topViewController(base: root) === split)
            }
        }

        @Test("Screen autocapture follows navigation in a split view showing only its secondary column", arguments: ["classic", "column", "wrapped column", "nested column"])
        func secondaryOnlySplitNavigation(setup: String) {
            let root = InitialViewController()
            let split: SplitViewController
            let navigation = UINavigationController(rootViewController: OneViewController())
            var wrappedDetail: UIViewController?
            if setup != "classic", #available(iOS 14.0, tvOS 14.0, *) {
                split = SplitViewController(style: .doubleColumn)
                split.setViewController(ThreeViewController(), for: .primary)
                if setup == "wrapped column" {
                    // UIKit wraps a plain column controller in its own navigation controller.
                    let detail = OneViewController()
                    split.setViewController(detail, for: .secondary)
                    wrappedDetail = detail
                } else {
                    split.setViewController(navigation, for: .secondary)
                }
            } else {
                split = SplitViewController()
                split.viewControllers = [ThreeViewController(), navigation]
            }
            split.preferredDisplayMode = .secondaryOnly
            split.displayModeOverride = .secondaryOnly
            add(split, to: root)
            root.setOverrideTraitCollection(UITraitCollection(horizontalSizeClass: .regular), forChild: split)
            // An app navigation controller around the split, e.g. a hosted
            // NavigationSplitView pushed from UIKit, is not the split's own wrapper.
            let windowRoot = setup == "nested column" ? UINavigationController(rootViewController: root) : root

            withWindow(root: windowRoot, width: 1024) { _ in
                windowRoot.view.layoutIfNeeded()
                #expect(!split.isCollapsed)
                let target = wrappedDetail.map(\.navigationController) ?? navigation
                #expect(target != nil)
                var names: [String] = []
                ApplicationScreenViewPublisher.shared.startAutoCapture { names.append($0) }
                defer { ApplicationScreenViewPublisher.shared.stopAutoCapture() }

                for screen in [TwoViewController(), OneViewController()] as [UIViewController] {
                    guard let navigation = target else { break }
                    navigation.pushViewController(screen, animated: false)
                    navigation.view.layoutIfNeeded()
                    screen.viewDidAppear(false)
                }
                #expect(names == ["Two", "One"])
            }
        }

        @Test("A split pushed with animation resolves to its visible screen", arguments: [
            UIUserInterfaceSizeClass.compact,
            .regular,
        ])
        func animatedOuterNavigation(sizeClass: UIUserInterfaceSizeClass) {
            let (root, split, primary, secondary) = makeSplit(sizeClass: sizeClass)
            if sizeClass == .regular {
                split.displayModeOverride = .secondaryOnly
            }
            let navigation = UINavigationController(rootViewController: InitialViewController())

            withWindow(root: navigation, width: 1024) { _ in
                navigation.view.layoutIfNeeded()
                var names: [String] = []
                ApplicationScreenViewPublisher.shared.startAutoCapture { names.append($0) }
                defer { ApplicationScreenViewPublisher.shared.stopAutoCapture() }

                navigation.pushViewController(root, animated: true)
                navigation.view.layoutIfNeeded()
                // The split inherits the push's coordinator, which is not its own layout change.
                #expect(split.transitionCoordinator != nil)
                let visible = sizeClass == .compact ? primary : secondary
                visible.viewDidAppear(true)
                #expect(names == [sizeClass == .compact ? "One" : "Two"])
            }
        }

        @Test("SwiftUI-internal screen names are recognised conservatively", arguments: [
            ("UIHostingController<ModifiedContent<_UnaryViewAdaptor<EmptyView>, StyleContextWriter<NoStyleContext>>>", true),
            ("UIHostingController<_UnaryViewAdaptor<EmptyView>>", true),
            // A @ViewBuilder root with an if/else is a real screen.
            ("UIHostingController<_ConditionalContent<Home, Login>>", false),
            // The split view's own name, and app views wrapped in private modifiers.
            ("NotifyingMulticolumnSplit", false),
            ("UIHostingController<ModifiedContent<ContentView, _PrivateModifier>>", false),
            ("UIHostingController<ContentView>", false),
            // UIKit controllers are never skipped, even with a leading underscore.
            ("_Checkout", false),
        ])
        func swiftUIInternalNames(name: String, isInternal: Bool) {
            #expect(PostHogScreenNameSanitizer.isSwiftUIInternal(rawScreenName: name) == isInternal)
        }

        @Test("Screen autocapture skips SwiftUI-internal screens without forgetting the last screen")
        func skipsSwiftUIInternalScreens() {
            let first = OneViewController()
            let navigation = UINavigationController(rootViewController: first)

            withWindow(root: navigation) { _ in
                var names: [String] = []
                ApplicationScreenViewPublisher.shared.startAutoCapture { names.append($0) }
                defer { ApplicationScreenViewPublisher.shared.stopAutoCapture() }
                navigation.view.layoutIfNeeded()
                first.viewDidAppear(false)
                #expect(names == ["One"])

                func show(_ screen: UIViewController) {
                    navigation.setViewControllers([screen], animated: false)
                    navigation.view.layoutIfNeeded()
                    screen.viewDidAppear(false)
                }

                // Unfolding briefly shows an empty split column before the split.
                show(UIHostingController(rootView: _UnaryViewAdaptor(EmptyView())))
                #expect(names == ["One"])
                // Still deduplicated against the last real screen.
                show(first)
                #expect(names == ["One"])

                show(UIHostingController(rootView: PlainView()))
                #expect(names == ["One", "UIHostingController<PlainView>"])

                // Other underscored SwiftUI roots are real screens.
                show(UIHostingController(rootView: conditionalRoot(true)))
                #expect(names.count == 3)
                #expect(names.last?.hasPrefix("UIHostingController<_ConditionalContent<") == true)
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
