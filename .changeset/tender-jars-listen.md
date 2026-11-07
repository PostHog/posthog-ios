---
'posthog-ios': minor
---

Session replay and surveys no longer swizzle `UIView.layoutSublayers(of:)`. Capture is now scheduled from an observer on the main run loop, and session replay skips rendering while the screen keeps producing identical frames. Wireframe mode now skips unchanged frames too, so idle screens send fewer `$snapshot` events. Surveys no longer require swizzling, so apps that set `enableSwizzling` to `false` now get surveys instead of having the integration skipped.
