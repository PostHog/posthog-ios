//
//  PostHogMaskViewModifier.swift
//  PostHog
//
//  Created by Yiannis Josephides on 09/10/2024.
//

#if os(iOS) && canImport(SwiftUI)

    import SwiftUI

    public extension View {
        /**
         Marks a SwiftUI View to be masked in PostHog session replay recordings.

         Note: On iOS 26+ (Xcode 26 SwiftUI rendering engine), SwiftUI views may no longer map
         reliably to a backing `UIView`, so this modifier may behave inconsistently. A future SDK
         update will try to address this limitation, but for now, we recommend using this modifier
         with caution.

         Because of the nature of how we intercept SwiftUI view hierarchy (and how it maps to UIKit),
         we can't always be 100% confident that a view should be masked and may accidentally mark a
         sensitive view as non-sensitive instead.

         Use this modifier to explicitly mask sensitive views in session replay recordings.

         For example:
         ```swift
         // This view will be masked in recordings
         SensitiveDataView()
            .postHogMask()

         // Conditionally mask based on a flag
         SensitiveDataView()
            .postHogMask(shouldMask)
         ```

         - Parameter isEnabled: Whether masking should be enabled. Defaults to true.
         - Returns: A modified view that will be masked in session replay recordings when enabled
         */
        func postHogMask(_ isEnabled: Bool = true) -> some View {
            modifier(
                PostHogTagViewModifier(
                    onChange: { views, layers in
                        views.forEach { $0.postHogNoCapture = isEnabled }
                        layers.forEach { $0.postHogNoCapture = isEnabled }
                    },
                    onRemove: { views, layers in
                        views.forEach { $0.postHogNoCapture = false }
                        layers.forEach { $0.postHogNoCapture = false }
                    }
                )
            )
        }
    }

    extension UIView {
        var postHogNoCapture: Bool {
            get { objc_getAssociatedObject(self, &AssociatedKeys.phNoCapture) as? Bool ?? false }
            set { objc_setAssociatedObject(self, &AssociatedKeys.phNoCapture, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC) }
        }
    }

    extension CALayer {
        var postHogNoCapture: Bool {
            get { objc_getAssociatedObject(self, &AssociatedKeys.phNoCapture) as? Bool ?? false }
            set { objc_setAssociatedObject(self, &AssociatedKeys.phNoCapture, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC) }
        }
    }
#endif
