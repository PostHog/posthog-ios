---
"posthog-ios": patch
---

Ignore `group(type:key:)` calls with an empty `type` or `key` instead of storing and sending an invalid group
