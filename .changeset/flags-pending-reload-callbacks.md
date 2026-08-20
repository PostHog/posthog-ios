---
"posthog-ios": patch
---

Fix `reloadFeatureFlags(_:)` completion handlers resolving with stale cached flags when a reload was displaced from the pending queue. They now resolve against a `/flags` response that actually went out, so they fire later — after a round trip and any retries — but with flags evaluated for the caller's request-time person properties.
