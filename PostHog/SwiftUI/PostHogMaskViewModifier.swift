//
//  PostHogMaskViewModifier.swift
//  PostHog
//
//  Created by Yiannis Josephides on 09/10/2024.
//

#if os(iOS) && canImport(SwiftUI)

    import SwiftUI

    /// SwiftUI session replay masking helpers.
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
                    onChange: { owner, views, layers in
                        views.forEach { $0.setPostHogNoCapture(isEnabled, owner: owner) }
                        layers.forEach { $0.setPostHogNoCapture(isEnabled, owner: owner) }
                    },
                    onRemove: { owner, views, layers in
                        views.forEach { $0.setPostHogNoCapture(false, owner: owner) }
                        layers.forEach { $0.setPostHogNoCapture(false, owner: owner) }
                    }
                )
            )
        }
    }

    /// Ref-counted flag ownership. A target can be claimed by several masks at once —
    /// overlapping target sets are the norm on iOS 26, where masks resolve against the
    /// shared hosting view — so a plain Boolean flag would let one mask's teardown
    /// (e.g. a lazy row scrolling offscreen) unmask targets still owned by another.
    /// A target stays flagged for as long as at least one owner claims it.
    final class PostHogFlagOwners {
        var owners: Set<ObjectIdentifier> = []
    }

    extension NSObject {
        func isPostHogFlagOwned(_ key: UnsafeRawPointer) -> Bool {
            (objc_getAssociatedObject(self, key) as? PostHogFlagOwners)?.owners.isEmpty == false
        }

        func setPostHogFlag(_ key: UnsafeRawPointer, enabled: Bool, owner: ObjectIdentifier) {
            let box: PostHogFlagOwners
            if let existing = objc_getAssociatedObject(self, key) as? PostHogFlagOwners {
                box = existing
            } else {
                box = PostHogFlagOwners()
                objc_setAssociatedObject(self, key, box, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
            }
            if enabled {
                box.owners.insert(owner)
            } else {
                box.owners.remove(owner)
            }
        }
    }

    extension UIView {
        /// Whether at least one mask currently claims this view.
        var postHogNoCapture: Bool {
            isPostHogFlagOwned(&AssociatedKeys.phNoCapture)
        }

        func setPostHogNoCapture(_ enabled: Bool, owner: ObjectIdentifier) {
            setPostHogFlag(&AssociatedKeys.phNoCapture, enabled: enabled, owner: owner)
        }
    }

    extension CALayer {
        /// Whether at least one mask currently claims this layer.
        var postHogNoCapture: Bool {
            isPostHogFlagOwned(&AssociatedKeys.phNoCapture)
        }

        func setPostHogNoCapture(_ enabled: Bool, owner: ObjectIdentifier) {
            setPostHogFlag(&AssociatedKeys.phNoCapture, enabled: enabled, owner: owner)
        }
    }
#endif
