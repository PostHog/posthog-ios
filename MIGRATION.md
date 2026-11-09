# Migrating from PostHog iOS 3.x to 4.0

This guide covers what you need to change when you upgrade an app from PostHog iOS 3.x to 4.0.

1. [Before you upgrade](#before-you-upgrade): toolchain, deployment targets and installation.
2. [Changes the compiler won't flag](#changes-the-compiler-wont-flag): behavior that changes without a build error. Read this even if your app builds cleanly.
3. [Capture v1](#capture-v1): the new analytics endpoint, event validation, property precedence, capture options, AI events and retries.
4. [Compile errors and how to fix them](#compile-errors-and-how-to-fix-them): removed and renamed APIs.
5. [Package traits](#package-traits): leaving out session replay, crash reporting or surveys.
6. [Upgrade checklist](#upgrade-checklist).

For the full list of changes, see the [changelog](https://github.com/PostHog/posthog-ios/blob/main/CHANGELOG.md).

## Before you upgrade

### Requirements

| | 3.x | 4.0 |
| --- | --- | --- |
| Xcode | `swift-tools-version` 5.3 | 26 or later (`swift-tools-version` 6.2) |
| iOS and Mac Catalyst | 13.0 | 15.0 |
| macOS | 10.15 | 11.0 |
| tvOS | 13.0 | 15.0 |
| watchOS | 6.0 | 10.0 |
| visionOS | 1.0 | 1.0 |
| Installation | Swift Package Manager or CocoaPods | Swift Package Manager only |

The SDK still compiles in Swift 5 language mode, so your app can use Swift 5 or Swift 6 mode. App Store Connect uploads already require Xcode 26; the toolchain floor mainly affects ad-hoc, enterprise, Mac and local builds still on Xcode 16 or older.

### Move from CocoaPods to Swift Package Manager

PostHog 4.0 is not published to CocoaPods, and the repository no longer has a `PostHog.podspec`, so `pod 'PostHog', :git => ...` can't install 4.x either. 3.x versions stay installable from CocoaPods, but [CocoaPods trunk becomes read-only on December 2, 2026](https://blog.cocoapods.org/CocoaPods-Specs-Repo/).

1. Remove `pod 'PostHog'` from your `Podfile` and run `pod install`.
2. Add the package. In Xcode, choose **File > Add Package Dependencies…** and enter `https://github.com/PostHog/posthog-ios`. In a `Package.swift`:

   ```swift
   dependencies: [
       .package(url: "https://github.com/PostHog/posthog-ios.git", from: "4.0.0")
   ]
   ```

3. Add the `PostHog` library to your app target. `import PostHog` doesn't change.
4. If a Run Script phase uploads dSYMs with `${PODS_ROOT}/PostHog/build-tools/upload-symbols.sh`, change the path to `${BUILD_DIR%/Build/*}/SourcePackages/checkouts/posthog-ios/build-tools/upload-symbols.sh`. The old path no longer exists once the pod is gone, so symbol upload fails and crash reports lose symbolication.

### React Native, Flutter and Kotlin Multiplatform apps

Don't add posthog-ios 4.0 to these apps yourself. They get the iOS SDK through their PostHog package (`@posthog/react-native-plugin`, `posthog_flutter`, `posthog-kmp`). Upgrade to the version of that package that moves to iOS SDK 4.0, and follow its migration notes.

## Changes the compiler won't flag

### Session replay always records screenshots

In 3.x, session replay recorded wireframes unless you set `screenshotMode = true`. In 4.0 it always records screenshots of the screen, with sensitive content masked. Wireframe recording is gone.

If your app didn't set `screenshotMode = true`:

- Recordings now show real pixels for everything that isn't masked, including custom-drawn content such as `draw(_:)` views, maps, video and charts.
- `WKWebView` content is recorded in full when both `maskAllTextInputs` and `maskAllImages` are off. Wireframes only sent a placeholder.
- Each frame uses more bandwidth and CPU than a wireframe.

If your app's window root is a SwiftUI view, replay recorded nothing in 3.x unless you set `screenshotMode = true`. With `config.sessionReplay = true`, these apps start recording on 4.0, which counts against your replay quota and may need a consent or privacy disclosure update.

`$sdk_debug_replay_capture_mode` is now always `screenshot`, so update any filter on `wireframe`.

Check what your screens show before you ship 4.0. Text inputs and images are masked by default (`maskAllTextInputs` and `maskAllImages` are `true`). To hide anything else:

| To mask | SwiftUI | UIKit |
| --- | --- | --- |
| A view and everything inside it | `.postHogMask()` | add `ph-no-capture` to the view's `accessibilityIdentifier` |
| All text and text inputs | `sessionReplayConfig.maskAllTextInputs = true` | same |
| Every image | `sessionReplayConfig.maskAllImages = true` | same, except SF Symbols and images bundled with your app |
| System pickers (photos, contacts) | `sessionReplayConfig.maskAllSandboxedViews = true` | same |

To mask an exempt image, tag its image view with `ph-no-capture`. `ph-no-capture` also works in `accessibilityLabel`. To keep pixels out of recordings entirely, turn replay off with `config.sessionReplay = false`.

Secure-entry text fields now stay masked inside a `.postHogNoMask()` or `ph-no-mask` subtree. If you upgrade from a version before 3.93.1, masking also covers content a masked view draws outside its bounds (unclipped images, layer shadows, button titles) and image attachments in labels and text views when `maskAllImages` is on, with the same UIKit exceptions.

Known limitation: if a masked view sits inside a view backed by your app's own `CALayer` subclass, such as a Lottie animation view, the SDK can't safely read where the masked view is on screen, so it masks the whole window for that frame. Fast scrolling on a screen that holds such a layer may also drop replay frames.

### Replay screen names

- The screen name shown for a recording comes from the screen that is visible. SwiftUI screens report their view name.
- A plain `UIViewController`'s `title` is no longer used as the replay screen name, so it reports no name. This includes storyboard scenes without a custom class. Subclasses still report their type name without `ViewController` (`CheckoutViewController` becomes `Checkout`).

`$screen` events are named as in 3.x.

### Feature flag payloads and empty variants

- A malformed, empty or whitespace-only payload now reads as `nil` from `getFeatureFlagResult(_:)` and `getAllFeatureFlags()`. In 3.x you got the raw string. The flag's value and enabled state don't change.
- Bootstrapped string payloads in `PostHogBootstrapConfig.featureFlagPayloads` stay strings. In 3.x, a bootstrapped `"123"` or `"true"` was decoded a second time and read back as a number or `Bool`.
- A flag whose variant is an empty string reads as disabled. `isFeatureEnabled(_:)` returns `false`, with or without `defaultValue`, `enabled` is `false` in `getFeatureFlagResult(_:)` and `getAllFeatureFlags()`, `PostHogFeatureFlagsLoaded` leaves the flag out of `flags` and `variants`, and captured events leave it out of `$active_feature_flags`. In 3.x, `isFeatureEnabled(_:)` and `enabled` returned `true` and events listed the flag. `variant`, `getFeatureFlag(_:)` and the event's `$feature/<key>` property still return `""`.

If your code relied on getting the raw string back, make the payload valid JSON in PostHog.

If an app's last 3.x launch cached a bootstrapped string payload, got no `/flags` response afterwards and no longer passes bootstrap values, that payload can read as `nil` until the next `/flags` response.

### Lifecycle events lose `version` and `build`

`Application Installed`, `Application Updated` and `Application Opened` no longer send `version` and `build`. Every event already has `$app_version` and `$app_build`, so update insights, cohorts and actions that filter on `version` or `build`. `Application Updated` still sends `previous_version` and `previous_build`. If you used "`version` is set" on `Application Opened` to find cold launches, filter on `from_background = false` instead. Events already stored keep the old fields.

### Apps updating straight from 2.x

If an app updates from a 2.x SDK straight to 4.0, events still queued on disk by 2.x are deleted instead of sent. Distinct ID, anonymous ID, groups and cached feature flags still carry over. Events created by 3.x aren't affected.

If 3.x copied a 2.x event into its queue and it's still unsent, 4.0 sends it but ignores its top-level `$set` and `message_id`: those person properties aren't set, and the event gets a new uuid unless it has a `uuid` field.

### `$locale` and `$app_language`

`$locale` now means the device's preferred language, with its region: `de-CH` instead of `de`, and `fr-FR` when your app only supports English. This matches Android's format and the property's definition. If a user picks a language for your app in iOS Settings, iOS reports that language as the first preferred language, so `$locale` follows it. Android 4.0 reports the device-wide language even when a per-app language is set, so for those users `$locale` means different things on iOS and Android.

The new `$app_language` property is the language your app shows. It's the closest match to what `$locale` used to mean, but not always the same value: `$locale` sent only the language code, and `$app_language` sends your app's full localization name. An app localized as `de` still sends `de`. An app localized as `pt-BR` or `zh-Hans` now sends that, where `$locale` sent `pt` or `zh`. If you use your own language setting instead of iOS localizations, call `PostHogSDK.shared.setAppLanguage("de")` at startup and whenever it changes.

Update cohorts, insights and actions that match `$locale`: a filter on `$locale = de` stops matching `de-CH`. To filter on the language your app shows, use `$app_language`, with a regex such as `^pt(-|$)` if you ship regional or script localizations. To filter on device language, use a regex on `$locale` such as `^de(-|$)`, because "contains" also matches `en-DE`. Events already stored and app versions still on 3.x keep the old `$locale` and have no `$app_language`.

Feature flags aren't affected: the SDK doesn't send `$locale` or `$app_language` with flag requests, so flags only see these if you set them as person properties yourself.

### Null event properties

An event property set to `NSNull()` is now left out of the event instead of being sent as `null`, also inside nested dictionaries and dictionaries in arrays, and also when `beforeSend` sets it. An array keeps a `null` element at its position, and a dictionary left empty is sent as `{}`. `false`, `0`, `""` and empty arrays are sent as before. You can still pass `NSNull()`. To clear a person or group property, `$set`, `$set_once` and `$group_set` still send `null` values. A `$feature_flag_called` event for a flag with no value now has no `$feature_flag_response` instead of `null`.

### Network reachability

4.0 detects connectivity with `NWPathMonitor`:

- A connection that needs user action, such as a VPN waiting for a password, counts as reachable.
- Queues pause while cellular data is turned off for your app.
- Events captured in the first 100 ms after `setup()` may leave out `$network_wifi` and `$network_cellular`.

## Capture v1

4.0 sends analytics events to capture v1 (`/i/v1/analytics/events`) instead of `/batch`. Most apps upgrade without code changes, and only the `maxRetries` rename (see [Retries](#retries)) produces a compile error. Read the checklist first, then the sections that apply to you.

For the changes every capture v1 SDK shares, such as event options, limits and per-event results, see [Upgrading to capture v1 SDKs](https://posthog.com/docs/libraries/capture-v1).

### Checklist

You need to change your code, proxy or PostHog setup if your app does any of these:

- sends events to a self-hosted PostHog or a reverse proxy that doesn't serve `/i/v1/analytics/events`
- authenticates its proxy with an `Authorization` header in `requestHeaders`
- sends events through a reverse proxy set up from PostHog's proxy guides before 29 October 2026, which strips `Authorization`
- sends events through a proxy that redirects capture requests, other than with a 307 or 308 to the same origin as `host`
- captures events with an empty event name, or with an event name or distinct ID over 200 bytes
- sets an empty distinct ID in `beforeSend`
- replaces `event.options` in `beforeSend`, or returns an event kept from an earlier call (see [Event options](#event-options))
- sets `projectToken` to a personal API key (`phx_...`)
- reads `$session_id` or `$window_id` from the raw request body, for example in a proxy
- registers a super property, or passes an event property, with the same key as one the SDK sets, such as `$os`, `$is_identified` or `$geoip_disable`, and expects the SDK's value to win
- sets `$cookieless_mode`, `$ignore_sent_at` or `$product_tour_id` to a value PostHog can't read, such as `"maybe"`
- relies on a `Retry-After` longer than 30 seconds
- reads the SDK's debug log, for example in log-based alerts

### Endpoints

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

A personal API key (`phx_...`) in `projectToken` now disables the SDK at setup, as an empty or whitespace-only token does, and prints a warning explaining why, also without `debug`. The SDK trims whitespace from `projectToken`, as in 3.x. To turn the SDK off in tests, use an empty token.
In 3.x, the SDK started and PostHog rejected every event with a 401. Use your project token (`phc_...`).

#### Hosts without capture v1

PostHog Cloud (`us.i.posthog.com`, `eu.i.posthog.com`) serves both capture v1 endpoints.
If you self-host PostHog, check that it serves `/i/v1/analytics/events` and `/i/v1/ai/events` before you upgrade.

If you send events through your own reverse proxy, update it before you upgrade:

- Forward `/i/v1/analytics/events` and `/i/v1/ai/events` to PostHog.
- Pass `Authorization` (the project token, sent as `Bearer <token>`), every `PostHog-*` header, `Content-Type`, `Content-Encoding` and `User-Agent` through unchanged. PostHog answers `401` without `Authorization` and `400` without the others, and the batch is dropped.
- If your proxy strips other credentials, keep `Authorization` values that start with `Bearer phc_`, `Bearer phs_` or `Bearer phx_`, or the exact `Bearer <key>` of an older key without a prefix.
- Pass PostHog's response body through unchanged. A 2xx response whose body isn't PostHog's `{"results": {...}}` drops the events instead of retrying them.
- Accept request bodies up to 20 MB. AI requests are often larger than 1 MB, the default limit in nginx and ingress-nginx. On a `413` from the proxy, the SDK splits the batch and drops any event that is still too large on its own.

PostHog's managed reverse proxy already does this and needs no change. A proxy set up from PostHog's [proxy guides](https://posthog.com/docs/advanced/proxy) before 29 October 2026 strips `Authorization`, so PostHog answers `401` and the events are dropped. Update it from the current guide.

The SDK doesn't fall back to `/batch`. A 404 is retried, so events stay queued until the route is served. Other error statuses that aren't retried, such as 403 or 405, drop the events.

#### Redirects

The SDK follows a 307 or 308 redirect only to the origin of `host` (same scheme, host and port), at most 5 times, and resends the same body and headers.
Any other redirect is not followed and the events are dropped.
In 3.x, `URLSession` followed redirects to any host.
If a proxy redirects capture requests to another host, point `host` at the final host.

### Event validation

Capture v1 checks each event on its own and drops only the invalid ones, so the rest of the batch is delivered.

The SDK drops an event with an empty event name before sending it, for example `capture("")` or a name `beforeSend` sets to `""`.
`captureAi` then returns `nil`, and with `debug` on the SDK logs the first one.

The SDK doesn't check these before sending. PostHog drops the event, and the SDK removes it from the queue.
With `debug` on, the SDK logs how many events were dropped and why. There's no error callback, and the log text changed from 3.x, so update any log-based alerts.
The line has counts and PostHog's drop reasons, never event names, uuids or properties.

- An event with an empty or whitespace-only distinct ID is dropped, for example one `beforeSend` sets to `""`.
  An empty or whitespace-only `distinctId` argument isn't dropped: like `nil`, it uses the current distinct ID.
  `identify` ignores an empty or whitespace-only distinct ID. 3.x ignored only an empty one.
- An event whose name is over 200 UTF-8 bytes is dropped. Legacy capture had no limit on event name length.
- An event whose distinct ID is over 200 UTF-8 bytes is dropped. Legacy capture shortened the ID to 200 characters and kept the event.

A `NaN`, infinite or other non-JSON property value is removed before sending, and the event is still sent.
In a nested dictionary, a key that isn't a string, such as an `Int`, `Double` or `Bool`, is sent as its string form: `["scores": [1: "gold"]]` is sent as `{"scores": {"1": "gold"}}`. A key with no string form is removed, and the rest of the dictionary is sent. In 3.x, the SDK removed the whole nested dictionary.

Each event needs its own uuid: PostHog keeps the first copy in a request and drops later events with the same uuid. The SDK generates a uuid for each capture and keeps it through `beforeSend`, even when the hook returns an event kept from an earlier call, so you can't send a repeated uuid by accident.

In 3.x, an empty event name or distinct ID made legacy capture reject the whole batch it was in.

The distinct ID can come from `identify(_:)`, the `distinctId` argument of `capture` or `beforeSend`.
If you identify users with a long ID, such as a JWT or a long email address, shorten or hash it before you upgrade. Otherwise every event for that user is dropped.

### Property precedence

An event's properties are merged in this order, and later values win:

1. properties the SDK sets itself, such as `$os`, `$app_version`, `$screen_name`, `$is_identified`, `$geoip_disable` and the session replay debug properties
2. registered super properties (`register`)
3. the properties you pass to `capture` or another event-sending method
4. `beforeSend`

Per-call `userProperties` and `userPropertiesSetOnce` are applied between steps 2 and 3, so they replace a registered `$set` or `$set_once` whole, as in 3.x.
A `$set` or `$set_once` you pass in the properties also replaces a registered one whole. The two aren't merged.
Groups set with `group()` and per-call `groups` are applied there too, and replace a registered `$groups`.
If you also pass `$set`, `$set_once` or `$groups` in the properties, the per-call `userProperties`, `userPropertiesSetOnce` and `groups` win key by key over them. In 3.x, `$set` and `$set_once` in the properties replaced the per-call values, and `$groups` in the properties won per key.

In 3.x, the SDK's own values won over super properties, and `$is_identified`, `$process_person_profile`, `$geoip_disable` and the session replay debug properties also won over the properties you pass.
In 4.0 a value you register or pass wins, for example `capture("signed_up", properties: ["$geoip_disable": false])` sends that event with GeoIP enabled even when `disableGeoIp` is on.

### Session and window IDs

Capture v1 sends `$session_id` and `$window_id` as top-level `session_id` and `window_id` fields, not as properties.
The SDK moves them out of `properties` for you.
A string value, including an empty string, is sent unchanged.
Any other value is removed and not sent. With `debug` on, the SDK logs a warning that names the key and the value's JSON type, never the value.
A null value counts as unset and is removed without a warning.
In PostHog, the events still have `$session_id` and `$window_id`, so insights, filters and session replay work as before.
A registered `$session_id` now overrides the SDK's session ID (see [Property precedence](#property-precedence)), which can detach events from their session replay.

### Timestamps and IDs

The SDK sends every timestamp in UTC with 3 fractional digits, for example `2026-01-01T00:00:00.000Z`, as 3.x did.
It doesn't check for future timestamps. PostHog replaces a timestamp more than 23 hours ahead with the time it received the event.
Event uuids and anonymous distinct IDs are UUID v7, as in 3.x.
The new `PostHog-Request-Id` header is a UUID v7 too.

### Event options

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

The legacy option properties, the `$`-prefixed properties legacy capture reads as settings, still work.
When the event is sent, the SDK removes each one from `properties` and uses it for its option:

| Legacy option property | Option |
| --- | --- |
| `$process_person_profile` | `process_person_profile` |
| `$cookieless_mode` | `cookieless_mode` |
| `$ignore_sent_at` | `disable_skew_correction` |
| `$product_tour_id` | `product_tour_id` |

- An option you pass to any of these methods or set in `beforeSend` wins over its legacy property. An option set to `NSNull()` counts as unset, so the legacy property fills it.
- When `personProfiles` turns person processing off, the SDK sets the `process_person_profile` option to `false`. Otherwise it sends neither, because PostHog processes person profiles by default. To change person processing for one event, pass the `process_person_profile` option or the `$process_person_profile` property. A registered `$process_person_profile` changes it for every event.
- Calling `group()`, or passing `userProperties`, `userPropertiesSetOnce` or `groups`, still turns person processing on for later events when `personProfiles` is `.identifiedOnly`, as in 3.x.
- Review your `beforeSend` hooks for the new event shape. In 3.x, the SDK marked person processing with the `$process_person_profile` property. In 4.0, it's the `process_person_profile` option, and the property isn't set. A hook that replaces `event.options` without keeping that key, or returns an event kept from an earlier call, can lose the `false` the SDK set. That turns person processing on for anonymous users, overriding `personProfiles`.
- The SDK sends option values as given. PostHog reads common forms of a value, such as `"false"` or `0` for a boolean, and drops an event whose option value it can't read.
- Other option keys are sent unchanged, and PostHog ignores keys it doesn't know.
- There are no global options. To set one for every event, register its legacy property, for example `register(["$cookieless_mode": true])`.
- A registered option also reaches `$identify`, `$create_alias` and `$groupidentify`. If it turns person processing off, for example `register(["$process_person_profile": false])`, PostHog accepts those events and then drops them with an ingestion warning, and the SDK doesn't report it.
- Events still queued on disk by 3.x are sent to capture v1 after the update, with their legacy properties moved to options.

### AI events

4.0 adds `captureAi`, which sends AI events, such as `$ai_generation`, to PostHog's AI endpoint (`/i/v1/ai/events`) instead of the analytics endpoint.
It takes the same arguments as `capture`, and the events go through the same `beforeSend` hooks.

```swift
PostHogSDK.shared.captureAi("$ai_generation", properties: ["$ai_model": "gpt-5", "$ai_trace_id": traceId])
```

In Objective-C, use `captureAiWithEvent:distinctId:properties:userProperties:userPropertiesSetOnce:groups:timestamp:options:`.

- An AI event's properties can be up to 8 MiB. The SDK drops a serialized event over 8 MiB + 64 KiB, and `captureAi` returns `nil`. Set `captureAiMaxEventBytes` to lower the limit; it measures the whole serialized event.
- Any `$ai_*` event never creates or updates a person profile, so `$set` and `$set_once` are ignored, and it's billed as an AI event. See [the `$ai_` prefix](https://posthog.com/docs/ai-observability/basics#the-ai_-prefix).
- PostHog drops an event sent with `captureAi` whose name doesn't start with `$ai_`. `capture` never sends events to the AI endpoint, even ones named `$ai_*`.
- AI requests time out after 60 seconds without network activity, or `captureAiTimeout`. Other requests still time out after 10 seconds.
- AI events are queued on disk separately from other events. Up to 100 events (`captureAiMaxQueueSize`) and 50 MiB are kept, and the oldest are dropped first. `maxQueueSize` doesn't apply.
- AI requests are gzipped unless you set `captureAiCompression` to `.none`. `compression` doesn't apply.
- AI events use `flushAt`, `maxBatchSize` and `flushIntervalSeconds`, like other events. A request carries up to about 5 MiB, as for analytics events (see [Retries](#retries)).
- `flush()` and `close()` also send AI events, and AI events left on disk are sent after the next launch.
- The SDK sends AI events unchanged. It doesn't redact or truncate prompts, outputs or media, so use `beforeSend` to remove anything you don't want to send.

### Retries

- The SDK retries network errors and 404, 408, 429, 500, 502, 503 and 504 responses. Other statuses, such as a 402 when you're over your billing limit, drop the whole request. A product quota, such as for exceptions or AI events, instead drops only those events inside a 200. 3.x did not retry 404, and retried 3xx responses.
- When the response asks to retry only some events, the SDK keeps those events queued and removes the rest.
- A `Retry-After` header sets the minimum wait before the next send, up to 30 seconds. This also applies to session replay and logs. In 3.x, analytics events and session replay had no cap, and logs allowed up to 5 minutes.
- After a failed send, the wait before the next one doubles from 1 second up to 30 seconds, with up to 25% random jitter. In 3.x it grew by 1 second per failure. This applies to events, session replay and logs.
- Event, session replay and log retries have no limit, as in 3.x: queued records stay until they're delivered or a full queue evicts them (`maxQueueSize`, or `logs.maxBufferSize` for logs).
- `maxRetries` is renamed to `pushNotificationSubscriptionMaxRetries`, with no deprecated alias. Since 3.73.0 it has only limited push-notification subscription retries.
- A request carries at most `maxBatchSize` events and about 5 MiB, and the SDK sends as soon as about 5 MiB of events is queued, even before `flushAt` is reached. In 3.x, batches were limited by event count only.
- A 413 halves the batch and resends it, until a request carries one event. A single event that still gets a 413 is dropped. 3.x did the same.
- The SDK has no per-event size limit for analytics events, as in 3.x. An event larger than about 5 MiB is sent in a request of its own.
- PostHog drops an analytics event whose serialized size is over 1,000,000 bytes, and only that event; with `debug` on, the drop line says `event_too_big`. In 3.x, such an event got a 413 for its whole batch, and was dropped once the SDK had split the batch down to it.
- `beforeSend` runs when you capture the event, before it's queued, so batching, splitting and retries never change what it sees.
- With `debug` on, the SDK no longer logs a line for each queued event, and a failed capture request no longer logs PostHog's response body. 3.x did both.

## Compile errors and how to fix them

Removed and renamed APIs fail to build. For most of them Xcode names the replacement, and offers a fix-it for plain renames. Internal and utility APIs get a plain "cannot find in scope" error, so look those up here. Objective-C names are listed where they differ.

### Configuration

| 3.x | 4.0 |
| --- | --- |
| `PostHogConfig(apiKey:)`, `PostHogConfig(apiKey:host:)`<br>ObjC: `apiKey:`, `apiKey:host:` | `PostHogConfig(projectToken:)`, `PostHogConfig(projectToken:host:)`<br>ObjC: `projectToken:`, `projectToken:host:` |
| `config.apiKey` | `config.projectToken` |
| `config.evaluationEnvironments` | `config.evaluationContexts` |
| `config.remoteConfig` | Delete the assignment. Remote config is always loaded. |
| `config.propertiesSanitizer`, `PostHogPropertiesSanitizer` | `config.setBeforeSend(_:)` (see below) |
| `config.dataMode = .cellular`<br>ObjC: `PostHogDataModeCellular` | `.any`<br>ObjC: `PostHogDataModeAny`. `PostHogDataMode(rawValue: 1)` now returns `nil`. |
| `config.maxRetries` | `config.pushNotificationSubscriptionMaxRetries`. It only ever limited push-notification subscription retries. |
| `config.storageManager`, `PostHogStorageManager` | `identify(_:)`, `getDistinctId()`, `getAnonymousId()`, `getDeviceId()` and `reset()` on `PostHogSDK`. There's no public way to supply your own storage manager or set the IDs directly. |

Replacing `propertiesSanitizer`:

```swift
// 3.x
config.propertiesSanitizer = MySanitizer()

// 4.0
config.setBeforeSend { event in
    event.properties = sanitize(event.properties)
    return event // or nil to drop the event
}
```

In Objective-C, wrap each block in a `BoxedBeforeSendBlock`:

```objc
[config setBeforeSend:@[[[BoxedBeforeSendBlock alloc] block:^PostHogEvent *(PostHogEvent *event) {
    return event;
}]]];
```

### Session replay

| 3.x | 4.0 |
| --- | --- |
| `sessionReplayConfig.screenshotMode` | Delete the assignment. Replay always records masked screenshots: see [Session replay always records screenshots](#session-replay-always-records-screenshots). |
| `sessionReplayConfig.screenshotModeBackgroundCapture` | Delete the assignment. Screenshots are always captured on the main thread. |
| `sessionReplayConfig.maskPhotoLibraryImages` | Delete the assignment. It had no effect. |
| `sessionReplayConfig.debouncerDelay` | `sessionReplayConfig.throttleDelay` |
| `PostHogLogLevel`, `PostHogLogEntry`<br>ObjC: `PostHogLogLevelInfo`, `PostHogLogLevelWarn`, `PostHogLogLevelError` | `PostHogConsoleLogLevel`, `PostHogConsoleLogEntry`<br>ObjC: `PostHogConsoleLogLevelInfo`, `PostHogConsoleLogLevelWarn`, `PostHogConsoleLogLevelError` |

### Feature flags

| 3.x | 4.0 |
| --- | --- |
| `getFeatureFlagPayload(key)`<br>ObjC: `getFeatureFlagPayload:` | `getFeatureFlagResult(key, sendFeatureFlagEvent: false)?.payload`<br>ObjC: `[sdk getFeatureFlagResultWithKey:key sendFeatureFlagEvent:NO].payload` |
| `reloadFeatureFlags { ... }`<br>ObjC: `^{ ... }` | `reloadFeatureFlags { result in ... }` (or `{ _ in ... }`). `result.errorsLoading` is `true` when the reload failed (`result.variants` then holds the last known flags) or the SDK isn't set up. It's `false` when the project is over its flag quota.<br>ObjC: `^(PostHogFeatureFlagsLoaded *result) { ... }` |
| `PostHogSDK.didReceiveFeatureFlags` notification | `onFeatureFlags(_:)` (see below) |

Replacing the `didReceiveFeatureFlags` notification:

```swift
// 3.x
NotificationCenter.default.addObserver(
    self, selector: #selector(flagsLoaded),
    name: PostHogSDK.didReceiveFeatureFlags, object: nil
)

// 4.0: runs on the main thread after each flag load
let subscription = PostHogSDK.shared.onFeatureFlags { loaded in
    // loaded.flags, loaded.variants, loaded.errorsLoading
}
// later, to stop listening:
subscription.unsubscribe()
```

In Objective-C, call `[[PostHogSDK shared] onFeatureFlags:^(PostHogFeatureFlagsLoaded *loaded) { ... }]`. You can subscribe before `setup()`.

### Callbacks are `@Sendable`

Callbacks the SDK can call off the main thread are now `@Sendable`: `reloadFeatureFlags(_:)`, the blocks passed to `setBeforeSend(_:)` on `PostHogConfig` and `PostHogLogsConfig`, `getAnonymousId`, `pushIdentityProvider` and its `completion`, and `sessionReplayConfig.captureLogsConfig.logSanitizer`. The `BeforeSendBlock` and `PostHogBeforeSendLogBlock` type aliases are `@Sendable` too.

In Swift 6 mode, a closure that reads or writes main-actor state no longer compiles (Swift 5 mode warns). For `reloadFeatureFlags(_:)` and `pushIdentityProvider`, hop to the main actor:

```swift
PostHogSDK.shared.reloadFeatureFlags { result in
    Task { @MainActor in
        self.showNewFeature = !result.errorsLoading
    }
}
```

The other callbacks must return right away, so don't read main-actor state in them.

A closure written inline in the call, such as `config.setBeforeSend { event in ... }`, works in both modes. A closure stored in a variable, or a method reference, depends on the language mode:

- Swift 6 mode: `config.setBeforeSend(sanitize)` fails with "converting non-Sendable function value to '@Sendable ...' may introduce data races". Declare the closure as `BeforeSendBlock` (`let sanitize: BeforeSendBlock = { ... }`), or pass it in an array: `config.setBeforeSend([sanitize])`.
- Swift 5 mode: `config.setBeforeSend([sanitize])` fails with "ambiguous use of 'setBeforeSend'". Pass the closure directly instead: `config.setBeforeSend(sanitize)`, or declare it as `BeforeSendBlock`.

An array of closures stored in a variable works in both modes, so you don't need to retype it as `[BeforeSendBlock]`. The same applies to `config.logs.setBeforeSend(_:)`, with `PostHogBeforeSendLogBlock`.

### Internal and utility APIs

These were public only for PostHog's own React Native and Flutter SDKs, or by accident:

| 3.x | 4.0 |
| --- | --- |
| `PostHogSessionManager` | `getSessionId()`, `startSession()` and `endSession()` on `PostHogSDK`. Custom session IDs (`setSessionId(_:)`) have no public replacement in 4.0. |
| `postHogSdkName`, `postHogVersion`, `config.snapshotEndpoint` | No longer public. A wrapper SDK that must read or set them can use `@_spi(PostHogInternal) import PostHog`, with no stability guarantees. |
| ObjC: `[PostHogSessionManager shared]`, `setSessionId:`, `config.snapshotEndpoint` | No longer exposed to Objective-C. `[[PostHogSDK shared] getSessionId]`, `startSession` and `endSession` replace the session calls. |
| `dateToMillis(_:)`, `imageToBase64(_:_:)` | No longer public. For `dateToMillis(_:)`, use `Int64(date.timeIntervalSince1970 * 1000)`; for `imageToBase64(_:_:)`, copy the code you need into your app. A wrapper SDK can still use both through `@_spi(PostHogInternal) import PostHog`, with no stability guarantees. |
| `toISO8601String(_:)`, `toISO8601Date(_:)`, `sanitizeDictionary(_:)`, `deleteSafely(_:)`, `postHogiOSSdkName`, `Gzip`, `GzipError`, `CompressionLevel`, `UIColor(hex:)`, `UIColor.hexDescription(_:)` | No longer public. Copy the code you need into your app. |
| `ReachabilityError`, `ReachabilityChangedNotification` | Removed. Use `NWPathMonitor` if your app needs reachability. |

## Package traits

4.0 splits three features into Swift package traits, all on by default:

| Trait | What it includes |
| --- | --- |
| `SessionReplay` | Session replay on iOS, including the bundled libwebp |
| `CrashReporting` | Crash and uncaught-exception capture using the bundled PLCrashReporter, and out-of-memory capture |
| `Surveys` | The survey engine and UI on iOS |

With the default traits nothing changes. To leave a feature out, list only the traits you want in your `Package.swift`:

```swift
dependencies: [
    // Keep crash reporting, leave out session replay and surveys
    .package(url: "https://github.com/PostHog/posthog-ios.git", from: "4.0.0", traits: ["CrashReporting"])
]
```

Use `traits: []` to leave out all three. In an Xcode app project, traits for a package dependency can be chosen from Xcode 26.4. Check that the build actually leaves the feature out.

When a trait is off, its public API is removed too, so code that uses it fails to compile instead of silently doing nothing:

| Trait off | Removed |
| --- | --- |
| `SessionReplay` | `config.sessionReplay`, `config.sessionReplayConfig`, `PostHogSessionReplayConfig`, the console log types, `startSessionRecording()`, `stopSessionRecording()`, `isSessionReplayActive()`, `.postHogNoMask()` |
| `CrashReporting` | `errorTrackingConfig.autoCapture`. `captureException` and the rest of `errorTrackingConfig` still work. |
| `Surveys` | `config.surveys`, `config.surveysConfig`, `PostHogSurveysConfig`, `PostHogSurveysDelegate` and the survey display types |

`.postHogMask()` stays available, because it also keeps tap autocapture out of masked areas.

SwiftPM turns a trait on if any package in your dependency graph depends on posthog-ios with the default traits, so you can only leave a feature out if every dependency does too.

## Upgrade checklist

- [ ] Build with Xcode 26 or later, and raise your deployment targets to at least iOS 15, macOS 11, tvOS 15 and watchOS 10.
- [ ] Move from CocoaPods to Swift Package Manager, including any dSYM upload script path.
- [ ] If you use session replay, review recordings on a test build: custom-drawn content, maps, video and web views can now appear. Add masks where needed.
- [ ] If your app is SwiftUI-rooted and has replay on, expect recordings to start, and check quota and consent.
- [ ] Update insights, cohorts and actions that use `version` or `build` on lifecycle events, or `wireframe` in `$sdk_debug_replay_capture_mode`.
- [ ] Update cohorts, insights and actions that match `$locale`, which now includes the region. Use `$app_language` for the language your app shows, which can also include a region or script, such as `pt-BR`.
- [ ] Check code that reads feature flag payloads and could get `nil` for a malformed one, and flags whose variant is an empty string, which now read as disabled.
- [ ] Work through the [capture v1 checklist](#checklist), especially reverse proxies, self-hosted instances and long distinct IDs.
- [ ] Fix the compile errors using the tables above, including `reloadFeatureFlags` closures, `maxRetries`, and `@Sendable` callbacks such as `setBeforeSend` in Swift 6 mode.
- [ ] If you leave features out with package traits, list every trait you want to keep.
