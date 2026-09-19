---
"posthog-ios": minor
---

Add opt-in SwiftUI tap autocapture with `captureSwiftUIElementInteractions`, disabled by default and independent of `captureElementInteractions`. Enable it for element-level SwiftUI labels and accessibility identifiers; opting in changes SwiftUI tap recognition and element chains. Existing interaction autocapture behavior is preserved when the new option is disabled.
