---
"posthog-ios": patch
---

Fix `postHogMask()` causing severe launch and scroll hangs on iOS 26 in lazy SwiftUI containers (`ScrollView` + `LazyVStack`). The modifier now reports its region through a single passive overlay view whose frame is read live at snapshot time, replacing the per-mask tag-view traversal and KVO ancestor observers that degenerated to O(N²) work on the shared hosting view. Behavior notes: a masked view is now redacted across its full extent (previously only its resolved backing subviews), and screenshot snapshots are skipped while a masked view awaits its first layout, so a frame can never be captured under-masked. Also fixes overlapping masks unmasking each other's targets on teardown, flag claims outliving their owner view, and bounds the iOS 26 layer scan to the masked view's own extent.
