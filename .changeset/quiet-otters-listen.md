---
'posthog-ios': patch
---

Omit null-valued custom object properties recursively when serializing events for delivery and disk queues, while preserving null array entries.
