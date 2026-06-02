---
"posthog-ios": patch
---

Keep session replay recording active after an in-session `identify()`/`reset()` instead of disabling it until the next app restart.
