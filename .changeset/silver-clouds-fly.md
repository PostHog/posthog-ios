---
"posthog-ios": minor
---

Rage click detection no longer emits `$rageclick` on controls where rapid repeated taps are intentional rather than frustration — the on-screen keyboard, text fields and text selection, steppers, sliders, pickers, date pickers, segmented controls and page controls. This applies to UIKit and SwiftUI. You can exclude a custom control with the `ph-no-rageclick` accessibility identifier/label (UIKit) or the `.postHogNoRageClick()` view modifier (SwiftUI).
