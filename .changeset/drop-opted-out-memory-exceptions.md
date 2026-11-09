---
'posthog-ios': patch
---

On iOS 27+, an out-of-memory termination recorded after `optOut()` is no longer sent as `$exception` after the next `optIn()`. One from a session that was opted in is still delivered, and one with no saved context carries no consent signal and is still sent.
