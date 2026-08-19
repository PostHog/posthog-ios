---
"posthog-ios": patch
---

Fix feature flag reloads resolving a caller's completion handler with stale, pre-override cached flags. Only one queued `/flags` reload was kept while another was in flight, so a third reload displaced the queued one and immediately resolved its completion handler from the disk cache — flags that never saw the caller's request-time person properties. The queued reload now retains every displaced caller's completion handler, so each one resolves against a `/flags` response that actually went out.

Documents the startup ordering contract on `setPersonPropertiesForFlags(_:reloadFeatureFlags:)` and `PostHogConfig.preloadFeatureFlags`: the automatic preload is not ordered against app-set properties, `reset()` clears them, and reading a flag that is guaranteed to reflect them means setting with `reloadFeatureFlags: false` and waiting for an explicit `reloadFeatureFlags(_:)`.

A displaced completion handler now waits for a `/flags` round trip, including any retries, where it previously resolved almost immediately from the cache. Apps that gate UI on `reloadFeatureFlags(_:)` will see it fire later than before — with values that reflect the caller's context rather than stale ones.

Also hardens `getPersonPropertiesForFlags()` so it no longer holds `personPropertiesForFlagsLock` across a call that reaches `setupLock`.
