---
'posthog-ios': patch
---

A `/flags` load still in flight when `reset()` runs no longer writes the previous user's flags into the cache, calls `onFeatureFlags` listeners, posts `didReceiveFeatureFlags`, or is replayed to a listener registered later. The reload `reset()` starts still runs, and a `reloadFeatureFlags` callback waiting on the dropped load is called when that reload finishes.
