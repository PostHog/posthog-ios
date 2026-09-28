---
'posthog-ios': minor
---

Add the `PostHogAI` library, which captures Apple Foundation Models calls as `$ai_generation` events on iOS 27 and later. In privacy mode, failed turns still set `$ai_is_error` but omit the `$ai_error` string.
