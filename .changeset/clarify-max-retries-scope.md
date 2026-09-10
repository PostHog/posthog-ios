---
"posthog-ios": patch
---

Clarify that `maxRetries` limits push-subscription registration retries. Retryable event, replay, and log ingestion failures retain queued records for later flush attempts with backoff. Use `maxQueueSize` for event/replay capacity and `logs.maxBufferSize` for log capacity.
