---
"posthog-ios": minor
---

Auto-attach `$screen_name` to every captured event after `PostHogSDK.shared.screen()` has been called, or whenever screen auto-capture is on (default). Cached value is cleared by `reset()` and `close()`. To opt out, set `PostHogConfig.captureScreenViews = false` and avoid calling `screen()` manually. Behavior change: existing events from `captureException`, `identify`, etc. will start carrying `$screen_name` for users who hadn't disabled screen capture. Closes posthog-android#119.
