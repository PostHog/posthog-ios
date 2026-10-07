---
'posthog-ios': major
---

**Breaking:** return `nil` instead of the raw string for a malformed, empty or whitespace-only feature flag payload from `getFeatureFlagResult(_:)` and `getAllFeatureFlags()`. If you read a malformed payload as a `String`, fix the payload JSON in PostHog. String payloads passed to `PostHogBootstrapConfig.featureFlagPayloads` are no longer JSON-decoded a second time, so a bootstrapped `"123"` stays a `String`.
