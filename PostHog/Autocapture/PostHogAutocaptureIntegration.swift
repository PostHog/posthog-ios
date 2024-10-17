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
        struct EventData {
            enum Source {
                case notification
                case actionMethod
                case gestureRecognizer
            }

            let screenName: String?
            let accessibilityLabel: String?
            let accessibilityIdentifier: String?
            let targetViewClass: String
            let targetText: String?
            let hierarchy: String
            let touchCoordinates: CGPoint
        }

        let config: PostHogConfig

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

        init(_ config: PostHogConfig) {
            self.config = config
            Self.setupSwizzlingOnce
            Self.addNotificationObservers
        }

        // `UITextField` or `UITextView` did end editing notification
        @objc static func didEndEditing(_ notification: NSNotification) {
            guard let view = notification.object as? UIView else { return }
            let source: EventData.Source = .notification
            // Text fields in SwiftUI are identifiable only after the text field is edited.
            print("PostHogSDK.shared.capture source: \(source) \(getCaptureDescription(for: view, eventDescription: "didEndEditing")))")
        }
    }

    private func getCaptureDescription(for element: UIView, eventDescription: String) -> String {
        var description = ""

        if let targetText = element.eventData.targetText {
            description = "\"\(targetText)\""
        } else if let vcName = element.nearestViewController?.descriptiveTypeName {
            description = "in \(vcName)"
        }

        return "\(eventDescription) \(element.descriptiveTypeName) \(description)".trimmingCharacters(in: .whitespacesAndNewlines)
    }

    extension UIApplication {
        @objc func ph_swizzled_uiapplication_sendAction(_ action: Selector, to target: Any?, from sender: Any?, for event: UIEvent?) -> Bool {
            defer {
                // TODO: Reduce SwiftUI noise by finding the unique view that the action method is attached to.
                // Currently, the action methods pointing to a SwiftUI target are blocked.
                let targetClass = String(describing: object_getClassName(target))
                if targetClass.contains("SwiftUI") {
                    print("PostHogSDK.shared.capture SwiftUI -> \(targetClass)")
                } else if let control = sender as? UIControl,
                          control.ph_shouldTrack(action, for: target),
                          let eventDescription = control.event(for: action, to: target)?.description
                {
                    print("PostHogSDK.shared.capture \(getCaptureDescription(for: control, eventDescription: eventDescription))")
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

            let gestureAction: String?
            switch self {
            case is UITapGestureRecognizer:
                gestureAction = "tap"
            case is UISwipeGestureRecognizer:
                gestureAction = "swipe"
            case is UIPanGestureRecognizer:
                gestureAction = "pan"
            case is UILongPressGestureRecognizer:
                gestureAction = "longPress"
            #if !os(tvOS)
                case is UIPinchGestureRecognizer:
                    gestureAction = "pinch"
                case is UIRotationGestureRecognizer:
                    gestureAction = "rotation"
                case is UIScreenEdgePanGestureRecognizer:
                    gestureAction = "screenEdgePan"
            #endif
            default:
                gestureAction = nil
            }

            guard let gestureAction else { return }

            print("PostHogSDK.shared.capture -> \(gestureAction) \(descriptiveTypeName) -> \(view.eventData)")
        }
    }

    extension UIView {
        private static let viewHierarchyDelimiter = " → "

        var eventData: PostHogAutocaptureIntegration.EventData {
            PostHogAutocaptureIntegration.EventData(
                screenName: nearestViewController
                    .flatMap(UIViewController.ph_topViewController)
                    .flatMap(UIViewController.getViewControllerName),
                accessibilityLabel: accessibilityLabel,
                accessibilityIdentifier: accessibilityIdentifier,
                targetViewClass: descriptiveTypeName,
                targetText: sanitizeTitle(ph_autocaptureTitle),
                hierarchy: sequence(first: self, next: \.superview)
                    .map(\.descriptiveTypeName)
                    .joined(separator: UIView.viewHierarchyDelimiter),
                touchCoordinates: CGPoint.zero // TODO:
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
        var description: String? {
            if self == .touchUpInside {
                return "tap"
            } else if UIControl.Event.allTouchEvents.contains(self) {
                return "touch"
            } else if UIControl.Event.allEditingEvents.contains(self) {
                return "edit"
            } else if self == .valueChanged {
                return "valueChange"
            } else if self == .primaryActionTriggered {
                return "primaryAction"
            } else if #available(iOS 14.0, tvOS 14.0, macCatalyst 14.0, *), self == .menuActionTriggered {
                return "menuAction"
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
        var ph_autocaptureTitle: String? { get }
        var ph_autocaptureEvents: UIControl.Event { get }
        func ph_shouldTrack(_ action: Selector, for target: Any?) -> Bool
    }

    extension UIView: AutoCapturable {
        @objc var ph_autocaptureEvents: UIControl.Event { .touchUpInside }
        @objc var ph_autocaptureTitle: String? { nil }
        @objc func ph_shouldTrack(_: Selector, for _: Any?) -> Bool {
            false // by default views are not tracked. Can be overwritten in subclasses
        }
    }

    extension UIButton {
        override var ph_autocaptureTitle: String? { title(for: .normal) ?? title(for: .selected) }
    }

    extension UIControl {
        @objc override func ph_shouldTrack(_ action: Selector, for target: Any?) -> Bool {
            actions(forTarget: target, forControlEvent: ph_autocaptureEvents)?.contains(action.description) ?? false
        }
    }

    extension UISegmentedControl {
        override var ph_autocaptureEvents: UIControl.Event { .valueChanged }
        override var ph_autocaptureTitle: String? { titleForSegment(at: selectedSegmentIndex) }
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
        override var ph_autocaptureTitle: String? { text ?? attributedText?.string ?? placeholder }
    }

    extension UITextView {
        override var ph_autocaptureTitle: String? { text ?? attributedText?.string }
    }

    extension UIStepper {
        override var ph_autocaptureEvents: UIControl.Event { .valueChanged }
    }

    #if !os(tvOS)
        extension UIDatePicker {
            override var ph_autocaptureEvents: UIControl.Event { .valueChanged }
        }
    #endif

    private func sanitizeTitle(_ title: String?) -> String? {
        guard let title else { return nil }
        return title.replacingOccurrences(of: "[^a-zA-Z0-9]+", with: "-", options: .regularExpression, range: nil)
    }

#endif
