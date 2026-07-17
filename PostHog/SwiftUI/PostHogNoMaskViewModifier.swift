//
//  PostHogNoMaskViewModifier.swift
//  PostHog
//
//  Created by Yiannis Josephides on 09/10/2024.
//

#if os(iOS) && canImport(SwiftUI)

    import SwiftUI

    /// SwiftUI session replay unmasking helpers.
    public extension View {
        /**
         Marks a SwiftUI View to be excluded from masking in PostHog session replay recordings.

         Note: On iOS 26+ (Xcode 26 SwiftUI rendering engine), SwiftUI views may no longer map
         reliably to a backing `UIView`, so this modifier may behave inconsistently. A future SDK
         update will try to address this limitation, but for now, we recommend using this modifier
         with caution.

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
                PostHogTagViewModifier(
                    onChange: { owner, views, layers in
                        views.forEach { $0.setPostHogNoMask(true, owner: owner) }
                        layers.forEach { $0.setPostHogNoMask(true, owner: owner) }
                    },
                    onRemove: { owner, views, layers in
                        views.forEach { $0.setPostHogNoMask(false, owner: owner) }
                        layers.forEach { $0.setPostHogNoMask(false, owner: owner) }
                    }
                )
            )
        }
    }

    // Same ref-counted ownership as `postHogNoCapture` (see PostHogFlagOwners):
    // overlapping no-mask regions must not clear each other on teardown.
    extension UIView {
        var postHogNoMask: Bool {
            isPostHogFlagOwned(&AssociatedKeys.phNoMask)
        }

        func setPostHogNoMask(_ enabled: Bool, owner: ObjectIdentifier) {
            setPostHogFlag(&AssociatedKeys.phNoMask, enabled: enabled, owner: owner)
        }
    }

    extension CALayer {
        var postHogNoMask: Bool {
            isPostHogFlagOwned(&AssociatedKeys.phNoMask)
        }

        func setPostHogNoMask(_ enabled: Bool, owner: ObjectIdentifier) {
            setPostHogFlag(&AssociatedKeys.phNoMask, enabled: enabled, owner: owner)
        }
    }

#endif
