//
//  View+PostHogNoRageClick.swift
//  PostHog
//
//  Created by Ioannis Josephides on 10/06/2026.
//

#if os(iOS) && canImport(SwiftUI)

    import SwiftUI

    /// SwiftUI rage click helpers.
    public extension View {
        /**
         Excludes a SwiftUI View from PostHog rage click detection.

         Rapid repeated taps on this view (and its descendants) will not be captured as a
         `$rageclick` event. Use this for controls where fast repeated tapping is intentional but
         not auto-detected as a UIKit control — for example a custom-built stepper or carousel arrow.

         For example:
         ```swift
         // Taps on this control won't trigger rage clicks
         CustomStepper()
            .postHogNoRageClick()

         // Conditionally opt out based on a flag
         CustomStepper()
            .postHogNoRageClick(shouldExclude)
         ```

         - Parameter isEnabled: Whether the view should be excluded from rage click detection. Defaults to true.
         - Returns: A modified view that is excluded from rage click detection when enabled.
         */
        func postHogNoRageClick(_ isEnabled: Bool = true) -> some View {
            modifier(
                PostHogTagViewModifier(
                    onChange: { views, layers in
                        // On iOS 26, SwiftUI primitives may be layer-backed, so tag both.
                        views.forEach { $0.postHogNoRageClick = isEnabled }
                        layers.forEach { $0.postHogNoRageClick = isEnabled }
                    },
                    onRemove: { views, layers in
                        views.forEach { $0.postHogNoRageClick = false }
                        layers.forEach { $0.postHogNoRageClick = false }
                    }
                )
            )
        }
    }
#endif
