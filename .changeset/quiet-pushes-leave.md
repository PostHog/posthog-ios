---
"posthog-ios": patch
---

Unregister a push token from the previous distinct id when it moves to one that is not merged with it (`identify()` with `reuseAnonymousId`, or an identity change while opted out), so pushes sent to the previous person no longer reach the device. A normal `identify()` from an anonymous user still keeps a single subscription on the merged person
