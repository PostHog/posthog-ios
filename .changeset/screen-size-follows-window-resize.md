---
'posthog-ios': patch
---

Fix `$screen_width` and `$screen_height` staying stale after a window resize that neither rotates the device nor makes another window key, such as folding or unfolding a foldable, a Stage Manager drag, or an iPad split-view change.
