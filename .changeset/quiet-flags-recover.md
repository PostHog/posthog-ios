---
"posthog-ios": patch
---

Treat failed detailed feature flag records as unavailable instead of serving their placeholder values or payloads, including previously persisted placeholders. Preserve successful cached results on response-wide errors and retain failed-read evaluation diagnostics across restarts.
