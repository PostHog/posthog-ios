---
'posthog-ios': major
---

**Breaking:** send events to capture V1 (`/i/v1/analytics/events`) with the project token in an `Authorization: Bearer` header.

- If you use a reverse proxy, forward `/i/v1/analytics/events`. A 404 falls back to `/batch` until the app restarts; other errors such as 403 or 405 drop the events.
- Capture requests replace any `Authorization` header from `requestHeaders`, so authenticate your proxy with a different header.
- Only a 307 or 308 redirect to the same origin as `host` is followed, at most 5 times. Other redirects drop the events, so point `host` at the final host.
- 429 responses are no longer retried, and `Retry-After` pauses sending for at most 30 seconds, including session replay and logs.
- The `$process_person_profile`, `$cookieless_mode`, `$ignore_sent_at` and `$product_tour_id` properties are sent as capture options, and PostHog drops an event whose option value it can't read.
