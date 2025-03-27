//
//  ForwardingPickerViewDelegate.swift
//  PostHog
//
//  Created by Yiannis Josephides on 24/10/2024.
//

#if os(iOS) || targetEnvironment(macCatalyst)
    import UIKit

    final class ForwardingPickerViewDelegate: NSObject, UIPickerViewDelegate, UIPickerViewDataSource {
        // this needs to be weak since `actualDelegate` will hold a strong reference to `ForwardingPickerViewDelegate`
        weak var actualDelegate: UIPickerViewDelegate?
        private var valueChangedCallback: (() -> Void)?

        // We respond to the same selectors that the original delegate responds to
        override func responds(to aSelector: Selector!) -> Bool {
            actualDelegate?.responds(to: aSelector) ?? false
        }

        init(delegate: UIPickerViewDelegate?, onValueChanged: @escaping () -> Void) {
            actualDelegate = delegate
            valueChangedCallback = onValueChanged
        }

        // MARK: - UIPickerViewDataSource

        func numberOfComponents(in pickerView: UIPickerView) -> Int {
            (actualDelegate as? UIPickerViewDataSource)?.numberOfComponents(in: pickerView) ?? 0
        }

        func pickerView(_ pickerView: UIPickerView, numberOfRowsInComponent component: Int) -> Int {
            (actualDelegate as? UIPickerViewDataSource)?.pickerView(pickerView, numberOfRowsInComponent: component) ?? 0
        }

        // MARK: - UIPickerViewDelegate

        func pickerView(_ pickerView: UIPickerView, didSelectRow row: Int, inComponent component: Int) {
            valueChangedCallback?()
            actualDelegate?.pickerView?(pickerView, didSelectRow: row, inComponent: component)
        }

        func pickerView(_ pickerView: UIPickerView, viewForRow row: Int, forComponent component: Int, reusing view: UIView?) -> UIView {
            actualDelegate?.pickerView?(pickerView, viewForRow: row, forComponent: component, reusing: view) ?? UIView()
        }

        func pickerView(_ pickerView: UIPickerView, widthForComponent component: Int) -> CGFloat {
            actualDelegate?.pickerView?(pickerView, widthForComponent: component) ?? .zero
        }

        func pickerView(_ pickerView: UIPickerView, rowHeightForComponent component: Int) -> CGFloat {
            actualDelegate?.pickerView?(pickerView, rowHeightForComponent: component) ?? .zero
        }

        func pickerView(_ pickerView: UIPickerView, titleForRow row: Int, forComponent component: Int) -> String? {
            actualDelegate?.pickerView?(pickerView, titleForRow: row, forComponent: component)
        }

        func pickerView(_ pickerView: UIPickerView, attributedTitleForRow row: Int, forComponent component: Int) -> NSAttributedString? {
            actualDelegate?.pickerView?(pickerView, attributedTitleForRow: row, forComponent: component)
        }
    }

    extension UIPickerViewDelegate {
        var ph_forwardingDelegate: UIPickerViewDelegate? {
            get { objc_getAssociatedObject(self, &AssociatedKeys.phForwardingDelegate) as? UIPickerViewDelegate }
            set { objc_setAssociatedObject(self, &AssociatedKeys.phForwardingDelegate, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC) }
        }
    }

#endif
