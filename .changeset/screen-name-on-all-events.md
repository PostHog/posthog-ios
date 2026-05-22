---
"posthog-ios": minor
---

Auto-attach `$screen_name` to every captured event after `PostHogSDK.shared.screen()` has been called, or whenever screen auto-capture is on (default). Cached value is cleared by `reset()` and `close()`. To opt out, set `PostHogConfig.captureScreenViews = false` and avoid calling `screen()` manually. Closes posthog-android#119.

Additional behavior changes:

- `screen()` now sanitizes SwiftUI wrappers before emitting: `$screen` events on SwiftUI apps will carry `"MyView"` instead of `"UIHostingController<MyView>"`. Same applies to the `$screen_name` cached on subsequent events.
- `screen("")` and `screen("AnyView")` (and anything that sanitizes to an empty/`AnyView`-only name) are silently dropped — no `$screen` event, cache untouched.
- Caller-supplied `$screen_name` in `properties` now wins on the `$screen` event itself (previously the `screenTitle` arg won), matching the cross-event override on `capture()` and aligning with Android.
- Existing events from `captureException`, `identify`, etc. will start carrying `$screen_name` for users who hadn't disabled screen capture.
