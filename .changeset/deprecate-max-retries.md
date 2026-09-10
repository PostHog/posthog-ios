---
"posthog-ios": minor
---

Deprecate `PostHogConfig.maxRetries`: ingestion retries are not count-limited. Use `maxQueueSize` for events and replay, and `logs.maxBufferSize` for logs. This option still controls push subscription registration retries.
