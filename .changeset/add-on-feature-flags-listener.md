---
'posthog-ios': minor
---

Add `PostHogSDK.onFeatureFlags(_:)` to run a callback on the main thread whenever feature flags load or change, including from bootstrap values. The callback receives a `PostHogFeatureFlagsLoaded` with the enabled flag keys, their values and whether loading failed, and runs shortly after you register if flags have already loaded. Call `unsubscribe()` on the returned `PostHogFeatureFlagsSubscription` to stop listening.
