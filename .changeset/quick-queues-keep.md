---
"posthog-ios": patch
---

Stop dropping the whole on-disk event queue after a brief network outage. A transport failure (lost connectivity, timeout, no route) now keeps every buffered event and lets `maxQueueSize` bound the queue, instead of wiping it once a few retries exceeded `maxRetries`. A full queue drop is now reserved for a responsive-but-unhealthy backend that keeps rejecting batches past the new `maxRetryWindowSeconds` window (default 24 hours), and every drop emits a `$queue_records_dropped` diagnostic event so the loss is measurable.
