---
'posthog-ios': patch
---

Avoid a crash in the flags and remote-config API handlers when the URL response is not an `HTTPURLResponse` (previously force-cast); the SDK now logs and returns gracefully instead.
