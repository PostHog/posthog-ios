---
"posthog-ios": patch
---

`reloadFeatureFlags(_:)` now always invokes its completion callback, including when the SDK is disabled/opted-out or when no remote config is available. Previously these early-returns skipped the callback, which could leave callers that await it (e.g. the Flutter SDK's `reloadFeatureFlags`) hanging indefinitely.
