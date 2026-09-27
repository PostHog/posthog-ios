---
'posthog-ios': patch
---

Respect a caller-supplied `$process_person_profile: false` on `capture` and `screen` for identified users, matching posthog-android. Previously the SDK's own value overwrote it after `identify`, so the event was processed as identified.
