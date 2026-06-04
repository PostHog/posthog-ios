---
"posthog-ios": patch
---

Keep session replay recording, error-tracking autocapture, and network performance capture active after an in-session `identify()`/`reset()` instead of disabling them until the next app restart. The project-level recording, error-tracking, and capture-performance config is now preserved across `reset()` and re-armed on the next `/flags` reload.
