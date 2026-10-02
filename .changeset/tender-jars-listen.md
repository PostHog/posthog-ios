---
'posthog-ios': patch
---

Session replay and surveys no longer swizzle `UIView.layoutSublayers(of:)`. Capture is now scheduled from an observer on the main run loop, and session replay skips rendering while the screen keeps producing identical frames. Surveys no longer require swizzling, so apps that set `enableSwizzling` to `false` now get surveys instead of having the integration skipped.
