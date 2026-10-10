---
"posthog-ios": patch
---

Ignore `group(type:key:)` calls with an empty `type` or `key`. Previously they stored the empty group on later events and sent an invalid `$groupidentify`; now the call does nothing and logs a debug message
