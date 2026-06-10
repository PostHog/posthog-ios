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

        private static var integrationInstalledLock = NSLock()
        private static var integrationInstalled = false

        private weak var postHog: PostHogSDK?
        private var rageClickDetector: RageClickDetector?
        private var applicationEventToken: RegistrationToken?

        func install(_ postHog: PostHogSDK) -> PostHogIntegrationInstallResult {
            let didInstall = PostHogRageClickIntegration.integrationInstalledLock.withLock {
                if PostHogRageClickIntegration.integrationInstalled {
                    return false
                }
                PostHogRageClickIntegration.integrationInstalled = true
                return true
            }

            guard didInstall else {
                return .skipped(.alreadyInstalled)
            }

            self.postHog = postHog
            rageClickDetector = RageClickDetector(config: postHog.config.rageClickConfig)

            start()
            return .installed
        }

        func uninstall(_ postHog: PostHogSDK) {
            // uninstall only for integration instance
            if self.postHog === postHog || self.postHog == nil {
                stop()
                self.postHog = nil
                PostHogRageClickIntegration.integrationInstalledLock.withLock {
                    PostHogRageClickIntegration.integrationInstalled = false
                }
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

            // Skip taps where rapid repeats are intentional (on-screen keyboard, text fields,
            // steppers, pickers, …) before they reach the detector, so they never accumulate a
            // rage sequence and can't produce a false `$rageclick`.
            guard !isRageClickIneligible(view: touch.view, isKeyboardWindow: window.isKeyboardWindow) else {
                return
            }

            let touchCoordinates = touch.location(in: window)
            let eventData = touch.view?.eventData(touchCoordinates: touchCoordinates)
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

        /// Whether a tap should be excluded from rage click detection.
        ///
        /// Mirrors the element-aware suppression in posthog-js: rapid repeated taps are deliberate
        /// (not frustration) on the on-screen keyboard, text entry/selection, value steppers and
        /// paged navigation. As the native SDK is also embedded by the React Native and Flutter SDKs,
        /// this suppression applies to those hosts too — see `isRageClickIneligibleControl` and
        /// `UIView.isNoRageClick()` for the cross-host caveats.
        private func isRageClickIneligible(view: UIView?, isKeyboardWindow: Bool) -> Bool {
            // The on-screen keyboard, predictive bar, text-selection magnifier and copy/paste menus
            // all live in dedicated keyboard/text-effect windows. This is the one check that holds
            // across native, React Native and Flutter (all use the real iOS keyboard).
            if isKeyboardWindow {
                return true
            }

            // The hit-test view is often an internal subview (a text field's content view, a
            // stepper's inner buttons), so walk up the hierarchy like `shouldTrack(_:)` does.
            var node = view
            while let current = node {
                if current.isRageClickIneligibleControl || current.isNoRageClick() {
                    return true
                }
                node = current.superview
            }
            return false
        }
    }

    private extension UIView {
        /// Controls where rapid repeated taps are deliberate interaction rather than frustration:
        /// text entry/selection, value steppers, wheel pickers and paged navigation.
        ///
        /// Matches native UIKit and React Native text inputs (`RCTUITextField`/`RCTUITextView`
        /// subclass these). Flutter draws its own widgets into a single `FlutterView`, so its
        /// controls aren't matched here and rely on the `ph-no-rageclick` marker instead.
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
                integrationInstalledLock.withLock {
                    integrationInstalled = false
                }
            }

            func processTapForTesting(
                touchX: CGFloat,
                touchY: CGFloat,
                view: UIView? = nil,
                isKeyboardWindow: Bool = false,
                screenName: String? = "TestScreen",
                elementsChain: String = "UIButton:attr__class=\"UIButton\"",
                elementLabel: String? = nil
            ) {
                guard !isRageClickIneligible(view: view, isKeyboardWindow: isKeyboardWindow) else {
                    return
                }
                // When a label is supplied, build a minimal EventData so the capture path sees a
                // concrete element id (mirrors a real tap landing on a labeled view).
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
