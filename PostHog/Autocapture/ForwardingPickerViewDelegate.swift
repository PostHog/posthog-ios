// swiftlint:disable cyclomatic_complexity

//
//  ForwardingPickerViewDelegate.swift
//  PostHog
//
//  Created by Yiannis Josephides on 24/10/2024.
//

#if os(iOS) || targetEnvironment(macCatalyst)
    import Foundation
    import UIKit

    enum ForwardingDelegateSelector {
        static func selectDelegate(for actualDelegate: UIPickerViewDelegate?, onValueChanged: @escaping () -> Void) -> UIPickerViewDelegate {
            // Checking if the actual delegate implements specific methods
            let titleForRow = actualDelegate?.responds(to: #selector(UIPickerViewDelegate.pickerView(_:titleForRow:forComponent:))) ?? false
            let attributedTitleForRow = actualDelegate?.responds(to: #selector(UIPickerViewDelegate.pickerView(_:attributedTitleForRow:forComponent:))) ?? false
            let viewForRow = actualDelegate?.responds(to: #selector(UIPickerViewDelegate.pickerView(_:viewForRow:forComponent:reusing:))) ?? false
            let rowHeightForComponent = actualDelegate?.responds(to: #selector(UIPickerViewDelegate.pickerView(_:rowHeightForComponent:))) ?? false
            let widthForComponent = actualDelegate?.responds(to: #selector(UIPickerViewDelegate.pickerView(_:widthForComponent:))) ?? false

            // Selecting the appropriate forwarding delegate based on implemented methods
            //
            // UIPickerViewDelegate includes several `optional` methods that return values.
            //
            // To ensure that the behavior of the host app is preserved, we must select a forwarding delegate that accurately
            // reflects which methods are implemented by the original delegate. This ensures the forwarding delegate
            // responds correctly to `responds(to: #selector)` checks and avoids dependeing on abstract default values

            switch (titleForRow, attributedTitleForRow, viewForRow, rowHeightForComponent, widthForComponent) {
            case (false, false, false, false, false):
                return ForwardingPickerViewDelegate1(delegate: actualDelegate, onValueChanged: onValueChanged)
            case (true, false, false, false, false):
                return ForwardingPickerViewDelegate2(delegate: actualDelegate, onValueChanged: onValueChanged)
            case (false, true, false, false, false):
                return ForwardingPickerViewDelegate3(delegate: actualDelegate, onValueChanged: onValueChanged)
            case (false, false, true, false, false):
                return ForwardingPickerViewDelegate4(delegate: actualDelegate, onValueChanged: onValueChanged)
            case (false, false, false, true, false):
                return ForwardingPickerViewDelegate5(delegate: actualDelegate, onValueChanged: onValueChanged)
            case (false, false, false, false, true):
                return ForwardingPickerViewDelegate6(delegate: actualDelegate, onValueChanged: onValueChanged)
            case (true, true, false, false, false):
                return ForwardingPickerViewDelegate7(delegate: actualDelegate, onValueChanged: onValueChanged)
            case (true, false, true, false, false):
                return ForwardingPickerViewDelegate8(delegate: actualDelegate, onValueChanged: onValueChanged)
            case (true, false, false, true, false):
                return ForwardingPickerViewDelegate9(delegate: actualDelegate, onValueChanged: onValueChanged)
            case (true, false, false, false, true):
                return ForwardingPickerViewDelegate10(delegate: actualDelegate, onValueChanged: onValueChanged)
            case (false, true, true, false, false):
                return ForwardingPickerViewDelegate11(delegate: actualDelegate, onValueChanged: onValueChanged)
            case (false, true, false, true, false):
                return ForwardingPickerViewDelegate12(delegate: actualDelegate, onValueChanged: onValueChanged)
            case (false, true, false, false, true):
                return ForwardingPickerViewDelegate13(delegate: actualDelegate, onValueChanged: onValueChanged)
            case (false, false, true, true, false):
                return ForwardingPickerViewDelegate14(delegate: actualDelegate, onValueChanged: onValueChanged)
            case (false, false, true, false, true):
                return ForwardingPickerViewDelegate15(delegate: actualDelegate, onValueChanged: onValueChanged)
            case (false, false, false, true, true):
                return ForwardingPickerViewDelegate16(delegate: actualDelegate, onValueChanged: onValueChanged)
            case (true, true, true, false, false):
                return ForwardingPickerViewDelegate17(delegate: actualDelegate, onValueChanged: onValueChanged)
            case (true, true, false, true, false):
                return ForwardingPickerViewDelegate18(delegate: actualDelegate, onValueChanged: onValueChanged)
            case (true, true, false, false, true):
                return ForwardingPickerViewDelegate19(delegate: actualDelegate, onValueChanged: onValueChanged)
            case (true, false, true, true, false):
                return ForwardingPickerViewDelegate20(delegate: actualDelegate, onValueChanged: onValueChanged)
            case (true, false, true, false, true):
                return ForwardingPickerViewDelegate21(delegate: actualDelegate, onValueChanged: onValueChanged)
            case (true, false, false, true, true):
                return ForwardingPickerViewDelegate22(delegate: actualDelegate, onValueChanged: onValueChanged)
            case (false, true, true, true, false):
                return ForwardingPickerViewDelegate23(delegate: actualDelegate, onValueChanged: onValueChanged)
            case (false, true, true, false, true):
                return ForwardingPickerViewDelegate24(delegate: actualDelegate, onValueChanged: onValueChanged)
            case (false, true, false, true, true):
                return ForwardingPickerViewDelegate25(delegate: actualDelegate, onValueChanged: onValueChanged)
            case (false, false, true, true, true):
                return ForwardingPickerViewDelegate26(delegate: actualDelegate, onValueChanged: onValueChanged)
            case (true, true, true, true, false):
                return ForwardingPickerViewDelegate27(delegate: actualDelegate, onValueChanged: onValueChanged)
            case (true, true, true, false, true):
                return ForwardingPickerViewDelegate28(delegate: actualDelegate, onValueChanged: onValueChanged)
            case (true, true, false, true, true):
                return ForwardingPickerViewDelegate29(delegate: actualDelegate, onValueChanged: onValueChanged)
            case (true, false, true, true, true):
                return ForwardingPickerViewDelegate30(delegate: actualDelegate, onValueChanged: onValueChanged)
            case (false, true, true, true, true):
                return ForwardingPickerViewDelegate31(delegate: actualDelegate, onValueChanged: onValueChanged)
            case (true, true, true, true, true):
                return ForwardingPickerViewDelegate32(delegate: actualDelegate, onValueChanged: onValueChanged)
            }
        }
    }

    private var phForwardingDelegateKey: UInt8 = 0
    extension UIPickerViewDelegate {
        var phForwardingDelegate: UIPickerViewDelegate {
            get {
                objc_getAssociatedObject(self, &phForwardingDelegateKey) as! UIPickerViewDelegate
            }

            set {
                objc_setAssociatedObject(
                    self,
                    &phForwardingDelegateKey,
                    newValue as UIPickerViewDelegate?,
                    .OBJC_ASSOCIATION_RETAIN_NONATOMIC
                )
            }
        }
    }

    // MARK: - DELEGATE VARIANTS

    /// Combination 1: `didSelectRow`
    private class ForwardingPickerViewDelegate1: NSObject, UIPickerViewDelegate {
        weak var actualDelegate: UIPickerViewDelegate?
        private var valueChangedCallback: (() -> Void)?

        init(delegate: UIPickerViewDelegate?, onValueChanged: @escaping () -> Void) {
            actualDelegate = delegate
            valueChangedCallback = onValueChanged
        }
    }

    /// Combination 2: `didSelectRow`, `titleForRow`
    private class ForwardingPickerViewDelegate2: NSObject, UIPickerViewDelegate {
        weak var actualDelegate: UIPickerViewDelegate?
        private var valueChangedCallback: (() -> Void)?

        init(delegate: UIPickerViewDelegate?, onValueChanged: @escaping () -> Void) {
            actualDelegate = delegate
            valueChangedCallback = onValueChanged
        }

        func pickerView(_ pickerView: UIPickerView, didSelectRow row: Int, inComponent component: Int) {
            valueChangedCallback?()
            actualDelegate?.pickerView?(pickerView, didSelectRow: row, inComponent: component)
        }

        func pickerView(_ pickerView: UIPickerView, titleForRow row: Int, forComponent component: Int) -> String? {
            actualDelegate?.pickerView?(pickerView, titleForRow: row, forComponent: component)
        }
    }

    /// Combination 3: `didSelectRow`, `attributedTitleForRow`
    private class ForwardingPickerViewDelegate3: NSObject, UIPickerViewDelegate {
        weak var actualDelegate: UIPickerViewDelegate?

        private var valueChangedCallback: (() -> Void)?

        init(delegate: UIPickerViewDelegate?, onValueChanged: @escaping () -> Void) {
            actualDelegate = delegate
            valueChangedCallback = onValueChanged
        }

        func pickerView(_ pickerView: UIPickerView, didSelectRow row: Int, inComponent component: Int) {
            // Call the value changed callback
            valueChangedCallback?()
            // Forward the call to the actual delegate
            actualDelegate?.pickerView?(pickerView, didSelectRow: row, inComponent: component)
        }

        func pickerView(_ pickerView: UIPickerView, attributedTitleForRow row: Int, forComponent component: Int) -> NSAttributedString? {
            actualDelegate?.pickerView?(pickerView, attributedTitleForRow: row, forComponent: component)
        }
    }

    /// Combination 4: `didSelectRow`, `viewForRow`
    private class ForwardingPickerViewDelegate4: NSObject, UIPickerViewDelegate {
        weak var actualDelegate: UIPickerViewDelegate?
        private var valueChangedCallback: (() -> Void)?

        init(delegate: UIPickerViewDelegate?, onValueChanged: @escaping () -> Void) {
            actualDelegate = delegate
            valueChangedCallback = onValueChanged
        }

        func pickerView(_ pickerView: UIPickerView, didSelectRow row: Int, inComponent component: Int) {
            valueChangedCallback?()
            actualDelegate?.pickerView?(pickerView, didSelectRow: row, inComponent: component)
        }

        func pickerView(_ pickerView: UIPickerView, viewForRow row: Int, forComponent component: Int, reusing view: UIView?) -> UIView {
            actualDelegate?.pickerView?(pickerView, viewForRow: row, forComponent: component, reusing: view) ?? UIView()
        }
    }

    /// Combination 5: `didSelectRow`, `rowHeightForComponent`
    private class ForwardingPickerViewDelegate5: NSObject, UIPickerViewDelegate {
        weak var actualDelegate: UIPickerViewDelegate?
        private var valueChangedCallback: (() -> Void)?

        init(delegate: UIPickerViewDelegate?, onValueChanged: @escaping () -> Void) {
            actualDelegate = delegate
            valueChangedCallback = onValueChanged
        }

        func pickerView(_ pickerView: UIPickerView, didSelectRow row: Int, inComponent component: Int) {
            valueChangedCallback?()
            actualDelegate?.pickerView?(pickerView, didSelectRow: row, inComponent: component)
        }

        func pickerView(_ pickerView: UIPickerView, rowHeightForComponent component: Int) -> CGFloat {
            actualDelegate?.pickerView?(pickerView, rowHeightForComponent: component) ?? .zero
        }
    }

    /// Combination 6: `didSelectRow`, `widthForComponent`
    private class ForwardingPickerViewDelegate6: NSObject, UIPickerViewDelegate {
        weak var actualDelegate: UIPickerViewDelegate?
        private var valueChangedCallback: (() -> Void)?

        init(delegate: UIPickerViewDelegate?, onValueChanged: @escaping () -> Void) {
            actualDelegate = delegate
            valueChangedCallback = onValueChanged
        }

        func pickerView(_ pickerView: UIPickerView, didSelectRow row: Int, inComponent component: Int) {
            valueChangedCallback?()
            actualDelegate?.pickerView?(pickerView, didSelectRow: row, inComponent: component)
        }

        func pickerView(_ pickerView: UIPickerView, widthForComponent component: Int) -> CGFloat {
            actualDelegate?.pickerView?(pickerView, widthForComponent: component) ?? .zero
        }
    }

    /// Combination 7: `didSelectRow`, `titleForRow`, `attributedTitleForRow`
    private class ForwardingPickerViewDelegate7: NSObject, UIPickerViewDelegate {
        weak var actualDelegate: UIPickerViewDelegate?
        private var valueChangedCallback: (() -> Void)?

        init(delegate: UIPickerViewDelegate?, onValueChanged: @escaping () -> Void) {
            actualDelegate = delegate
            valueChangedCallback = onValueChanged
        }

        func pickerView(_ pickerView: UIPickerView, didSelectRow row: Int, inComponent component: Int) {
            valueChangedCallback?()
            actualDelegate?.pickerView?(pickerView, didSelectRow: row, inComponent: component)
        }

        func pickerView(_ pickerView: UIPickerView, titleForRow row: Int, forComponent component: Int) -> String? {
            actualDelegate?.pickerView?(pickerView, titleForRow: row, forComponent: component)
        }

        func pickerView(_ pickerView: UIPickerView, attributedTitleForRow row: Int, forComponent component: Int) -> NSAttributedString? {
            actualDelegate?.pickerView?(pickerView, attributedTitleForRow: row, forComponent: component)
        }
    }

    /// Combination 8: `didSelectRow`, `titleForRow`, `viewForRow`
    private class ForwardingPickerViewDelegate8: NSObject, UIPickerViewDelegate {
        weak var actualDelegate: UIPickerViewDelegate?
        private var valueChangedCallback: (() -> Void)?

        init(delegate: UIPickerViewDelegate?, onValueChanged: @escaping () -> Void) {
            actualDelegate = delegate
            valueChangedCallback = onValueChanged
        }

        func pickerView(_ pickerView: UIPickerView, didSelectRow row: Int, inComponent component: Int) {
            valueChangedCallback?()
            actualDelegate?.pickerView?(pickerView, didSelectRow: row, inComponent: component)
        }

        func pickerView(_ pickerView: UIPickerView, titleForRow row: Int, forComponent component: Int) -> String? {
            actualDelegate?.pickerView?(pickerView, titleForRow: row, forComponent: component)
        }

        func pickerView(_ pickerView: UIPickerView, viewForRow row: Int, forComponent component: Int, reusing view: UIView?) -> UIView {
            actualDelegate?.pickerView?(pickerView, viewForRow: row, forComponent: component, reusing: view) ?? UIView()
        }

        func pickerView(_ pickerView: UIPickerView, rowHeightForComponent component: Int) -> CGFloat {
            actualDelegate?.pickerView?(pickerView, rowHeightForComponent: component) ?? .zero
        }

        func pickerView(_ pickerView: UIPickerView, widthForComponent component: Int) -> CGFloat {
            actualDelegate?.pickerView?(pickerView, widthForComponent: component) ?? .zero
        }
    }

    /// Combination 9: `didSelectRow`, `titleForRow`, `rowHeightForComponent`
    private class ForwardingPickerViewDelegate9: NSObject, UIPickerViewDelegate {
        weak var actualDelegate: UIPickerViewDelegate?
        private var valueChangedCallback: (() -> Void)?

        init(delegate: UIPickerViewDelegate?, onValueChanged: @escaping () -> Void) {
            actualDelegate = delegate
            valueChangedCallback = onValueChanged
        }

        func pickerView(_ pickerView: UIPickerView, didSelectRow row: Int, inComponent component: Int) {
            valueChangedCallback?()
            actualDelegate?.pickerView?(pickerView, didSelectRow: row, inComponent: component)
        }

        func pickerView(_ pickerView: UIPickerView, titleForRow row: Int, forComponent component: Int) -> String? {
            actualDelegate?.pickerView?(pickerView, titleForRow: row, forComponent: component)
        }

        func pickerView(_ pickerView: UIPickerView, rowHeightForComponent component: Int) -> CGFloat {
            actualDelegate?.pickerView?(pickerView, rowHeightForComponent: component) ?? .zero
        }
    }

    /// Combination 10: `didSelectRow`, `titleForRow`, `widthForComponent`
    private class ForwardingPickerViewDelegate10: NSObject, UIPickerViewDelegate {
        weak var actualDelegate: UIPickerViewDelegate?
        private var valueChangedCallback: (() -> Void)?

        init(delegate: UIPickerViewDelegate?, onValueChanged: @escaping () -> Void) {
            actualDelegate = delegate
            valueChangedCallback = onValueChanged
        }

        func pickerView(_ pickerView: UIPickerView, didSelectRow row: Int, inComponent component: Int) {
            valueChangedCallback?()
            actualDelegate?.pickerView?(pickerView, didSelectRow: row, inComponent: component)
        }

        func pickerView(_ pickerView: UIPickerView, titleForRow row: Int, forComponent component: Int) -> String? {
            actualDelegate?.pickerView?(pickerView, titleForRow: row, forComponent: component)
        }

        func pickerView(_ pickerView: UIPickerView, widthForComponent component: Int) -> CGFloat {
            actualDelegate?.pickerView?(pickerView, widthForComponent: component) ?? .zero
        }
    }

    /// Combination 11: `didSelectRow`, `attributedTitleForRow`, `viewForRow`
    private class ForwardingPickerViewDelegate11: NSObject, UIPickerViewDelegate {
        weak var actualDelegate: UIPickerViewDelegate?
        private var valueChangedCallback: (() -> Void)?

        init(delegate: UIPickerViewDelegate?, onValueChanged: @escaping () -> Void) {
            actualDelegate = delegate
            valueChangedCallback = onValueChanged
        }

        func pickerView(_ pickerView: UIPickerView, didSelectRow row: Int, inComponent component: Int) {
            valueChangedCallback?()
            actualDelegate?.pickerView?(pickerView, didSelectRow: row, inComponent: component)
        }

        func pickerView(_ pickerView: UIPickerView, attributedTitleForRow row: Int, forComponent component: Int) -> NSAttributedString? {
            actualDelegate?.pickerView?(pickerView, attributedTitleForRow: row, forComponent: component)
        }

        func pickerView(_ pickerView: UIPickerView, viewForRow row: Int, forComponent component: Int, reusing view: UIView?) -> UIView {
            actualDelegate?.pickerView?(pickerView, viewForRow: row, forComponent: component, reusing: view) ?? UIView()
        }
    }

    /// Combination 12: `didSelectRow`, `attributedTitleForRow`, `rowHeightForComponent`
    private class ForwardingPickerViewDelegate12: NSObject, UIPickerViewDelegate {
        weak var actualDelegate: UIPickerViewDelegate?
        private var valueChangedCallback: (() -> Void)?

        init(delegate: UIPickerViewDelegate?, onValueChanged: @escaping () -> Void) {
            actualDelegate = delegate
            valueChangedCallback = onValueChanged
        }

        func pickerView(_ pickerView: UIPickerView, didSelectRow row: Int, inComponent component: Int) {
            valueChangedCallback?()
            actualDelegate?.pickerView?(pickerView, didSelectRow: row, inComponent: component)
        }

        func pickerView(_ pickerView: UIPickerView, attributedTitleForRow row: Int, forComponent component: Int) -> NSAttributedString? {
            actualDelegate?.pickerView?(pickerView, attributedTitleForRow: row, forComponent: component)
        }

        func pickerView(_ pickerView: UIPickerView, rowHeightForComponent component: Int) -> CGFloat {
            actualDelegate?.pickerView?(pickerView, rowHeightForComponent: component) ?? .zero
        }
    }

    /// Combination 13: `didSelectRow`, `attributedTitleForRow`, `widthForComponent`
    private class ForwardingPickerViewDelegate13: NSObject, UIPickerViewDelegate {
        weak var actualDelegate: UIPickerViewDelegate?
        private var valueChangedCallback: (() -> Void)?

        init(delegate: UIPickerViewDelegate?, onValueChanged: @escaping () -> Void) {
            actualDelegate = delegate
            valueChangedCallback = onValueChanged
        }

        func pickerView(_ pickerView: UIPickerView, didSelectRow row: Int, inComponent component: Int) {
            valueChangedCallback?()
            actualDelegate?.pickerView?(pickerView, didSelectRow: row, inComponent: component)
        }

        func pickerView(_ pickerView: UIPickerView, attributedTitleForRow row: Int, forComponent component: Int) -> NSAttributedString? {
            actualDelegate?.pickerView?(pickerView, attributedTitleForRow: row, forComponent: component)
        }

        func pickerView(_ pickerView: UIPickerView, widthForComponent component: Int) -> CGFloat {
            actualDelegate?.pickerView?(pickerView, widthForComponent: component) ?? .zero
        }
    }

    /// Combination 14: `didSelectRow`, `viewForRow`, `rowHeightForComponent`
    private class ForwardingPickerViewDelegate14: NSObject, UIPickerViewDelegate {
        weak var actualDelegate: UIPickerViewDelegate?
        private var valueChangedCallback: (() -> Void)?

        init(delegate: UIPickerViewDelegate?, onValueChanged: @escaping () -> Void) {
            actualDelegate = delegate
            valueChangedCallback = onValueChanged
        }

        func pickerView(_ pickerView: UIPickerView, didSelectRow row: Int, inComponent component: Int) {
            valueChangedCallback?()
            actualDelegate?.pickerView?(pickerView, didSelectRow: row, inComponent: component)
        }

        func pickerView(_ pickerView: UIPickerView, viewForRow row: Int, forComponent component: Int, reusing view: UIView?) -> UIView {
            actualDelegate?.pickerView?(pickerView, viewForRow: row, forComponent: component, reusing: view) ?? UIView()
        }

        func pickerView(_ pickerView: UIPickerView, rowHeightForComponent component: Int) -> CGFloat {
            actualDelegate?.pickerView?(pickerView, rowHeightForComponent: component) ?? .zero
        }
    }

    /// Combination 15: `didSelectRow`, `viewForRow`, `widthForComponent`
    private class ForwardingPickerViewDelegate15: NSObject, UIPickerViewDelegate {
        weak var actualDelegate: UIPickerViewDelegate?
        private var valueChangedCallback: (() -> Void)?

        init(delegate: UIPickerViewDelegate?, onValueChanged: @escaping () -> Void) {
            actualDelegate = delegate
            valueChangedCallback = onValueChanged
        }

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
    }

    /// Combination 16: `didSelectRow`, `rowHeightForComponent`, `widthForComponent`
    private class ForwardingPickerViewDelegate16: NSObject, UIPickerViewDelegate {
        weak var actualDelegate: UIPickerViewDelegate?
        private var valueChangedCallback: (() -> Void)?

        init(delegate: UIPickerViewDelegate?, onValueChanged: @escaping () -> Void) {
            actualDelegate = delegate
            valueChangedCallback = onValueChanged
        }

        func pickerView(_ pickerView: UIPickerView, didSelectRow row: Int, inComponent component: Int) {
            valueChangedCallback?()
            actualDelegate?.pickerView?(pickerView, didSelectRow: row, inComponent: component)
        }

        func pickerView(_ pickerView: UIPickerView, rowHeightForComponent component: Int) -> CGFloat {
            actualDelegate?.pickerView?(pickerView, rowHeightForComponent: component) ?? .zero
        }

        func pickerView(_ pickerView: UIPickerView, widthForComponent component: Int) -> CGFloat {
            actualDelegate?.pickerView?(pickerView, widthForComponent: component) ?? .zero
        }
    }

    /// Combination 17: `didSelectRow`, `titleForRow`, `attributedTitleForRow`, `viewForRow`
    private class ForwardingPickerViewDelegate17: NSObject, UIPickerViewDelegate {
        weak var actualDelegate: UIPickerViewDelegate?
        private var valueChangedCallback: (() -> Void)?

        init(delegate: UIPickerViewDelegate?, onValueChanged: @escaping () -> Void) {
            actualDelegate = delegate
            valueChangedCallback = onValueChanged
        }

        func pickerView(_ pickerView: UIPickerView, didSelectRow row: Int, inComponent component: Int) {
            valueChangedCallback?()
            actualDelegate?.pickerView?(pickerView, didSelectRow: row, inComponent: component)
        }

        func pickerView(_ pickerView: UIPickerView, titleForRow row: Int, forComponent component: Int) -> String? {
            actualDelegate?.pickerView?(pickerView, titleForRow: row, forComponent: component)
        }

        func pickerView(_ pickerView: UIPickerView, attributedTitleForRow row: Int, forComponent component: Int) -> NSAttributedString? {
            actualDelegate?.pickerView?(pickerView, attributedTitleForRow: row, forComponent: component)
        }

        func pickerView(_ pickerView: UIPickerView, viewForRow row: Int, forComponent component: Int, reusing view: UIView?) -> UIView {
            actualDelegate?.pickerView?(pickerView, viewForRow: row, forComponent: component, reusing: view) ?? UIView()
        }
    }

    /// Combination 18: `didSelectRow`, `titleForRow`, `attributedTitleForRow`, `rowHeightForComponent`
    private class ForwardingPickerViewDelegate18: NSObject, UIPickerViewDelegate {
        weak var actualDelegate: UIPickerViewDelegate?
        private var valueChangedCallback: (() -> Void)?

        init(delegate: UIPickerViewDelegate?, onValueChanged: @escaping () -> Void) {
            actualDelegate = delegate
            valueChangedCallback = onValueChanged
        }

        func pickerView(_ pickerView: UIPickerView, didSelectRow row: Int, inComponent component: Int) {
            valueChangedCallback?()
            actualDelegate?.pickerView?(pickerView, didSelectRow: row, inComponent: component)
        }

        func pickerView(_ pickerView: UIPickerView, titleForRow row: Int, forComponent component: Int) -> String? {
            actualDelegate?.pickerView?(pickerView, titleForRow: row, forComponent: component)
        }

        func pickerView(_ pickerView: UIPickerView, attributedTitleForRow row: Int, forComponent component: Int) -> NSAttributedString? {
            actualDelegate?.pickerView?(pickerView, attributedTitleForRow: row, forComponent: component)
        }

        func pickerView(_ pickerView: UIPickerView, rowHeightForComponent component: Int) -> CGFloat {
            actualDelegate?.pickerView?(pickerView, rowHeightForComponent: component) ?? .zero
        }
    }

    /// Combination 19: `didSelectRow`, `titleForRow`, `attributedTitleForRow`, `widthForComponent`
    private class ForwardingPickerViewDelegate19: NSObject, UIPickerViewDelegate {
        weak var actualDelegate: UIPickerViewDelegate?
        private var valueChangedCallback: (() -> Void)?

        init(delegate: UIPickerViewDelegate?, onValueChanged: @escaping () -> Void) {
            actualDelegate = delegate
            valueChangedCallback = onValueChanged
        }

        func pickerView(_ pickerView: UIPickerView, didSelectRow row: Int, inComponent component: Int) {
            valueChangedCallback?()
            actualDelegate?.pickerView?(pickerView, didSelectRow: row, inComponent: component)
        }

        func pickerView(_ pickerView: UIPickerView, titleForRow row: Int, forComponent component: Int) -> String? {
            actualDelegate?.pickerView?(pickerView, titleForRow: row, forComponent: component)
        }

        func pickerView(_ pickerView: UIPickerView, attributedTitleForRow row: Int, forComponent component: Int) -> NSAttributedString? {
            actualDelegate?.pickerView?(pickerView, attributedTitleForRow: row, forComponent: component)
        }

        func pickerView(_ pickerView: UIPickerView, widthForComponent component: Int) -> CGFloat {
            actualDelegate?.pickerView?(pickerView, widthForComponent: component) ?? .zero
        }
    }

    /// Combination 20: `didSelectRow`, `titleForRow`, `viewForRow`, `rowHeightForComponent`
    private class ForwardingPickerViewDelegate20: NSObject, UIPickerViewDelegate {
        weak var actualDelegate: UIPickerViewDelegate?
        private var valueChangedCallback: (() -> Void)?

        init(delegate: UIPickerViewDelegate?, onValueChanged: @escaping () -> Void) {
            actualDelegate = delegate
            valueChangedCallback = onValueChanged
        }

        func pickerView(_ pickerView: UIPickerView, didSelectRow row: Int, inComponent component: Int) {
            valueChangedCallback?()
            actualDelegate?.pickerView?(pickerView, didSelectRow: row, inComponent: component)
        }

        func pickerView(_ pickerView: UIPickerView, titleForRow row: Int, forComponent component: Int) -> String? {
            actualDelegate?.pickerView?(pickerView, titleForRow: row, forComponent: component)
        }

        func pickerView(_ pickerView: UIPickerView, viewForRow row: Int, forComponent component: Int, reusing view: UIView?) -> UIView {
            actualDelegate?.pickerView?(pickerView, viewForRow: row, forComponent: component, reusing: view) ?? UIView()
        }

        func pickerView(_ pickerView: UIPickerView, rowHeightForComponent component: Int) -> CGFloat {
            actualDelegate?.pickerView?(pickerView, rowHeightForComponent: component) ?? .zero
        }
    }

    /// Combination 21: `didSelectRow`, `titleForRow`, `viewForRow`, `widthForComponent`
    private class ForwardingPickerViewDelegate21: NSObject, UIPickerViewDelegate {
        weak var actualDelegate: UIPickerViewDelegate?
        private var valueChangedCallback: (() -> Void)?

        init(delegate: UIPickerViewDelegate?, onValueChanged: @escaping () -> Void) {
            actualDelegate = delegate
            valueChangedCallback = onValueChanged
        }

        func pickerView(_ pickerView: UIPickerView, didSelectRow row: Int, inComponent component: Int) {
            valueChangedCallback?()
            actualDelegate?.pickerView?(pickerView, didSelectRow: row, inComponent: component)
        }

        func pickerView(_ pickerView: UIPickerView, titleForRow row: Int, forComponent component: Int) -> String? {
            actualDelegate?.pickerView?(pickerView, titleForRow: row, forComponent: component)
        }

        func pickerView(_ pickerView: UIPickerView, viewForRow row: Int, forComponent component: Int, reusing view: UIView?) -> UIView {
            actualDelegate?.pickerView?(pickerView, viewForRow: row, forComponent: component, reusing: view) ?? UIView()
        }

        func pickerView(_ pickerView: UIPickerView, widthForComponent component: Int) -> CGFloat {
            actualDelegate?.pickerView?(pickerView, widthForComponent: component) ?? .zero
        }
    }

    /// Combination 22: `didSelectRow`, `titleForRow`, `rowHeightForComponent`, `widthForComponent`
    private class ForwardingPickerViewDelegate22: NSObject, UIPickerViewDelegate {
        weak var actualDelegate: UIPickerViewDelegate?
        private var valueChangedCallback: (() -> Void)?

        init(delegate: UIPickerViewDelegate?, onValueChanged: @escaping () -> Void) {
            actualDelegate = delegate
            valueChangedCallback = onValueChanged
        }

        func pickerView(_ pickerView: UIPickerView, didSelectRow row: Int, inComponent component: Int) {
            valueChangedCallback?()
            actualDelegate?.pickerView?(pickerView, didSelectRow: row, inComponent: component)
        }

        func pickerView(_ pickerView: UIPickerView, titleForRow row: Int, forComponent component: Int) -> String? {
            actualDelegate?.pickerView?(pickerView, titleForRow: row, forComponent: component)
        }

        func pickerView(_ pickerView: UIPickerView, rowHeightForComponent component: Int) -> CGFloat {
            actualDelegate?.pickerView?(pickerView, rowHeightForComponent: component) ?? .zero
        }

        func pickerView(_ pickerView: UIPickerView, widthForComponent component: Int) -> CGFloat {
            actualDelegate?.pickerView?(pickerView, widthForComponent: component) ?? .zero
        }
    }

    /// Combination 23: `didSelectRow`, `attributedTitleForRow`, `viewForRow`, `rowHeightForComponent`
    private class ForwardingPickerViewDelegate23: NSObject, UIPickerViewDelegate {
        weak var actualDelegate: UIPickerViewDelegate?
        private var valueChangedCallback: (() -> Void)?

        init(delegate: UIPickerViewDelegate?, onValueChanged: @escaping () -> Void) {
            actualDelegate = delegate
            valueChangedCallback = onValueChanged
        }

        func pickerView(_ pickerView: UIPickerView, didSelectRow row: Int, inComponent component: Int) {
            valueChangedCallback?()
            actualDelegate?.pickerView?(pickerView, didSelectRow: row, inComponent: component)
        }

        func pickerView(_ pickerView: UIPickerView, attributedTitleForRow row: Int, forComponent component: Int) -> NSAttributedString? {
            actualDelegate?.pickerView?(pickerView, attributedTitleForRow: row, forComponent: component)
        }

        func pickerView(_ pickerView: UIPickerView, viewForRow row: Int, forComponent component: Int, reusing view: UIView?) -> UIView {
            actualDelegate?.pickerView?(pickerView, viewForRow: row, forComponent: component, reusing: view) ?? UIView()
        }

        func pickerView(_ pickerView: UIPickerView, rowHeightForComponent component: Int) -> CGFloat {
            actualDelegate?.pickerView?(pickerView, rowHeightForComponent: component) ?? .zero
        }
    }

    /// Combination 24: `didSelectRow`,`attributedTitleForRow`, `viewForRow`, `widthForComponent`
    private class ForwardingPickerViewDelegate24: NSObject, UIPickerViewDelegate {
        weak var actualDelegate: UIPickerViewDelegate?
        private var valueChangedCallback: (() -> Void)?

        init(delegate: UIPickerViewDelegate?, onValueChanged: @escaping () -> Void) {
            actualDelegate = delegate
            valueChangedCallback = onValueChanged
        }

        func pickerView(_ pickerView: UIPickerView, didSelectRow row: Int, inComponent component: Int) {
            valueChangedCallback?()
            actualDelegate?.pickerView?(pickerView, didSelectRow: row, inComponent: component)
        }

        func pickerView(_ pickerView: UIPickerView, attributedTitleForRow row: Int, forComponent component: Int) -> NSAttributedString? {
            actualDelegate?.pickerView?(pickerView, attributedTitleForRow: row, forComponent: component)
        }

        func pickerView(_ pickerView: UIPickerView, viewForRow row: Int, forComponent component: Int, reusing view: UIView?) -> UIView {
            actualDelegate?.pickerView?(pickerView, viewForRow: row, forComponent: component, reusing: view) ?? UIView()
        }

        func pickerView(_ pickerView: UIPickerView, widthForComponent component: Int) -> CGFloat {
            actualDelegate?.pickerView?(pickerView, widthForComponent: component) ?? .zero
        }
    }

    /// Combination 25: `didSelectRow`, `attributedTitleForRow`, `rowHeightForComponent`, `widthForComponent`
    private class ForwardingPickerViewDelegate25: NSObject, UIPickerViewDelegate {
        weak var actualDelegate: UIPickerViewDelegate?
        private var valueChangedCallback: (() -> Void)?

        init(delegate: UIPickerViewDelegate?, onValueChanged: @escaping () -> Void) {
            actualDelegate = delegate
            valueChangedCallback = onValueChanged
        }

        func pickerView(_ pickerView: UIPickerView, didSelectRow row: Int, inComponent component: Int) {
            valueChangedCallback?()
            actualDelegate?.pickerView?(pickerView, didSelectRow: row, inComponent: component)
        }

        func pickerView(_ pickerView: UIPickerView, attributedTitleForRow row: Int, forComponent component: Int) -> NSAttributedString? {
            actualDelegate?.pickerView?(pickerView, attributedTitleForRow: row, forComponent: component)
        }

        func pickerView(_ pickerView: UIPickerView, rowHeightForComponent component: Int) -> CGFloat {
            actualDelegate?.pickerView?(pickerView, rowHeightForComponent: component) ?? .zero
        }

        func pickerView(_ pickerView: UIPickerView, widthForComponent component: Int) -> CGFloat {
            actualDelegate?.pickerView?(pickerView, widthForComponent: component) ?? .zero
        }
    }

    /// Combination 26: `didSelectRow`, `viewForRow`, `rowHeightForComponent`, `widthForComponent`
    private class ForwardingPickerViewDelegate26: NSObject, UIPickerViewDelegate {
        weak var actualDelegate: UIPickerViewDelegate?
        private var valueChangedCallback: (() -> Void)?

        init(delegate: UIPickerViewDelegate?, onValueChanged: @escaping () -> Void) {
            actualDelegate = delegate
            valueChangedCallback = onValueChanged
        }

        func pickerView(_ pickerView: UIPickerView, didSelectRow row: Int, inComponent component: Int) {
            valueChangedCallback?()
            actualDelegate?.pickerView?(pickerView, didSelectRow: row, inComponent: component)
        }

        func pickerView(_ pickerView: UIPickerView, viewForRow row: Int, forComponent component: Int, reusing view: UIView?) -> UIView {
            actualDelegate?.pickerView?(pickerView, viewForRow: row, forComponent: component, reusing: view) ?? UIView()
        }

        func pickerView(_ pickerView: UIPickerView, rowHeightForComponent component: Int) -> CGFloat {
            actualDelegate?.pickerView?(pickerView, rowHeightForComponent: component) ?? .zero
        }

        func pickerView(_ pickerView: UIPickerView, widthForComponent component: Int) -> CGFloat {
            actualDelegate?.pickerView?(pickerView, widthForComponent: component) ?? .zero
        }
    }

    /// Combination 27: `didSelectRow`, `titleForRow`, `attributedTitleForRow`, `viewForRow`, `rowHeightForComponent`
    private class ForwardingPickerViewDelegate27: NSObject, UIPickerViewDelegate {
        weak var actualDelegate: UIPickerViewDelegate?
        private var valueChangedCallback: (() -> Void)?

        init(delegate: UIPickerViewDelegate?, onValueChanged: @escaping () -> Void) {
            actualDelegate = delegate
            valueChangedCallback = onValueChanged
        }

        func pickerView(_ pickerView: UIPickerView, didSelectRow row: Int, inComponent component: Int) {
            valueChangedCallback?()
            actualDelegate?.pickerView?(pickerView, didSelectRow: row, inComponent: component)
        }

        func pickerView(_ pickerView: UIPickerView, titleForRow row: Int, forComponent component: Int) -> String? {
            actualDelegate?.pickerView?(pickerView, titleForRow: row, forComponent: component)
        }

        func pickerView(_ pickerView: UIPickerView, attributedTitleForRow row: Int, forComponent component: Int) -> NSAttributedString? {
            actualDelegate?.pickerView?(pickerView, attributedTitleForRow: row, forComponent: component)
        }

        func pickerView(_ pickerView: UIPickerView, viewForRow row: Int, forComponent component: Int, reusing view: UIView?) -> UIView {
            actualDelegate?.pickerView?(pickerView, viewForRow: row, forComponent: component, reusing: view) ?? UIView()
        }

        func pickerView(_ pickerView: UIPickerView, rowHeightForComponent component: Int) -> CGFloat {
            actualDelegate?.pickerView?(pickerView, rowHeightForComponent: component) ?? .zero
        }
    }

    /// Combination 28: `didSelectRow`, `titleForRow`, `attributedTitleForRow`, `viewForRow`, `widthForComponent`
    private class ForwardingPickerViewDelegate28: NSObject, UIPickerViewDelegate {
        weak var actualDelegate: UIPickerViewDelegate?
        private var valueChangedCallback: (() -> Void)?

        init(delegate: UIPickerViewDelegate?, onValueChanged: @escaping () -> Void) {
            actualDelegate = delegate
            valueChangedCallback = onValueChanged
        }

        func pickerView(_ pickerView: UIPickerView, didSelectRow row: Int, inComponent component: Int) {
            valueChangedCallback?()
            actualDelegate?.pickerView?(pickerView, didSelectRow: row, inComponent: component)
        }

        func pickerView(_ pickerView: UIPickerView, titleForRow row: Int, forComponent component: Int) -> String? {
            actualDelegate?.pickerView?(pickerView, titleForRow: row, forComponent: component)
        }

        func pickerView(_ pickerView: UIPickerView, attributedTitleForRow row: Int, forComponent component: Int) -> NSAttributedString? {
            actualDelegate?.pickerView?(pickerView, attributedTitleForRow: row, forComponent: component)
        }

        func pickerView(_ pickerView: UIPickerView, viewForRow row: Int, forComponent component: Int, reusing view: UIView?) -> UIView {
            actualDelegate?.pickerView?(pickerView, viewForRow: row, forComponent: component, reusing: view) ?? UIView()
        }

        func pickerView(_ pickerView: UIPickerView, widthForComponent component: Int) -> CGFloat {
            actualDelegate?.pickerView?(pickerView, widthForComponent: component) ?? .zero
        }
    }

    /// Combination 29: `didSelectRow`, `titleForRow`, `attributedTitleForRow`, `rowHeightForComponent`, `widthForComponent`
    private class ForwardingPickerViewDelegate29: NSObject, UIPickerViewDelegate {
        weak var actualDelegate: UIPickerViewDelegate?
        private var valueChangedCallback: (() -> Void)?

        init(delegate: UIPickerViewDelegate?, onValueChanged: @escaping () -> Void) {
            actualDelegate = delegate
            valueChangedCallback = onValueChanged
        }

        func pickerView(_ pickerView: UIPickerView, didSelectRow row: Int, inComponent component: Int) {
            valueChangedCallback?()
            actualDelegate?.pickerView?(pickerView, didSelectRow: row, inComponent: component)
        }

        func pickerView(_ pickerView: UIPickerView, titleForRow row: Int, forComponent component: Int) -> String? {
            actualDelegate?.pickerView?(pickerView, titleForRow: row, forComponent: component)
        }

        func pickerView(_ pickerView: UIPickerView, attributedTitleForRow row: Int, forComponent component: Int) -> NSAttributedString? {
            actualDelegate?.pickerView?(pickerView, attributedTitleForRow: row, forComponent: component)
        }

        func pickerView(_ pickerView: UIPickerView, rowHeightForComponent component: Int) -> CGFloat {
            actualDelegate?.pickerView?(pickerView, rowHeightForComponent: component) ?? .zero
        }

        func pickerView(_ pickerView: UIPickerView, widthForComponent component: Int) -> CGFloat {
            actualDelegate?.pickerView?(pickerView, widthForComponent: component) ?? .zero
        }
    }

    /// Combination 30: `didSelectRow`, `titleForRow`, `viewForRow`, `rowHeightForComponent`, `widthForComponent`
    private class ForwardingPickerViewDelegate30: NSObject, UIPickerViewDelegate {
        weak var actualDelegate: UIPickerViewDelegate?
        private var valueChangedCallback: (() -> Void)?

        init(delegate: UIPickerViewDelegate?, onValueChanged: @escaping () -> Void) {
            actualDelegate = delegate
            valueChangedCallback = onValueChanged
        }

        func pickerView(_ pickerView: UIPickerView, didSelectRow row: Int, inComponent component: Int) {
            valueChangedCallback?()
            actualDelegate?.pickerView?(pickerView, didSelectRow: row, inComponent: component)
        }

        func pickerView(_ pickerView: UIPickerView, titleForRow row: Int, forComponent component: Int) -> String? {
            actualDelegate?.pickerView?(pickerView, titleForRow: row, forComponent: component)
        }

        func pickerView(_ pickerView: UIPickerView, viewForRow row: Int, forComponent component: Int, reusing view: UIView?) -> UIView {
            actualDelegate?.pickerView?(pickerView, viewForRow: row, forComponent: component, reusing: view) ?? UIView()
        }

        func pickerView(_ pickerView: UIPickerView, rowHeightForComponent component: Int) -> CGFloat {
            actualDelegate?.pickerView?(pickerView, rowHeightForComponent: component) ?? .zero
        }

        func pickerView(_ pickerView: UIPickerView, widthForComponent component: Int) -> CGFloat {
            actualDelegate?.pickerView?(pickerView, widthForComponent: component) ?? .zero
        }
    }

    /// Combination 31: `didSelectRow`, `attributedTitleForRow`, `viewForRow`, `rowHeightForComponent`, `widthForComponent`
    private class ForwardingPickerViewDelegate31: NSObject, UIPickerViewDelegate {
        weak var actualDelegate: UIPickerViewDelegate?
        private var valueChangedCallback: (() -> Void)?

        init(delegate: UIPickerViewDelegate?, onValueChanged: @escaping () -> Void) {
            actualDelegate = delegate
            valueChangedCallback = onValueChanged
        }

        func pickerView(_ pickerView: UIPickerView, didSelectRow row: Int, inComponent component: Int) {
            valueChangedCallback?()
            actualDelegate?.pickerView?(pickerView, didSelectRow: row, inComponent: component)
        }

        func pickerView(_ pickerView: UIPickerView, attributedTitleForRow row: Int, forComponent component: Int) -> NSAttributedString? {
            actualDelegate?.pickerView?(pickerView, attributedTitleForRow: row, forComponent: component)
        }

        func pickerView(_ pickerView: UIPickerView, viewForRow row: Int, forComponent component: Int, reusing view: UIView?) -> UIView {
            actualDelegate?.pickerView?(pickerView, viewForRow: row, forComponent: component, reusing: view) ?? UIView()
        }

        func pickerView(_ pickerView: UIPickerView, rowHeightForComponent component: Int) -> CGFloat {
            actualDelegate?.pickerView?(pickerView, rowHeightForComponent: component) ?? .zero
        }

        func pickerView(_ pickerView: UIPickerView, widthForComponent component: Int) -> CGFloat {
            actualDelegate?.pickerView?(pickerView, widthForComponent: component) ?? .zero
        }
    }

    /// Combination 32: `didSelectRow`, `titleForRow`, `attributedTitleForRow`, `viewForRow`, `rowHeightForComponent`, `widthForComponent`
    private class ForwardingPickerViewDelegate32: NSObject, UIPickerViewDelegate {
        weak var actualDelegate: UIPickerViewDelegate?
        private var valueChangedCallback: (() -> Void)?

        init(delegate: UIPickerViewDelegate?, onValueChanged: @escaping () -> Void) {
            actualDelegate = delegate
            valueChangedCallback = onValueChanged
        }

        func pickerView(_ pickerView: UIPickerView, didSelectRow row: Int, inComponent component: Int) {
            valueChangedCallback?()
            actualDelegate?.pickerView?(pickerView, didSelectRow: row, inComponent: component)
        }

        func pickerView(_ pickerView: UIPickerView, titleForRow row: Int, forComponent component: Int) -> String? {
            actualDelegate?.pickerView?(pickerView, titleForRow: row, forComponent: component)
        }

        func pickerView(_ pickerView: UIPickerView, attributedTitleForRow row: Int, forComponent component: Int) -> NSAttributedString? {
            actualDelegate?.pickerView?(pickerView, attributedTitleForRow: row, forComponent: component)
        }

        func pickerView(_ pickerView: UIPickerView, viewForRow row: Int, forComponent component: Int, reusing view: UIView?) -> UIView {
            actualDelegate?.pickerView?(pickerView, viewForRow: row, forComponent: component, reusing: view) ?? UIView()
        }

        func pickerView(_ pickerView: UIPickerView, rowHeightForComponent component: Int) -> CGFloat {
            actualDelegate?.pickerView?(pickerView, rowHeightForComponent: component) ?? .zero
        }

        func pickerView(_ pickerView: UIPickerView, widthForComponent component: Int) -> CGFloat {
            actualDelegate?.pickerView?(pickerView, widthForComponent: component) ?? .zero
        }
    }

#endif

// swiftlint:enable cyclomatic_complexity
