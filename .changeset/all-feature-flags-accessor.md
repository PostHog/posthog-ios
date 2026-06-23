---
'posthog-ios': minor
---

Add `PostHogSDK.getAllFeatureFlags()` returning all loaded flags as `[PostHogFeatureFlagResult]` (key, enabled, variant, payload). Exposed to Objective-C via `@objc`.
