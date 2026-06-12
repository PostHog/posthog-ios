//
//  PostHogRageClickIntegration.swift
//  PostHog
//
//  Created by Yiannis Josephides on 09/04/2026.
//

#if os(iOS) || targetEnvironment(macCatalyst)
    import UIKit

    final class PostHogRageClickIntegration: PostHogIntegration {
        var requiresSwizzling: Bool { true }

        private static let integrationInstallState = PostHogIntegrationInstallState()

        private weak var postHog: PostHogSDK?
        private var rageClickDetector: RageClickDetector?
        private var applicationEventToken: RegistrationToken?

        func install(_ postHog: PostHogSDK) -> PostHogIntegrationInstallResult {
            installIfNeeded(using: Self.integrationInstallState) {
                self.postHog = postHog
                rageClickDetector = RageClickDetector(config: postHog.config.rageClickConfig)

                start()
            }
        }

        func uninstall(_ postHog: PostHogSDK) {
            uninstallIfNeeded(from: postHog, installedPostHog: self.postHog, state: Self.integrationInstallState) {
                // uninstall only for integration instance
                stop()
                self.postHog = nil
            }
        }

        func start() {
            let applicationEventPublisher = DI.main.applicationEventPublisher
            applicationEventToken = applicationEventPublisher.onApplicationEvent.subscribe { [weak self] event, _ in
                self?.handleApplicationEvent(event)
            }
        }

        func stop() {
            applicationEventToken = nil
        }

        private func handleApplicationEvent(_ event: UIEvent) {
            guard postHog?.isRageClickActive() == true else {
                return
            }

            guard event.type == .touches,
                  let touches = event.allTouches
            else {
                return
            }

            // Rage clicks represent repeated single-pointer frustration taps.
            // Ignore multi-touch interactions (e.g. pinch/zoom) to avoid false positives.
            guard touches.count == 1,
                  let touch = touches.first,
                  let window = touch.window,
                  touch.phase == .ended,
                  touch.tapCount > 0
            else {
                return
            }

            let touchCoordinates = touch.location(in: window)

            // `touch.view` is nil for taps consumed by a gesture recognizer (text fields, pickers,
            // scroll views), so fall back to a hit-test to recover the tapped view.
            let hitView = touch.view ?? window.hitTest(touchCoordinates, with: event)

            // Skip taps where rapid repeats are intentional before they reach the detector.
            // The ancestor walk covers UIKit; SwiftUI hosts controls below the hit view, so we
            // also point-search the window's subtree.
            let ineligible = isRageClickIneligible(view: hitView, isKeyboardWindow: window.isKeyboardWindow)
                || ineligibleViewExists(in: window, at: touchCoordinates)
            guard !ineligible else {
                return
            }

            let eventData = hitView?.eventData(touchCoordinates: touchCoordinates)
            let elementsChain = eventData?.getElementChain() ?? ""

            captureRageClickIfNeeded(
                touchCoordinates: touchCoordinates,
                screenName: eventData?.screenName ?? currentScreenName(),
                elementsChain: elementsChain,
                eventData: eventData
            )
        }

        private func captureRageClickIfNeeded(
            touchCoordinates: CGPoint,
            screenName: String?,
            elementsChain: String,
            eventData: PostHogAutocaptureEventTracker.EventData?
        ) {
            guard let postHog,
                  let rageClickDetector,
                  rageClickDetector.isRageClick(
                      x: touchCoordinates.x,
                      y: touchCoordinates.y,
                      timestamp: ProcessInfo.processInfo.systemUptime
                  )
            else {
                return
            }

            let normalizedScreenName = screenName?.trimmingCharacters(in: .whitespacesAndNewlines)
            let normalizedElementsChain = elementsChain.trimmingCharacters(in: .whitespacesAndNewlines)
            let hasScreenName = normalizedScreenName?.isEmpty == false
            let hasElementId = eventData?.viewHierarchy.contains { $0.label?.isEmpty == false } ?? false

            // Keep rage clicks only when they contain enough context to be actionable:
            // - screen name is sufficient context when paired with touch coordinates
            // - without screen name: require a concrete element id
            guard hasScreenName || hasElementId else {
                return
            }

            var properties: [String: Any] = [
                "$touch_x": touchCoordinates.x,
                "$touch_y": touchCoordinates.y,
            ]

            if let normalizedScreenName, !normalizedScreenName.isEmpty {
                properties["$screen_name"] = normalizedScreenName
            }

            postHog.rageclick(
                eventType: EventType.kTouch,
                elementsChain: normalizedElementsChain,
                properties: properties
            )
        }

        private func currentScreenName() -> String? {
            guard let controller = UIViewController.ph_topViewController() else {
                return nil
            }
            return UIViewController.getViewControllerName(controller)
        }

        /// Whether a tap should be excluded from rage click detection, i.e. it landed on a control
        /// where rapid repeated taps are deliberate rather than frustration.
        private func isRageClickIneligible(view: UIView?, isKeyboardWindow: Bool) -> Bool {
            // The keyboard, text-selection magnifier and copy/paste menus live in dedicated windows.
            if isKeyboardWindow {
                return true
            }

            // The hit-test view is often an internal subview of the control, so walk up.
            var node = view
            while let current = node {
                if current.isRageClickIneligibleControl || current.isNoRageClick() {
                    return true
                }
                node = current.superview
            }
            return false
        }

        /// Depth-first search for an ineligible control or marker containing `point` (in `view`'s
        /// coordinate system). Needed because SwiftUI hosts controls and markers below the hit-test
        /// view, where the ancestor walk can't reach them.
        private func ineligibleViewExists(in view: UIView, at point: CGPoint) -> Bool {
            guard !view.isHidden, view.alpha > 0.01, view.bounds.contains(point) else {
                return false
            }
            if view.isRageClickIneligibleControl || view.isNoRageClick() {
                return true
            }
            // On iOS 26, SwiftUI primitives can be layer-backed, so a marker may land on a
            // CALayer rather than a view.
            if markedLayerExists(in: view.layer, at: point) {
                return true
            }
            return view.subviews.contains { subview in
                ineligibleViewExists(in: subview, at: view.convert(point, to: subview))
            }
        }

        /// Searches `layer`'s sublayers (skipping view-backing layers, already covered by the view
        /// search) for a marked layer containing `point` (in `layer`'s coordinate system).
        private func markedLayerExists(in layer: CALayer, at point: CGPoint) -> Bool {
            for sublayer in layer.sublayers ?? [] where !(sublayer.delegate is UIView) {
                let sublayerPoint = layer.convert(point, to: sublayer)
                guard !sublayer.isHidden, sublayer.opacity > 0.01, sublayer.bounds.contains(sublayerPoint) else {
                    continue
                }
                if sublayer.postHogNoRageClick || markedLayerExists(in: sublayer, at: sublayerPoint) {
                    return true
                }
            }
            return false
        }
    }

    private extension UIView {
        /// Controls where rapid repeated taps are deliberate interaction rather than frustration.
        var isRageClickIneligibleControl: Bool {
            self is UITextField || self is UITextView || self is UISearchBar // text entry / selection
                || self is UIStepper || self is UISlider // value steppers
                || self is UIDatePicker || self is UIPickerView // wheel pickers
                || self is UISegmentedControl || self is UIPageControl // paged navigation
        }
    }

    #if TESTING
        extension PostHogRageClickIntegration {
            static func clearInstalls() {
                integrationInstallState.clear()
            }

            func processTapForTesting(
                touchX: CGFloat,
                touchY: CGFloat,
                screenName: String? = "TestScreen",
                elementsChain: String = "UIButton:attr__class=\"UIButton\"",
                elementLabel: String? = nil
            ) {
                // A label produces a minimal EventData, mirroring a tap on a labeled view.
                let eventData = elementLabel.map { label in
                    PostHogAutocaptureEventTracker.EventData(
                        touchCoordinates: CGPoint(x: touchX, y: touchY),
                        value: nil,
                        screenName: screenName,
                        viewHierarchy: [
                            PostHogAutocaptureEventTracker.Element(text: "", targetClass: "UIButton", baseClass: nil, label: label),
                        ],
                        debounceInterval: 0
                    )
                }
                captureRageClickIfNeeded(
                    touchCoordinates: CGPoint(x: touchX, y: touchY),
                    screenName: screenName,
                    elementsChain: elementsChain,
                    eventData: eventData
                )
            }

            func isRageClickIneligibleForTesting(view: UIView?, isKeyboardWindow: Bool = false) -> Bool {
                isRageClickIneligible(view: view, isKeyboardWindow: isKeyboardWindow)
            }
        }
    #endif
#endif
