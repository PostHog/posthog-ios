#if os(iOS)
    import Foundation
    import UIKit

    enum ViewLayoutTracker {
        private(set) static var hasChanges = false
        private static var hasSwizzled = false

        static func viewDidLayout(view _: UIView) {
            hasChanges = true
        }

        static func clear() {
            hasChanges = false
        }

        static func swizzleLayoutSubviews() {
            if hasSwizzled {
                return
            }
            swizzle(forClass: UIView.self,
                    original: #selector(UIView.layoutSubviews),
                    new: #selector(UIView.layoutSubviewsOverride))
            hasSwizzled = true
        }

        static func unSwizzleLayoutSubviews() {
            if !hasSwizzled {
                return
            }
            swizzle(forClass: UIView.self,
                    original: #selector(UIView.layoutSubviews),
                    new: #selector(UIView.layoutSubviewsOverride))
            hasSwizzled = false
        }
    }

    extension UIView {
        @objc func layoutSubviewsOverride() {
            guard Thread.isMainThread else {
                return
            }
            layoutSubviewsOverride()
            ViewLayoutTracker.viewDidLayout(view: self)
        }
    }

#endif
