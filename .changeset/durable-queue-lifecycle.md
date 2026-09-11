---
"posthog-ios": minor
---

- Preserve bounded durable event, replay, and log queues across retryable upload failures instead of clearing them.
- Limit `maxRetries` to push-subscription registration; it no longer bounds event, replay, or log queue flush attempts.
- Acknowledge successful and terminal uploads by their exact persisted entry identities so full-queue replacements accepted during an upload are not deleted.
- Trim persisted queues to `maxQueueSize` (or `logs.maxBufferSize` for logs) in FIFO order when loading them from disk.
- Honor the received HTTP status and `Retry-After` when an upload also returns a transport error: successful and terminal responses remove the sent entries, while retryable responses retain them. A `3xx` left on a failed request is reported as no status, because a redirect does not confirm delivery to the final host.
- Preserve existing queued records when writing a new record to a full queue fails.
- Retry push-subscription requests that answer with HTTP 408 instead of treating the timeout as terminal, so a pending logout unregister survives until it succeeds.
