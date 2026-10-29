# Migrating from PostHog iOS 3.x to 4.0

4.0 sends analytics events to capture v1 (`/i/v1/analytics/events`) instead of `/batch`.
Most apps upgrade without code changes.
Read the checklist first, then the sections that apply to you.

<!-- TODO(capture-v1): when the public capture v1 SDK upgrade guide is published (PostHog/posthog.com#21386), link it here for details on options, limits and per-event results. -->

For the full list of 4.0 changes, see the [changelog](../CHANGELOG.md).

## Checklist

You need to change something if your app does any of these:

- sends events to a self-hosted PostHog or a reverse proxy that doesn't serve `/i/v1/analytics/events`
- authenticates its proxy with an `Authorization` header in `requestHeaders`
- sends events through a proxy that redirects capture requests, other than with a 307 or 308 to the same origin as `host`
- captures events with an empty event name, or with an event name or distinct ID over 200 bytes
- sets an empty distinct ID in `beforeSend`
- sets `projectToken` to a personal API key (`phx_...`)
- sets `$lib` or `$lib_version` and expects PostHog to store that value
- reads `$session_id` or `$window_id` from the raw request body, for example in a proxy
- registers a super property, or passes an event property, with the same key as one the SDK sets, such as `$os`, `$is_identified` or `$geoip_disable`, and expects the SDK's value to win
- sets `$cookieless_mode`, `$ignore_sent_at` or `$product_tour_id` to a value PostHog can't read, such as `"maybe"`
- relies on a `Retry-After` longer than 30 seconds

## Endpoints

| Data | 3.x | 4.0 |
| --- | --- | --- |
| Analytics events | `/batch` | `/i/v1/analytics/events` |
| Session replay | `/s/` | `/s/`, unchanged |
| AI events (`captureAi`) | – | `/i/v1/ai/events` (see [AI events](#ai-events)) |
| Logs | `/i/v1/logs` | `/i/v1/logs`, unchanged |
| Feature flags | `/flags` | `/flags`, unchanged |

Capture v1 requests send the project token in an `Authorization: Bearer <projectToken>` header instead of an `api_key` body field.
This header replaces any `Authorization` header you set in `PostHogConfig.requestHeaders`, so authenticate your proxy with a different header, such as `X-Proxy-Token`.
Other requests still send your `Authorization` header.

A personal API key (`phx_...`) in `projectToken` now disables the SDK at setup, as an empty token does, and logs why when `debug` is on.
In 3.x, the SDK started and PostHog rejected every event with a 401. Use your project token (`phc_...`).

### Hosts without capture v1

PostHog Cloud (`us.i.posthog.com`, `eu.i.posthog.com`) serves both capture v1 endpoints.
If you self-host PostHog, check that it serves `/i/v1/analytics/events` and `/i/v1/ai/events` before you upgrade.

If you send events through your own reverse proxy, update it before you upgrade:

- Forward `/i/v1/analytics/events` and `/i/v1/ai/events` to PostHog.
- Pass `Authorization` (the project token, sent as `Bearer <token>`), every `PostHog-*` header, `Content-Type`, `Content-Encoding` and `User-Agent` through unchanged. PostHog answers `401` without `Authorization` and `400` without the others, and the batch is dropped.
- Accept request bodies up to 20 MB. AI requests are often larger than 1 MB, the default limit in nginx and ingress-nginx. On a `413` from the proxy, the SDK splits the batch and drops any event that is still too large on its own.

PostHog's managed reverse proxy already does this. See the [proxy guides](https://posthog.com/docs/advanced/proxy).

The SDK doesn't fall back to `/batch`. A 404 is retried, so events stay queued until the route is served. Other error statuses that aren't retried, such as 403 or 405, drop the events.

### Redirects

The SDK follows a 307 or 308 redirect only to the origin of `host` (same scheme, host and port), at most 5 times, and resends the same body and headers.
Any other redirect is not followed and the events are dropped.
In 3.x, `URLSession` followed redirects to any host.
If a proxy redirects capture requests to another host, point `host` at the final host.

## Event validation

Capture v1 checks each event on its own and drops only the invalid ones, so the rest of the batch is delivered.

The SDK drops an event with an empty event name before sending it, for example `capture("")` or a name `beforeSend` sets to `""`.
`captureAi` then returns `nil`, and with `debug` on the SDK logs the first one.

The SDK doesn't check these before sending. PostHog drops the event, and the SDK removes it from the queue.
With `debug` on, the SDK logs how many events were dropped.

- An event with an empty or whitespace-only distinct ID is dropped, for example one `beforeSend` sets to `""`.
  An empty or whitespace-only `distinctId` argument isn't dropped: like `nil`, it uses the current distinct ID.
- An event whose name is over 200 UTF-8 bytes is dropped. Legacy capture had no limit on event name length.
- An event whose distinct ID is over 200 UTF-8 bytes is dropped. Legacy capture shortened the ID to 200 characters and kept the event.

In 3.x, an empty event name or distinct ID made legacy capture reject the whole batch it was in.

The distinct ID can come from `identify(_:)`, the `distinctId` argument of `capture` or `beforeSend`.
If you identify users with a long ID, such as a JWT or a long email address, shorten or hash it before you upgrade. Otherwise every event for that user is dropped.

## SDK identity

PostHog sets `$lib` and `$lib_version` from the `PostHog-Sdk-Info` request header, for example `posthog-ios/4.0.0`.
The SDK removes `$lib` and `$lib_version` from the properties it sends to capture v1.
A value you set in properties, in a super property or in `beforeSend` doesn't reach PostHog.
The SDK removes them when it sends the event, so `beforeSend` still sees them.

## Property precedence

An event's properties are merged in this order, and later values win:

1. properties the SDK sets itself, such as `$os`, `$app_version`, `$screen_name`, `$is_identified`, `$geoip_disable` and the session replay debug properties
2. registered super properties (`register`)
3. the properties you pass to `capture` or another event-sending method
4. `beforeSend`

Per-call `userProperties` and `userPropertiesSetOnce` are applied between steps 2 and 3, so they win over a registered `$set` or `$set_once`, as in 3.x.
Groups set with `group()` and per-call `groups` are applied there too, and replace a registered `$groups`.
If you also pass `$set`, `$set_once` or `$groups` in the properties, the per-call `userProperties`, `userPropertiesSetOnce` and `groups` win key by key over them. In 3.x, `$set` and `$set_once` in the properties replaced the per-call values, and `$groups` in the properties won per key.

In 3.x, the SDK's own values won over super properties, and `$is_identified`, `$process_person_profile`, `$geoip_disable` and the session replay debug properties also won over the properties you pass.
In 4.0 a value you register or pass wins, for example `capture("signed_up", properties: ["$geoip_disable": false])` sends that event with GeoIP enabled even when `disableGeoIp` is on.

## Session and window IDs

Capture v1 sends `$session_id` and `$window_id` as top-level `session_id` and `window_id` fields, not as properties.
The SDK moves them out of `properties` for you.
A string value, including an empty string, is sent unchanged.
Any other value is removed and not sent, and the SDK logs a warning that names the key and the value's JSON type, never the value.
A null value counts as unset and is removed without a warning.
In PostHog, the events still have `$session_id` and `$window_id`, so insights, filters and session replay work as before.
A registered `$session_id` now overrides the SDK's session ID (see [Property precedence](#property-precedence)), which can detach events from their session replay.

## Event options

Capture v1 reads processing settings from an `options` object sent next to `properties`.
`capture` takes a new `options` argument, and `beforeSend` can read and change `PostHogEvent.options`.
`screen`, `identify`, `setPersonProperties`, `alias`, `group` and `captureException` take the same argument.
For `identify`, the options apply to the `$identify` or `$set` event the call sends.

```swift
// 3.x
PostHogSDK.shared.capture("signed_up", properties: ["$cookieless_mode": true])

// 4.0
PostHogSDK.shared.capture("signed_up", options: ["cookieless_mode": true])
```

In Objective-C, use the selectors that end in `options:`, such as `captureWithEvent:distinctId:properties:userProperties:userPropertiesSetOnce:groups:timestamp:options:`, `screenWithTitle:properties:options:`, `identifyWithDistinctId:userProperties:userPropertiesSetOnce:options:`, `setPersonPropertiesWithUserPropertiesToSet:userPropertiesToSetOnce:options:`, `alias:options:`, `groupWithType:key:groupProperties:options:`, `captureExceptionWithError:properties:options:` and `captureExceptionWithNSException:properties:options:`. The selectors without `options:` still work.

The legacy option properties still work.
When the event is sent, the SDK removes each one from `properties` and uses it for its option:

| Legacy property | Option |
| --- | --- |
| `$process_person_profile` | `process_person_profile` |
| `$cookieless_mode` | `cookieless_mode` |
| `$ignore_sent_at` | `disable_skew_correction` |
| `$product_tour_id` | `product_tour_id` |

- An option you pass to any of these methods or set in `beforeSend` wins over its legacy property. An option set to `NSNull()` counts as unset, so the legacy property fills it.
- When `personProfiles` turns person processing off, the SDK sets the `process_person_profile` option to `false`. Otherwise it sends neither, because PostHog processes person profiles by default. To change person processing for one event, pass the `process_person_profile` option or the `$process_person_profile` property. A registered `$process_person_profile` changes it for every event.
- The SDK sends option values as given. PostHog reads common forms of a value, such as `"false"` or `0` for a boolean, and drops an event whose option value it can't read.
- Other option keys are sent unchanged, and PostHog ignores keys it doesn't know.
- Events still queued on disk by 3.x are sent to capture v1 after the update, with their legacy properties moved to options.

## AI events

4.0 adds `captureAi`, which sends AI events, such as `$ai_generation`, to PostHog's AI endpoint (`/i/v1/ai/events`) instead of the analytics endpoint.
It takes the same arguments as `capture`, and the events go through the same `beforeSend` hooks.

```swift
PostHogSDK.shared.captureAi("$ai_generation", properties: ["$ai_model": "gpt-5", "$ai_trace_id": traceId])
```

In Objective-C, use `captureAiWithEvent:distinctId:properties:userProperties:userPropertiesSetOnce:groups:timestamp:options:`.

- An AI event's properties can be up to 8 MiB. The SDK drops a serialized event over 8 MiB + 64 KiB, and `captureAi` returns `nil`. Set `captureAiMaxEventBytes` to lower the limit; it measures the whole serialized event.
- PostHog drops an event sent with `captureAi` whose name doesn't start with `$ai_`. `capture` never sends events to the AI endpoint, even ones named `$ai_*`.
- AI requests time out after 60 seconds without network activity, or `captureAiTimeout`. Other requests still time out after 10 seconds.
- AI events are queued on disk separately from other events. Up to 100 events (`captureAiMaxQueueSize`) and 50 MiB are kept, and the oldest are dropped first. `maxQueueSize` doesn't apply.
- AI requests are gzipped unless you set `captureAiCompression` to `.none`. `compression` doesn't apply.
- AI events use `flushAt`, `maxBatchSize` and `flushIntervalSeconds`, like other events. A request carries up to about 5 MiB, as for analytics events (see [Retries](#retries)).
- The SDK sends AI events unchanged. It doesn't redact or truncate prompts, outputs or media, so use `beforeSend` to remove anything you don't want to send.

## Retries

- The SDK retries network errors and 404, 408, 429, 500, 502, 503 and 504 responses. Other statuses drop the events. 3.x did not retry 404, and retried 3xx responses.
- When the response asks to retry only some events, the SDK keeps those events queued and removes the rest.
- A `Retry-After` header pauses sending for at most 30 seconds. This also applies to session replay and logs. In 3.x, analytics events and session replay had no cap, and logs allowed up to 5 minutes.
- After a failed send, the wait before the next one doubles from 1 second up to 30 seconds, with up to 25% random jitter. In 3.x it grew by 1 second per failure. This applies to events, session replay and logs.
- Event, session replay and log retries have no limit, as in 3.x: queued records stay until they're delivered or a full queue evicts them (`maxQueueSize`, or `logs.maxBufferSize` for logs).
- `maxRetries` is renamed to `pushNotificationSubscriptionMaxRetries`, with no deprecated alias. Since 3.73.0 it has only limited push-notification subscription retries.
- A request carries at most `maxBatchSize` events and about 5 MiB, and the SDK sends as soon as about 5 MiB of events is queued, even before `flushAt` is reached. In 3.x, batches were limited by event count only.
- A 413 still splits the batch into smaller requests.
