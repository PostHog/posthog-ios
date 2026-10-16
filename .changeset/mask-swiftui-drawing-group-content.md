---
"posthog-ios": patch
---

Mask SwiftUI `.drawingGroup()` and `Canvas` content in screenshot session replay when `maskAllTextInputs` or `maskAllImages` is enabled. Previously, text and images in a drawing group or Canvas were uploaded unmasked.
