---
'posthog-ios': major
---

**Breaking:** remove the `PostHogSDK.didReceiveFeatureFlags` notification. Use `PostHogSDK.shared.onFeatureFlags(_:)` instead (`[[PostHogSDK shared] onFeatureFlags:]` in Objective-C). It runs on the main thread after each flag load, receives a `PostHogFeatureFlagsLoaded` with the flags and whether loading failed, and returns a subscription you can `unsubscribe()`.
