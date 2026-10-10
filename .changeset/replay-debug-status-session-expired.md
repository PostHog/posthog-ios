---
"posthog-ios": patch
---

Fix `$recording_status` reporting `active` after a backgrounded session times out, while `isSessionReplayActive()` returns `false`
