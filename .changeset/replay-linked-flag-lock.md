---
"posthog-ios": patch
---

Fix a deadlock when session replay is linked to a feature flag. The `$feature_flag_called` capture now runs after `sessionReplayLock` is released, so setup and replay config can no longer wait on each other.
