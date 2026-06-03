---
"posthog-ios": patch
---

Keep session replay recording and error-tracking autocapture active after an in-session `identify()`/`reset()` instead of disabling them until the next app restart. The project-level recording and error-tracking config is now preserved across `reset()` and re-armed on the next `/flags` reload, matching posthog-android.
