---
"posthog-ios": patch
---

Retry capture delivery on transient HTTP errors and respect Retry-After responses while preserving queued events across retries.
