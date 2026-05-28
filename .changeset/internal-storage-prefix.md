---
"posthog-ios": patch
---

Add an internal `@_spi(PostHogInternal)` `storagePrefix` config to override the on-disk storage directory (used by the SDK compliance test harness for per-test isolation). Not part of the public API; default behavior is unchanged.
