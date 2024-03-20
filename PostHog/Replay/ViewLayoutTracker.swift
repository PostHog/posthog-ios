#if os(iOS) || os(tvOS)
    import Foundation
    import UIKit

    enum ViewLayoutTracker {
        static var hasChanges = false
        static var hasSwizzled = false

        static func viewDidLayout(view _: UIView) {
            ViewLayoutTracker.hasChanges = true
        }

        static func clear() {
            ViewLayoutTracker.hasChanges = false
        }

        static func swizzleLayoutSubviews() {
            if ViewLayoutTracker.hasSwizzled {
                return
            }
            hasSwizzled = true
            UIViewController.swizzle(forClass: UIView.self,
                                     original: #selector(UIView.layoutSubviews),
                                     new: #selector(UIView.ph_layoutSubviews))
        }

        static func unSwizzleLayoutSubviews() {
            if !ViewLayoutTracker.hasSwizzled {
                return
            }
            hasSwizzled = false
            UIViewController.swizzle(forClass: UIView.self,
                                     original: #selector(UIView.ph_layoutSubviews),
                                     new: #selector(UIView.layoutSubviews))
        }
    }

    extension UIView {
        @objc func ph_layoutSubviews() {
            guard Thread.isMainThread else {
                return
            }
            ph_layoutSubviews()
            ViewLayoutTracker.viewDidLayout(view: self)
        }
    }

#endif
