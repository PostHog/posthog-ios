---
"posthog-ios": patch
---

Persist the person properties deduplication hash, so a repeated `identify()` or `setPersonProperties()` call with unchanged properties no longer sends a new `$set` event after each app relaunch.
