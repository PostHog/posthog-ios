---
'posthog-ios': major
---

**Breaking:** send analytics events to `/i/v1/analytics/events` (capture V1) with the project token as an `Authorization: Bearer` header. Events the server accepts, warns about or drops are removed from the queue, and only the events it asks to retry are resent. Only HTTP 408, 500, 502, 503 and 504 (and network errors) are retried; 429 and redirects are no longer retried. If the host returns 404 for the new endpoint, the SDK falls back to `/batch` until the app restarts.
