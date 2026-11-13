---
"posthog-ios": patch
---

Keep tracking foreground and background transitions after `reset()`. Previously `reset()` unsubscribed the session manager from app lifecycle and UI events, so sessions stopped clearing in the background, or were never created again after a reset in the background, until the app restarted.
