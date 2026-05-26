---
"posthog-ios": minor
---

Auto-attach `$screen_name` to every captured event after `PostHogSDK.shared.screen()` has been called (manually or via screen-view auto-capture). Cached value is cleared by `reset()` and `close()`.

**To opt out of `$screen_name` stamping entirely**, set `PostHogConfig.captureScreenViews = false` **and** stop calling `screen()` manually. Disabling `captureScreenViews` alone is not sufficient — a single manual `screen("Home")` call will re-enable stamping.