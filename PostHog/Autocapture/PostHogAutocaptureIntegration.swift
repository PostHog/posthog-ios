//
//  PostHogAutocaptureIntegration.swift
//  PostHog
//
//  Created by Yiannis Josephides on 14/10/2024.
//

#if os(iOS) || targetEnvironment(macCatalyst)
    import UIKit

    // TODO: Configuration
    // TODO: ph-no-capture
    // TODO: Rage Clicks - possible?
    // TODO: Dead Clicks - possible?
    class PostHogAutocaptureIntegration {
        struct EventData: Hashable {
            struct ViewNode: CustomStringConvertible, Hashable {
                let text: String
                let targetClass: String
                let index: Int
                let subviewCount: Int

                // Note: For some reason text will not be processed if not present in elements_chain string.
                // Couldn't pinpoint to exact place `posthog` where we do this
                var description: String {
                    "\(targetClass)\(text.isEmpty ? "" : ":text=\"\(text)\"")"
                }
            }

            enum EventSource {
                case notification(name: String)
                case actionMethod(description: String)
                case gestureRecognizer(description: String)
            }

            let touchCoordinates: CGPoint?
            let value: String?
            let screenName: String?
            let viewHierarchy: [ViewNode]
            let targetClass: String
            let accessibilityLabel: String?
            let accessibilityIdentifier: String?
            // values >0 means that this event will be debounced for `debounceInterval`
            let debounceInterval: TimeInterval
            
            func hash(into hasher: inout Hasher) {
                hasher.combine(viewHierarchy.map(\.targetClass))
            }
        }

        // static -> won't be added twice
        private static let addNotificationObservers: Void = {
            NotificationCenter.default.addObserver(PostHogAutocaptureIntegration.self, selector: #selector(didEndEditing), name: UITextField.textDidEndEditingNotification, object: nil)
            NotificationCenter.default.addObserver(PostHogAutocaptureIntegration.self, selector: #selector(didEndEditing), name: UITextView.textDidEndEditingNotification, object: nil)
        }()

        // static -> lazy loaded once (won't swizzle back)
        private static let setupSwizzlingOnce: Void = {
            swizzle(
                forClass: UIApplication.self,
                original: #selector(UIApplication.sendAction),
                new: #selector(UIApplication.ph_swizzled_uiapplication_sendAction)
            )

            swizzle(
                forClass: UIGestureRecognizer.self,
                original: #selector(setter: UIGestureRecognizer.state),
                new: #selector(UIGestureRecognizer.ph_swizzled_uigesturerecognizer_state)
            )
        }()

        // TODO: Account for multiple instances/processors
        private(set) weak static var eventProcessor: (any AutocaptureEventProcessing)?

        static func addEventProcessor(_ processor: some AutocaptureEventProcessing) {
            if eventProcessor == nil {
                setupSwizzlingOnce
                addNotificationObservers
            }
            eventProcessor = processor
        }

        static func removeEventProcessor(_: some AutocaptureEventProcessing) {
            eventProcessor = nil
        }

        // `UITextField` or `UITextView` did end editing notification
        @objc static func didEndEditing(_ notification: NSNotification) {
            guard let view = notification.object as? UIView else { return }
            eventProcessor?.process(source: .notification(name: "change"), event: view.eventData)
        }
    }

    extension UIApplication {
        @objc func ph_swizzled_uiapplication_sendAction(_ action: Selector, to target: Any?, from sender: Any?, for event: UIEvent?) -> Bool {
            defer {
                // Currently, the action methods pointing to a SwiftUI target are blocked.
                let targetClass = String(describing: object_getClassName(target))
                if targetClass.contains("SwiftUI") {
                    print("PostHogSDK.shared.capture SwiftUI -> \(targetClass)")
                } else if let control = sender as? UIControl,
                          control.ph_shouldTrack(action, for: target),
                          let eventDescription = control.event(for: action, to: target)?.description(forControl: control)
                {
                    PostHogAutocaptureIntegration.eventProcessor?.process(source: .actionMethod(description: eventDescription), event: control.eventData)
                }
            }

            // first, call original method
            return ph_swizzled_uiapplication_sendAction(action, to: target, from: sender, for: event)
        }
    }

    extension UIGestureRecognizer {
        @objc func ph_swizzled_uigesturerecognizer_state(_ state: UIGestureRecognizer.State) {
            // first, call original method
            ph_swizzled_uigesturerecognizer_state(state)

            guard state == .ended, let view else { return }

            // Block scroll and zoom events for `UIScrollView`.
            if let scrollView = view as? UIScrollView {
                if self === scrollView.panGestureRecognizer {
                    return
                }
                #if !os(tvOS)
                    if self === scrollView.pinchGestureRecognizer {
                        return
                    }
                #endif
            }

            let gestureDescription: String?
            switch self {
            case is UITapGestureRecognizer:
                gestureDescription = EventType.kTouch
            case is UISwipeGestureRecognizer:
                gestureDescription = EventType.kSwipe
            case is UIPanGestureRecognizer:
                gestureDescription = EventType.kPan
            case is UILongPressGestureRecognizer:
                gestureDescription = EventType.kLongPress
            #if !os(tvOS)
                case is UIPinchGestureRecognizer:
                    gestureDescription = EventType.kPinch
                case is UIRotationGestureRecognizer:
                    gestureDescription = EventType.kRotation
                case is UIScreenEdgePanGestureRecognizer:
                    gestureDescription = EventType.kPan
            #endif
            default:
                gestureDescription = nil
            }

            guard let gestureDescription else { return }

            PostHogAutocaptureIntegration.eventProcessor?.process(source: .gestureRecognizer(description: gestureDescription), event: view.eventData)
        }
    }

    extension UIView {
        var eventData: PostHogAutocaptureIntegration.EventData {
            PostHogAutocaptureIntegration.EventData(
                touchCoordinates: nil,
                value: ph_autocaptureText
                    .map(sanitizeText),
                screenName: nearestViewController
                    .flatMap(UIViewController.ph_topViewController)
                    .flatMap(UIViewController.getViewControllerName),
                viewHierarchy: sequence(first: self, next: \.superview)
                    .enumerated()
                    .map { $1.viewNode(index: $0) },
                targetClass: descriptiveTypeName,
                accessibilityLabel: accessibilityLabel,
                accessibilityIdentifier: accessibilityIdentifier,
                debounceInterval: ph_autocaptureDebounceInterval
            )
        }
    }

    extension UIView {
        func viewNode(index: Int) -> PostHogAutocaptureIntegration.EventData.ViewNode {
            PostHogAutocaptureIntegration.EventData.ViewNode(
                text: ph_autocaptureText.map(sanitizeText) ?? "",
                targetClass: descriptiveTypeName,
                index: index,
                subviewCount: subviews.count
            )
        }
    }

    extension UIControl {
        func event(for action: Selector, to target: Any?) -> UIControl.Event? {
            var events: [UIControl.Event] = [
                .valueChanged,
                .touchDown,
                .touchDownRepeat,
                .touchDragInside,
                .touchDragOutside,
                .touchDragEnter,
                .touchDragExit,
                .touchUpInside,
                .touchUpOutside,
                .touchCancel,
                .editingDidBegin,
                .editingChanged,
                .editingDidEnd,
                .editingDidEndOnExit,
                .primaryActionTriggered
            ]

            if #available(iOS 14.0, tvOS 14.0, macCatalyst 14.0, *) {
                events.append(.menuActionTriggered)
            }

            // latest event for action
            return events.first { event in
                self.actions(forTarget: target, forControlEvent: event)?.contains(action.description) ?? false
            }
        }
    }

    extension UIControl.Event {
        func description(forControl control: UIControl) -> String? {
            if self == .primaryActionTriggered {
                if control is UIButton {
                    return EventType.kTouch // UIButton triggers primaryAction with a touch interaction
                } else if control is UISegmentedControl {
                    return EventType.kValueChange // UISegmentedControl changes its value
                } else if control is UITextField {
                    return EventType.kSubmit // UITextField uses this for submit-like behavior
                } else if control is UISwitch {
                    return EventType.kToggle
                } else if control is UIDatePicker {
                    return EventType.kValueChange
                } else if control is UIStepper {
                    return EventType.kValueChange
                } else {
                    return EventType.kPrimaryAction
                }
            }

            // General event descriptions
            if UIControl.Event.allTouchEvents.contains(self) {
                return EventType.kTouch
            } else if UIControl.Event.allEditingEvents.contains(self) {
                return EventType.kChange
            } else if self == .valueChanged {
                return EventType.kValueChange
            } else if #available(iOS 14.0, tvOS 14.0, macCatalyst 14.0, *), self == .menuActionTriggered {
                return EventType.kMenuAction
            }

            return nil
        }
    }

    extension UIApplication {
        static var ph_currentWindow: UIWindow? {
            Array(UIApplication.shared.connectedScenes)
                .compactMap { $0 as? UIWindowScene }
                .flatMap(\.windows)
                .first { $0.windowLevel != .statusBar }
        }
    }

    extension UIViewController {
        class func ph_topViewController(base: UIViewController? = UIApplication.ph_currentWindow?.rootViewController) -> UIViewController? {
            if let nav = base as? UINavigationController {
                return ph_topViewController(base: nav.visibleViewController)

            } else if let tab = base as? UITabBarController, let selected = tab.selectedViewController {
                return ph_topViewController(base: selected)

            } else if let presented = base?.presentedViewController {
                return ph_topViewController(base: presented)
            }
            return base
        }
    }

    extension UIResponder {
        var nearestViewController: UIViewController? {
            self as? UIViewController ?? next?.nearestViewController
        }
    }

    extension NSObject {
        var descriptiveTypeName: String {
            String(describing: type(of: self))
        }
    }

    protocol AutoCapturable {
        var ph_autocaptureText: String? { get }
        var ph_autocaptureEvents: UIControl.Event { get }
        var ph_autocaptureDebounceInterval: TimeInterval { get }
        func ph_shouldTrack(_ action: Selector, for target: Any?) -> Bool
    }

    extension UIView: AutoCapturable {
        @objc var ph_autocaptureEvents: UIControl.Event { .touchUpInside }
        @objc var ph_autocaptureText: String? { nil }
        @objc var ph_autocaptureDebounceInterval: TimeInterval { 0 }
        @objc func ph_shouldTrack(_: Selector, for _: Any?) -> Bool {
            false // by default views are not tracked. Can be overriden in subclasses
        }
    }

    extension UIButton {
        override var ph_autocaptureText: String? { title(for: .normal) ?? title(for: .selected) }
    }

    extension UIControl {
        @objc override func ph_shouldTrack(_ action: Selector, for target: Any?) -> Bool {
            actions(forTarget: target, forControlEvent: ph_autocaptureEvents)?.contains(action.description) ?? false
        }
    }

    extension UISegmentedControl {
        override var ph_autocaptureEvents: UIControl.Event { .valueChanged }
        override var ph_autocaptureText: String? { titleForSegment(at: selectedSegmentIndex) }
    }

    extension UIPageControl {
        override var ph_autocaptureEvents: UIControl.Event { .valueChanged }
    }

    extension UISearchBar {
        override var ph_autocaptureEvents: UIControl.Event { .editingDidEnd }
    }

    extension UIToolbar {
        override var ph_autocaptureEvents: UIControl.Event {
            if #available(iOS 14.0, *) { .menuActionTriggered } else { .primaryActionTriggered }
        }
    }

    extension UITextField {
        override var ph_autocaptureText: String? { text ?? attributedText?.string ?? placeholder }
    }

    extension UITextView {
        override var ph_autocaptureText: String? { text ?? attributedText?.string }
    }

    extension UIStepper {
        override var ph_autocaptureEvents: UIControl.Event { .valueChanged }
        override var ph_autocaptureText: String? { "\(value)" }
    }

    extension UISlider {
        override var ph_autocaptureDebounceInterval: TimeInterval { 0.3 }
        override var ph_autocaptureEvents: UIControl.Event { .valueChanged }
        override var ph_autocaptureText: String? { "\(value)" }
    }

    #if !os(tvOS)
        extension UIDatePicker {
            override var ph_autocaptureEvents: UIControl.Event { .valueChanged }
        }
    #endif

    private func sanitizeText(_ title: String) -> String {
        title.replacingOccurrences(of: "[^a-zA-Z0-9.]+", with: "-", options: .regularExpression, range: nil)
    }

    enum EventType {
        static let kValueChange = "value_changed"
        static let kSubmit = "submit"
        static let kToggle = "toggle"
        static let kPrimaryAction = "primary_action"
        static let kMenuAction = "menu_action"
        static let kChange = "change"

        static let kTouch = "touch"
        static let kSwipe = "swipe"
        static let kPinch = "pinch"
        static let kPan = "pan"
        static let kRotation = "rotation"
        static let kLongPress = "long_press"
    }

#endif
