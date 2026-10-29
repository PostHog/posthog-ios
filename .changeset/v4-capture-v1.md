---
'posthog-ios': major
---

Send events through capture V1 and add `captureAi(...)` for AI events. See the [migration guide](https://github.com/PostHog/posthog-ios/blob/main/docs/migration-3.x-to-4.0.md) for what to check before you upgrade.

**Changed**

- **Breaking:** send events to capture V1 (`/i/v1/analytics/events`) with the project token in an `Authorization: Bearer` header.
  - If you use a reverse proxy or self-host PostHog, make sure `/i/v1/analytics/events` is served: a 404 is retried, so events stay queued until the route exists, and the SDK prints a warning once, also without `debug`.
  - Capture requests replace any `Authorization` header from `requestHeaders`, so authenticate your proxy with a different header.
  - Only a 307 or 308 redirect to the same origin as `host` is followed, at most 5 times. Other redirects drop the events, so point `host` at the final host.
- **Breaking:** drop an event whose distinct ID is over 200 UTF-8 bytes, instead of shortening the ID and keeping the event. Shorten or hash long IDs, such as JWTs, before you upgrade.
- **Breaking:** disable the SDK at setup when `projectToken` is a personal API key (`phx_...`). Use your project token (`phc_...`).
- **Breaking:** pause sending for at most 30 seconds on `Retry-After`, including session replay and logs.
- **Breaking:** send the `$process_person_profile`, `$cookieless_mode`, `$ignore_sent_at` and `$product_tour_id` properties as capture options. PostHog drops an event whose option value it can't read.
- **Breaking:** merge event properties as: properties the SDK sets itself, then registered super properties, then the properties you pass, then `beforeSend`. Super properties now override SDK properties such as `$os`, and both super and event properties override `$is_identified`, `$process_person_profile`, `$geoip_disable` and the session replay debug values.
- **Breaking:** let `userProperties`, `userPropertiesSetOnce` and `groups` win key by key over `$set`, `$set_once` and `$groups` maps passed in the same call's properties, instead of being replaced by them.
- **Breaking:** rename `maxRetries` to `pushNotificationSubscriptionMaxRetries`, since it only limits push-notification subscription retries. Event, session replay and log retries still have no limit.
- Double the wait after a failed send from 1 second up to 30 seconds, with up to 25% random jitter, instead of growing it by 1 second per failure. This applies to events, session replay and logs, and queued records are still kept until they're delivered.
- Cap analytics batches at 5 MiB per request; an event larger than that is sent on its own.
- Drop an event with an empty name before sending it, including one `beforeSend` renames to `""` from any method, such as `screen`, `alias` or `group`.
- Ignore `identify` with a whitespace-only distinct ID, as for an empty one.

**Added**

- Add per-event capture options with `capture(..., timestamp:options:)` and `PostHogEvent.options`, which `beforeSend` can read and change. `screen`, `identify`, `setPersonProperties`, `alias`, `group` and `captureException` take the same `options` argument.
- Add `captureAi(...)` to send AI events such as `$ai_generation` to PostHog's AI endpoint (`/i/v1/ai/events`), which accepts events up to 8 MiB. It returns the event UUID, and its requests time out after 60 seconds without network activity.
  - Add `captureAiCompression`, `captureAiMaxQueueSize`, `captureAiTimeout` and `captureAiMaxEventBytes` to `PostHogConfig` to tune AI requests separately from other events. The defaults are gzip, 100 queued events, 60 seconds and 8 MiB plus 64 KiB per serialized event; a larger `captureAiMaxEventBytes` is clamped to that ceiling with a debug warning.
- Log the name, UUID and reason of each event PostHog drops when `debug` is on.
