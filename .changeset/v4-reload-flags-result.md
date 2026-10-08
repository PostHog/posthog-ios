---
'posthog-ios': major
---

**Breaking:** `reloadFeatureFlags(_:)` now passes a `PostHogFeatureFlagsLoaded` to its callback, so you can tell whether the reload failed.

`errorsLoading` is `true` when the request failed or the SDK isn't set up, and `flags` and `variants` then hold the last known values. Update closures from `{ ... }` to `{ result in ... }` (or `{ _ in ... }`). In Objective-C, the block now takes a `PostHogFeatureFlagsLoaded *` argument.
