---
"posthog-ios": minor
---

Rage click detection no longer emits `$rageclick` on controls where rapid repeated taps are intentional rather than frustration — the on-screen keyboard, text fields and text selection, steppers, sliders, pickers, date pickers, segmented controls and page controls. This applies to UIKit, React Native, and SwiftUI. You can exclude a custom control with the `ph-no-rageclick` accessibility identifier/label (UIKit/React Native) or the `.postHogNoRageClick()` view modifier (SwiftUI).
