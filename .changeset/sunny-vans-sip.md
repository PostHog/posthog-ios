---
"posthog-ios": patch
---

Keep the background colour of enclosing views under a `postHogMask()` region and draw SwiftUI text `*` rows in grey when `screenshotModeGPUCapture` is on, so masked text no longer uploads as a solid black box; colours belonging to the masked view itself stay black.
