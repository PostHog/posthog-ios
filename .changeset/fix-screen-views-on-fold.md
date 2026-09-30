---
"posthog-ios": patch
---

Fix automatic screen views capturing duplicate or wrongly named `$screen` events, such as SwiftUI's `_UnaryViewAdaptor<EmptyView>` placeholder, when the device is rotated, folded or unfolded. A screen that appears again without the visible screen changing is no longer captured twice, so navigating inside a split view that shows several columns no longer repeats the split view's `$screen` event. To track the screens inside a column of such a split view, call `screen()` manually.
