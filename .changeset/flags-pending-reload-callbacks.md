---
"posthog-ios": minor
---

Fix feature flag reloads resolving a caller's completion handler with stale, pre-override cached flags. Only one queued `/flags` reload was kept while another was in flight, so a third reload displaced the queued one and immediately resolved its completion handler from the disk cache — flags that never saw the caller's request-time person properties. The queued reload now retains every displaced caller's completion handler, so each one resolves against a `/flags` response that actually went out.

Adds `setPersonPropertiesForFlags(_:reloadFeatureFlags:completion:)` so apps can await flags evaluated with their person-property overrides, and documents the startup ordering contract on it and on `PostHogConfig.preloadFeatureFlags`: the automatic preload is not ordered against app-set overrides, and `reset()` clears them.

Also fixes a lock-order inversion in `getPersonPropertiesForFlags()`, which resolved default person properties while holding `personPropertiesForFlagsLock` even though that callback reaches `setupLock`, which `setup()` holds while acquiring `personPropertiesForFlagsLock`.
