---
'posthog-ios': major
---

**Breaking:** send events to capture V1 (`/i/v1/analytics/events`) with the project token in an `Authorization: Bearer` header.

- If you use a reverse proxy or self-host PostHog, make sure `/i/v1/analytics/events` is served: a 404 or other non-retriable response drops the events.
- Capture requests replace any `Authorization` header from `requestHeaders`, so authenticate your proxy with a different header.
- Only a 307 or 308 redirect to the same origin as `host` is followed, at most 5 times. Other redirects drop the events, so point `host` at the final host.
- 429 responses are no longer retried, and `Retry-After` pauses sending for at most 30 seconds, including session replay and logs.
- After a failed send, the wait before the next one now doubles from 1 second up to 30 seconds, with up to 25% random jitter, instead of growing by 1 second per failure. This applies to events, session replay and logs, and queued records are still kept until they're delivered.
- `maxRetries` is renamed to `pushNotificationSubscriptionMaxRetries`, because it only limits push-notification subscription retries. Event, session replay and log retries still have no limit.
- The `$process_person_profile`, `$cookieless_mode`, `$ignore_sent_at` and `$product_tour_id` properties are sent as capture options, and PostHog drops an event whose option value it can't read.
- Event properties are merged as: properties the SDK sets itself, then registered super properties, then the properties you pass, then `beforeSend`. Super properties now override SDK properties such as `$os`, and both super and event properties override `$is_identified`, `$process_person_profile`, `$geoip_disable` and the session replay debug values.

See the [migration guide](https://github.com/PostHog/posthog-ios/blob/main/docs/migration-3.x-to-4.0.md) for what to check before you upgrade.
