---
'posthog-ios': minor
---

Add `isFeatureEnabled(_:defaultValue:sendFeatureFlagEvent:)` overload that returns a caller-supplied default for an absent flag while still capturing `$feature_flag_called`, matching posthog-android.
