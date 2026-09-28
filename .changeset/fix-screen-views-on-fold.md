---
"posthog-ios": patch
---

Fix automatic screen views capturing duplicate or wrongly named `$screen` events, such as SwiftUI placeholders like `_UnaryViewAdaptor<EmptyView>`, when the device is rotated, folded or unfolded without navigating. A screen that appears again without the visible screen changing is no longer captured twice, so navigating inside a split view that shows several columns no longer repeats the split view's `$screen` event.
