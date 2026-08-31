---
"posthog-ios": patch
---

Preserve bounded durable event, replay, and log queues across retryable upload failures, and acknowledge successful batches by their exact persisted entry identities.
