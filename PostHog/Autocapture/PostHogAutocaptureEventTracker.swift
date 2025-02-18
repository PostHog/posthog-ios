//
//  PostHogAutocaptureEventTracker.swift
//  PostHog
//
//  Created by Yiannis Josephides on 14/10/2024.
//

#if os(iOS) || targetEnvironment(macCatalyst)
    import UIKit

    class PostHogAutocaptureEventTracker {
        struct EventData {
            let touchCoordinates: CGPoint?
            let value: String?
            let screenName: String?
            let viewHierarchy: [Element]
            // values >0 means that this event will be debounced for `debounceInterval`
            let debounceInterval: TimeInterval
        }

        struct Element {
            let text: String
            let targetClass: String
            let baseClass: String?
            let label: String?

            var elementsChainEntry: String {
                var attributes = [String]()

                if !text.isEmpty {
                    attributes.append("text=\(text.quoted)")
                }
                if let baseClass, !baseClass.isEmpty {
                    attributes.append("attr__class=\(baseClass.quoted)")
                }
                if let label, !label.isEmpty {
                    attributes.append("attr_id=\(label.quoted)")
                }

                return attributes.isEmpty ? targetClass : "\(targetClass):\(attributes.joined())"
            }
        }

        enum EventSource {
            case notification(name: String)
            case actionMethod(description: String)
            case gestureRecognizer(description: String)
        }

        static var eventProcessor: (any AutocaptureEventProcessing)? {
            willSet {
                if newValue != nil {
                    swizzle()
                } else {
                    unswizzle()
                }
            }
        }

        private static var hasSwizzled: Bool = false
        private static func swizzle() {
            guard !hasSwizzled else { return }
            hasSwizzled = true
            swizzleMethods()
            registerNotifications()
        }

        private static func unswizzle() {
            guard hasSwizzled else { return }
            hasSwizzled = false
            swizzleMethods() // swizzling again will exchange implementations back to original
            unregisterNotifications()
        }

        private static func swizzleMethods() {
            PostHog.swizzle(
                forClass: UIApplication.self,
                original: #selector(UIApplication.sendAction),
                new: #selector(UIApplication.ph_swizzled_uiapplication_sendAction)
            )

            PostHog.swizzle(
                forClass: UIGestureRecognizer.self,
                original: #selector(setter: UIGestureRecognizer.state),
                new: #selector(UIGestureRecognizer.ph_swizzled_uigesturerecognizer_state_Setter)
            )

            PostHog.swizzle(
                forClass: UIScrollView.self,
                original: #selector(setter: UIScrollView.contentOffset),
                new: #selector(UIScrollView.ph_swizzled_setContentOffset_Setter)
            )

            PostHog.swizzle(
                forClass: UIPickerView.self,
                original: #selector(setter: UIPickerView.delegate),
                new: #selector(UIPickerView.ph_swizzled_setDelegate)
            )
        }

        private static func registerNotifications() {
            NotificationCenter.default.addObserver(
                PostHogAutocaptureEventTracker.self,
                selector: #selector(didEndEditing),
                name: UITextField.textDidEndEditingNotification,
                object: nil
            )
            NotificationCenter.default.addObserver(
                PostHogAutocaptureEventTracker.self,
                selector: #selector(didEndEditing),
                name: UITextView.textDidEndEditingNotification,
                object: nil
            )
        }

        private static func unregisterNotifications() {
            NotificationCenter.default.removeObserver(PostHogAutocaptureEventTracker.self, name: UITextField.textDidEndEditingNotification, object: nil)
            NotificationCenter.default.removeObserver(PostHogAutocaptureEventTracker.self, name: UITextView.textDidEndEditingNotification, object: nil)
        }

        // `UITextField` or `UITextView` did end editing notification
        @objc static func didEndEditing(_ notification: NSNotification) {
            guard let view = notification.object as? UIView, let eventData = view.eventData else { return }

            eventProcessor?.process(source: .notification(name: "change"), event: eventData)
        }
    }

    extension UIApplication {
        @objc func ph_swizzled_uiapplication_sendAction(_ action: Selector, to target: Any?, from sender: Any?, for event: UIEvent?) -> Bool {
            defer {
                // Currently, the action methods pointing to a SwiftUI target are blocked.
                let targetClass = String(describing: object_getClassName(target))
                if targetClass.contains("SwiftUI") {
                    hedgeLog("Action methods on SwiftUI targets are not yet supported.")
                } else if let control = sender as? UIControl,
                          control.ph_shouldTrack(action, for: target),
                          let eventData = control.eventData,
                          let eventDescription = control.event(for: action, to: target)?.description(forControl: control)
                {
                    PostHogAutocaptureEventTracker.eventProcessor?.process(source: .actionMethod(description: eventDescription), event: eventData)
                }
            }

            // first, call original method
            return ph_swizzled_uiapplication_sendAction(action, to: target, from: sender, for: event)
        }
    }

    extension UIGestureRecognizer {
        // swiftlint:disable:next cyclomatic_complexity
        @objc func ph_swizzled_uigesturerecognizer_state_Setter(_ state: UIGestureRecognizer.State) {
            // first, call original method
            ph_swizzled_uigesturerecognizer_state_Setter(state)

            guard state == .ended, let view, shouldTrack(view) else { return }

            // block scroll and zoom gestures for `UIScrollView`.
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

            // block all gestures for `UISwitch` (already captured via `.valueChanged` action)
            if String(describing: type(of: view)).starts(with: "UISwitch") {
                return
            }
            // ignore gestures in `UIPickerColumnView`
            if String(describing: type(of: view)) == "UIPickerColumnView" {
                return
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

            if let eventData = view.eventData {
                PostHogAutocaptureEventTracker.eventProcessor?.process(source: .gestureRecognizer(description: gestureDescription), event: eventData)
            }
        }
    }

    extension UIScrollView {
        @objc func ph_swizzled_setContentOffset_Setter(_ newContentOffset: CGPoint) {
            // first, call original method
            ph_swizzled_setContentOffset_Setter(newContentOffset)

            guard shouldTrack(self) else {
                return
            }

            // ignore all keyboard events
            if let window, window.isKeyboardWindow {
                return
            }

            // scrollview did not scroll (contentOffset didn't change)
            guard contentOffset != newContentOffset else {
                return
            }

            // block scrolls on UIPickerTableView. (captured via a forwarding delegate implementation)
            if String(describing: type(of: self)) == "UIPickerTableView" {
                return
            }

            if let eventData {
                PostHogAutocaptureEventTracker.eventProcessor?.process(source: .gestureRecognizer(description: EventType.kScroll), event: eventData)
            }
        }
    }

    extension UIPickerView {
        @objc func ph_swizzled_setDelegate(_ delegate: (any UIPickerViewDelegate)?) {
            guard let delegate else {
                // this just removes the delegate
                return ph_swizzled_setDelegate(delegate)
            }

            // if delegate doesn't respond to this selector, then we can't intercept selection changes
            guard delegate.responds(to: #selector(UIPickerViewDelegate.pickerView(_:didSelectRow:inComponent:))) else {
                return ph_swizzled_setDelegate(delegate)
            }

            // wrap in a forwarding delegate so we can intercept calls
            let forwardingDelegate = ForwardingPickerViewDelegate(delegate: delegate) { [weak self] in
                if let data = self?.eventData {
                    PostHogAutocaptureEventTracker.eventProcessor?.process(source: .gestureRecognizer(description: EventType.kValueChange), event: data)
                }
            }

            // Need to keep a strong reference to keep this forwarding delegate instance alive
            delegate.ph_forwardingDelegate = forwardingDelegate

            // call original setter
            ph_swizzled_setDelegate(forwardingDelegate)
        }
    }

    extension UIView {
        var eventData: PostHogAutocaptureEventTracker.EventData? {
            guard shouldTrack(self) else { return nil }
            return PostHogAutocaptureEventTracker.EventData(
                touchCoordinates: nil,
                value: ph_autocaptureText
                    .map(sanitizeText),
                screenName: nearestViewController
                    .flatMap(UIViewController.ph_topViewController)
                    .flatMap(UIViewController.getViewControllerName),
                viewHierarchy: sequence(first: self, next: \.superview)
                    .map(\.toElement),
                debounceInterval: ph_autocaptureDebounceInterval
            )
        }
    }

    private extension UIView {
        var toElement: PostHogAutocaptureEventTracker.Element {
            PostHogAutocaptureEventTracker.Element(
                text: ph_autocaptureText.map(sanitizeText) ?? "",
                targetClass: descriptiveTypeName,
                baseClass: baseTypeName,
                label: postHogLabel
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
                .primaryActionTriggered,
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
        // swiftlint:disable:next cyclomatic_complexity
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
                if control is UISwitch {
                    // toggle better describes a value chagne in a switch control
                    return EventType.kToggle
                }
                return EventType.kValueChange
            } else if #available(iOS 14.0, tvOS 14.0, macCatalyst 14.0, *), self == .menuActionTriggered {
                return EventType.kMenuAction
            }

            return nil
        }
    }

    extension UIViewController {
        class func ph_topViewController(base: UIViewController? = UIApplication.getCurrentWindow()?.rootViewController) -> UIViewController? {
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

    private func typeName(of type: AnyClass) -> String {
        let typeName = String(describing: type)
        if let match = typeName.range(of: "^[^<]+", options: .regularExpression) {
            // Extracts everything before the first '<' to deal with generics
            return String(typeName[match])
        }
        return typeName
    }

    // common base types in UIKit that should not be captured
    private let excludedBaseTypes: [AnyClass] = [
        NSObject.self,
        UIResponder.self,
        UIControl.self,
        UIView.self,
        UIScrollView.self,
    ]

    extension NSObject {
        var descriptiveTypeName: String {
            typeName(of: type(of: self))
        }

        var baseTypeName: String? {
            guard
                let superclass = type(of: self).superclass(),
                !excludedBaseTypes.contains(where: { $0 == superclass })
            else {
                return nil
            }
            return typeName(of: superclass)
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
            false // by default views are not tracked. Can be overridden in subclasses
        }
    }

    extension UIButton {
        override var ph_autocaptureText: String? { title(for: .normal) ?? title(for: .selected) }
    }

    extension UIControl {
        @objc override func ph_shouldTrack(_ action: Selector, for target: Any?) -> Bool {
            guard shouldTrack(self) else { return false }
            return actions(forTarget: target, forControlEvent: ph_autocaptureEvents)?.contains(action.description) ?? false
        }
    }

    extension UIScrollView {
        override var ph_autocaptureDebounceInterval: TimeInterval { 0.4 }
    }

    extension UISegmentedControl {
        override var ph_autocaptureEvents: UIControl.Event { .valueChanged }
        override var ph_autocaptureText: String? {
            // -1 if no segment is selected
            if (0 ..< numberOfSegments) ~= selectedSegmentIndex {
                return titleForSegment(at: selectedSegmentIndex)
            }
            return nil
        }
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
        override func ph_shouldTrack(_: Selector, for _: Any?) -> Bool {
            // Just making sure that in the future we don't intercept UIControl.Ecent (even though it's not currently emited)
            // Tracked via `UITextField.textDidEndEditingNotification`
            false
        }
    }

    extension UITextView {
        override var ph_autocaptureText: String? { text ?? attributedText?.string }
        override func ph_shouldTrack(_: Selector, for _: Any?) -> Bool {
            shouldTrack(self)
        }
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

    extension UISwitch {
        @objc override var ph_autocaptureEvents: UIControl.Event { .valueChanged }
        override var ph_autocaptureText: String? { "\(isOn)" }
    }

    extension UIPickerView {
        override var ph_autocaptureText: String? {
            (0 ..< numberOfComponents).reduce("") { result, component in
                // -1 if no row is selected
                let selectedRow = selectedRow(inComponent: component)
                let rowCount = numberOfRows(inComponent: component)

                if (0 ..< rowCount) ~= selectedRow {
                    if let title = delegate?.pickerView?(self, titleForRow: selectedRow, forComponent: component) {
                        return result.isEmpty ? title : "\(result) \(title)"
                    } else if let title = delegate?.pickerView?(self, attributedTitleForRow: selectedRow, forComponent: component) {
                        return result.isEmpty ? title.string : "\(result) \(title.string)"
                    }
                }

                return result
            }
        }
    }

    #if !os(tvOS)
        extension UIDatePicker {
            override var ph_autocaptureEvents: UIControl.Event { .valueChanged }
        }
    #endif

    private func shouldTrack(_ view: UIView) -> Bool {
        if view.isHidden { return false }
        if !view.isUserInteractionEnabled { return false }
        if view.isNoCapture() { return false }
        if view.window?.isKeyboardWindow == true { return false }

        if let textField = view as? UITextField, textField.isSensitiveText() {
            return false
        }
        if let textView = view as? UITextView, textView.isSensitiveText() {
            return false
        }

        // check view hierarchy up
        if let superview = view.superview {
            return shouldTrack(superview)
        }

        return true
    }

    // TODO: Filter out or obfuscate strings that look like sensitive data
    // see: https://github.com/PostHog/posthog-js/blob/0cfffcac9bdf1da3fbb9478c1a51170a325bd57f/src/autocapture-utils.ts#L389
    private func sanitizeText(_ title: String) -> String {
        title
            .trimmingCharacters(in: .whitespacesAndNewlines) // trim
            .replacingOccurrences( // sequence of spaces, returns and line breaks
                of: "[ \\r\\n]+",
                with: " ",
                options: .regularExpression
            )
            .replacingOccurrences( // sanitize zero-width unicode characters
                of: "[\\u{200B}\\u{200C}\\u{200D}\\u{FEFF}]",
                with: "",
                options: .regularExpression
            )
            .limit(to: 255)
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
        static let kScroll = "scroll"
        static let kRotation = "rotation"
        static let kLongPress = "long_press"
    }

    // MARK: - Helpers

    private extension String {
        func limit(to length: Int) -> String {
            if count > length {
                let index = index(startIndex, offsetBy: length)
                return String(self[..<index]) + "..."
            }
            return self
        }

        var quoted: String {
            "\"\(self)\""
        }
    }

#endif
