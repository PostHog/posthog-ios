//
//  PostHogNoMaskViewModifier.swift
//  PostHog
//
//  Created by Yiannis Josephides on 09/10/2024.
//

#if os(iOS) && canImport(SwiftUI)

    import SwiftUI

    public extension View {
        /**
         Marks a SwiftUI View to be excluded from masking in PostHog session replay recordings.

         There are cases where PostHog SDK will unintentionally mask some SwiftUI views.

         Because of the nature of how we intercept SwiftUI view hierarchy (and how it maps to UIKit),
         we can't always be 100% confident that a view should be masked. For that reason, we prefer to
         take a proactive and prefer to mask views if we're not sure.

         Use this modifier to prevent views from being masked in session replay recordings.

         For example:
         ```swift
         // This view may be accidentally masked by PostHog SDK
         SomeSafeView()

         // This custom view (and all its subviews) will not be masked in recordings
         SomeSafeView()
           .postHogNoMask()
         ```

         - Returns: A modified view that will not be masked in session replay recordings
         */
        func postHogNoMask() -> some View {
            modifier(
                PostHogTagViewModifier { uiViews in
                    uiViews.forEach { $0.postHogNoMask = true }
                } onRemove: { uiViews in
                    uiViews.forEach { $0.postHogNoMask = false }
                }
            )
        }
    }

    extension UIView {
        var postHogNoMask: Bool {
            get { objc_getAssociatedObject(self, &AssociatedKeys.phNoMask) as? Bool ?? false }
            set { objc_setAssociatedObject(self, &AssociatedKeys.phNoMask, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC) }
        }
    }

#endif
