## Next

## 3.67.1

### Patch Changes

- 4c8c5a4: Fix surveys scoped to web via a CSS selector or URL display condition leaking onto native iOS. Surveys carrying `conditions.selector` or `conditions.url` are now treated as non-matching on native platforms, since those conditions can only be evaluated in a web context.

## 3.67.0

### Minor Changes

- 262c9b2: Send minimal `$feature_flag_called` events when the server opts the project in (top-level `minimalFlagCalledEvents` in the flags response) and the evaluated flag has no experiment. Minimal events keep only a strict allowlist of flag-evaluation and linkage properties plus `$os_name`, `$os_version`, and `$app_version` for OS- and version-segmented insights; the rest of the device/OS context envelope, super properties, `$active_feature_flags`, and the `$feature/<key>` enumeration are stripped. Experiment-linked flags, ungated projects, and any response missing the signals keep sending the full event.

## 3.66.1

### Patch Changes

- a582c6a: Add a `$feature_flag_has_experiment` boolean property to `$feature_flag_called` events, sourced from the flag's `metadata.has_experiment` in the flags response. The property is only sent when the server explicitly reports it and omitted when unknown (e.g. legacy responses without flag details).

## 3.66.0

### Minor Changes

- 474eb4a: Add a `bootstrap` option to `PostHogConfig` for pre-seeding identity and feature flags before the first `/flags` response. Set `config.bootstrap = PostHogBootstrapConfig(...)` before `setup()` so early events carry a caller-controlled distinct ID and flag reads return your values during cold start. Mirrors the `bootstrap` option in posthog-js.

## 3.65.0

### Minor Changes

- 2ee22f5: Add `PostHogSDK.captureSessionReplaySnapshot(afterScreenUpdates:)`, an SPI session-replay hook (`@_spi(PostHogInternal)`) that lets first-party PostHog wrapper SDKs (e.g. posthog-flutter) capture the current native window on their own cadence — used to record native screens that cover an out-of-engine UI. Not a public API: it requires an `@_spi(PostHogInternal) import` and carries no stability guarantees.

## 3.64.7

### Patch Changes

- 2f1e1c3: `upload-symbols.sh` supports `POSTHOG_SKIP_ON_CONFLICT=1` to pass `--skip-on-conflict` to `posthog-cli dsym upload`, so dSYM content conflicts skip the upload instead of failing the build (requires posthog-cli >= 0.7.12)

## 3.64.6

### Patch Changes

- 6ba42c4: Fix `errorTrackingConfig.ignoredExceptionTypes` not being applied to `$exception` events sent through the generic `capture()` API (e.g. hybrid SDK bridges forwarding pre-serialized exceptions); previously only `captureException` and crash-report autocapture honored it.

## 3.64.5

### Patch Changes

- 3921285: fix: make vendored protobuf-c header resolution robust against header-search-path loss

  Relocate the vendored `protobuf-c.{h,c}` next to `PLCrashReport.pb-c.h`, the only
  source that includes `protobuf-c.h` across directories, so the include resolves via
  the compiler's same-directory rule instead of a `HEADER_SEARCH_PATHS` entry. This
  prevents intermittent `'protobuf-c.h' file not found` build failures when a
  consumer's build drops the pod's header search paths.

## 3.64.4

### Patch Changes

- c5b2d23: Avoid a crash in the flags and remote-config API handlers when the URL response is not an `HTTPURLResponse` (previously force-cast); the SDK now logs and returns gracefully instead.
- 24cbc60: Session replay (screenshot mode): skip re-sending unchanged screenshots. Static screens no longer upload an identical full screenshot every tick, cutting replay bandwidth and storage. Wireframe mode is unaffected.

## 3.64.3

> **Note:** Version 3.64.3 is available through Swift Package Manager only. CocoaPods users should use **3.64.4** or later.

### Patch Changes

- 5ed8fd6: Fix event-queue peek/pop misalignment that could re-send already-delivered events when a file was skipped, and stop deleting valid queue files that are only temporarily unreadable (e.g. iOS data protection on a locked device).

## 3.64.2

### Patch Changes

- 6a5b391: fix: prevent Session Replay crashes on AVAggregateAssetDownloadTask

## 3.64.1

### Patch Changes

- ced6a8b: Fix the upload symbols script for projects with spaces in their paths.

## 3.64.0

### Minor Changes

- b9afc8f: Add `ignoredExceptionTypes` to `PostHogErrorTrackingConfig` so apps embedding both the JS RN SDK and the native iOS SDK can suppress duplicate native captures by exception class name.

### Patch Changes

- 7dbeb82: Retry remote feature flag requests after transient 502 and 504 responses.

## 3.63.1

### Patch Changes

- b9126c7: Feature-flag properties (`$feature/*` and `$active_feature_flags`) passed explicitly to `capture()` now take precedence over the SDK's cached flag values, matching posthog-js (web) and posthog-android.

## 3.63.0

### Minor Changes

- 5fa4a56: Add `requestHeaders` config option to send custom headers (e.g. `Authorization`) with every request to the PostHog API. Useful for reverse-proxy setups that require authentication.

## 3.62.5

### Patch Changes

- e57e428: Session replay now respects the resolved recording config once the first remote config response arrives. Recording still starts optimistically from the disk-cached config at cold start, but snapshots are now buffered (not persisted) until the first live remote config resolves. On resolve, the buffered opening window is flushed to the replay queue only when the session is recordable under the fresh config — recording flag on, sampled in, and not waiting on an event trigger — and is dropped otherwise, so a returning user no longer uploads a stale-cache window the fresh config disallows via the recording flag, sample rate, or event trigger. When recording is gated on a linked feature flag — whose value is only fresh once the flags response (which follows the config response) arrives — resolution is deferred to that flags reload so the window isn't flushed on a stale flag value; if feature-flag preloading is disabled, so no flags reload follows, it resolves against the cached flag instead. A subsequent remote config that turns recording off also stops it promptly instead of waiting for the next session rotation.

## 3.62.4

### Patch Changes

- b9bf252: Retry capture delivery on transient HTTP errors and respect Retry-After responses while preserving queued events across retries.

## 3.62.3

### Patch Changes

- c5f5b60: Generate lowercase UUID strings for SDK-created event, anonymous, session, and queue identifiers.

## 3.62.2

### Patch Changes

- fb59e77: Fall back to uncompressed uploads when local gzip compression fails.

## 3.62.1

### Patch Changes

- c1a7f11: Retry feature flag requests after transient network errors only. The feature flag request retry count defaults to 1 and can be set to 0 to disable retries.

## 3.62.0

### Minor Changes

- fcc876e: Add `PostHogSDK.getAllFeatureFlags()` returning all loaded flags as `[PostHogFeatureFlagResult]` (key, enabled, variant, payload). Exposed to Objective-C via `@objc`.

## 3.61.1

### Patch Changes

- b5bdba8: Session replay: skip native event-trigger gating when running under React Native (`postHogSdkName == "posthog-react-native"`). React Native evaluates `sessionRecording.eventTriggers` in its JS layer and drives recording via explicit `startSessionRecording` calls; the native gate could never be satisfied because JS-captured events never reach the native capture pipeline, so event-triggered replay never recorded on RN. The linked-flag and sampling gates are unchanged, and non-RN behavior is unaffected.

## 3.61.0

### Minor Changes

- 1f5d88d: Add `addExceptionStep(_:properties:)` to record breadcrumb-style steps that attach to every captured `$exception` as `$exception_steps`.

## 3.60.1

### Patch Changes

- 805c834: Respect remote session replay sample rates after config loads.

## 3.60.0

### Minor Changes

- b9861d8: Rage click detection no longer emits `$rageclick` on controls where rapid repeated taps are intentional rather than frustration — the on-screen keyboard, text fields and text selection, steppers, sliders, pickers, date pickers, segmented controls and page controls. This applies to UIKit and SwiftUI. You can exclude a custom control with the `ph-no-rageclick` accessibility identifier/label (UIKit) or the `.postHogNoRageClick()` view modifier (SwiftUI).

## 3.59.3

### Patch Changes

- 6b6dd54: `reloadFeatureFlags(_:)` now always invokes its completion callback, including when the SDK is disabled/opted-out or when no remote config is available. Previously these early-returns skipped the callback, which could leave callers that await it (e.g. the Flutter SDK's `reloadFeatureFlags`) hanging indefinitely.
- 306896b: Keep session replay recording, error-tracking autocapture, and network performance capture active after an in-session `identify()`/`reset()` instead of disabling them until the next app restart. The project-level recording, error-tracking, and capture-performance config is now preserved across `reset()` and re-armed on the next `/flags` reload.

## 3.59.2

### Patch Changes

- 0cc8d80: Retry event uploads on HTTP 408 (Request Timeout), matching the SDK's existing logs-endpoint behavior.

## 3.59.1

### Patch Changes

- 2afa9ec: fix(surveys): a single malformed survey no longer disables every survey on iOS. Surveys are now decoded per-element (a bad entry is logged and skipped instead of dropping the whole list), and rating questions tolerate missing `lowerBoundLabel`/`upperBoundLabel` to match Web/Android behavior. Empty bound labels are also no longer rendered as blank caption rows under the rating control. Fixes #611.

## 3.59.0

### Minor Changes

- c0341fe: Auto-attach `$screen_name` to every captured event after `PostHogSDK.shared.screen()` has been called (manually or via screen-view auto-capture). Cached value is cleared by `reset()` and `close()`.

  **To opt out of `$screen_name` stamping entirely**, set `PostHogConfig.captureScreenViews = false` **and** stop calling `screen()` manually. Disabling `captureScreenViews` alone is not sufficient — a single manual `screen("Home")` call will re-enable stamping.

### Minor Changes

- Add survey translations support. Surveys can carry per-language overrides for user-visible strings via a `translations` map keyed by language code. At display time the SDK resolves a language (`PostHogSurveysConfig.overrideDisplayLanguage` → person property `"language"` → device locale), applies any matching translation onto the display model, and stamps the matched key as `$survey_language` on every survey event when a translation actually took effect. Matching is case-insensitive with a base-language fallback (e.g. `"pt-BR"` falls back to `"pt"`).

## 3.58.3

### Patch Changes

- 90ceeea: fix: silence PHPLCrashReporter CocoaPods module warnings

## 3.58.2

### Patch Changes

- ce2c65a: fix: silence vendored libwebp macro redefinition warning

## 3.58.1

### Patch Changes

- f91bb4e: Add an experimental `sessionReplayConfig.screenshotModeBackgroundCapture` option for Session Replay screenshot mode, allowing screenshot rendering to be scheduled on a background queue to reduce main-thread pressure.

## 3.58.0

### Minor Changes

- 7e9bf5f: Add a logs feature for shipping structured log records from iOS, macOS, tvOS, watchOS, and visionOS apps:

  ```swift
  PostHogSDK.shared.captureLog("hello", level: .info, attributes: ["k": "v"])
  PostHogSDK.shared.logger?.info("ready")
  PostHogSDK.shared.flush()
  ```

  Configure batching, rate limiting, service metadata, and a `beforeSend` filter via `config.logs`. Records are persisted to disk and survive app restarts. Manual capture only — console autocapture is not included.

### Patch Changes

- 78bb5e8: fix: synchronize SDK enabled state
- 85afba6: Keep the SDK disabled when no project token or API key is provided.

## 3.57.6

### Patch Changes

- 2e76fa6: fix: duplicate symbol linker errors when posthog-ios is used alongside other dependencies that also include libwebp, such as SDWebImageWebPCoder or KingfisherWebP

## 3.57.5

### Patch Changes

- 04f7aa0: Clean up CocoaPods validation warnings from deprecated sanitizer access, unused lock results, and duplicate C++ linker flags.

## 3.57.4

### Patch Changes

- 8407036: Fix events queue not responding to network reachability changes. The replay queue's subscription was silently overwriting the events queue's `whenReachable` / `whenUnreachable` callbacks since v3.0, so `dataMode = .wifi` was ignored, auto-flush on WiFi reconnect did not fire, and the offline pause was reactive after a wasted request. `Reachability` now exposes `onReachable` / `onUnreachable` multicast hooks; the legacy single-callback fields are deprecated.

## 3.57.3

### Patch Changes

- 8e2658e: fix: capture Swift runtime crash messages from \_\_crash_info (covers fatalErrors, asserts, preconditions, and force unwraps)
- fb97bb4: fix: resolve PLCrashReporter dependency and symbol conflicts by vendoring/prefixing crash reporter sources

## 3.57.2

### Patch Changes

- cc2b23b: Include survey responses on iOS dismissal events and mark whether the dismissed survey was partially completed.

## 3.57.1

### Patch Changes

- 150e83f: fix: improve session replay screenshot performance

## 3.57.0

### Minor Changes

- 4273b7f: Add tracing header injection for URLSession requests.

### Patch Changes

- 6cebb23: fix: parse `build` as Int when possible on `Application Opened` events, matching `Application Installed` / `Application Updated`. Extracts the shared `CFBundleVersion` parsing into a reusable helper so all four `build` / `$app_build` / `previous_build` call sites stay consistent.

## 3.56.0

### Minor Changes

- 47aaf2f: Rename apiKey to projectToken with backward-compatible aliases

## 3.55.1

### Patch Changes

- 2278539: Trim surrounding whitespace from apiKey and host config before using them.

## 3.55.0

### Minor Changes

- 6098042: feat: add support for $rageclick detection for iOS/macCatalyst

## 3.54.0

### Minor Changes

- feeaeac: support survey popup delay

## 3.53.1

### Patch Changes

- 3588c05: fix: swift 5.3 compatibility issue with Xcode 15.4

## 3.53.0

### Minor Changes

- 51022cd: feat: support session replay minimum recording duration

## 3.52.0

### Minor Changes

- c01ece0: Add device bucketing support for stable feature flag assignment across identity changes

### Patch Changes

- c01ece0: Use renamed version/release on dsym upload

## 3.51.0

⚠️ Skip this version, this is a broken release and should not be used.

## 3.50.0

### Minor Changes

- 569348a: feat: error tracking GA

## 3.49.1

### Patch Changes

- 642d4b1: correct frame addresses, ordering, and in-app detection

## 3.49.0

### Minor Changes

- c2a3963: feat: Manual capture deep link events (SwiftUI and UIKit). Thanks @jeremiahseun ❤️

## 3.48.4

### Patch Changes

- 8bdd623: fix: session replay memory leak with 1s screenshot throttling
- 5055fd7: fix: SPM builds on Mac Catalyst build error

## 3.48.3

### Patch Changes

- 9d48e58: fix: use separate queue folder to prevent crashes when downgrading from 3.48.1+ to older SDK versions

## 3.48.2

### Patch Changes

- e331f56: purge crash reports before processing them

## 3.48.1

### Patch Changes

- 3545320: fix: guard swizzled layoutSublayers to handle background thread calls
- 061cb44: Replace ReadWriteLock with NSLock for consistent thread-safety across the codebase. The ReadWriteLock property wrapper provided false thread-safety for collection types since the lock was released between separate operations. Using explicit NSLock with `.withLock` closures ensures atomic operations and clearer intent.
- ac76d70: fix: clear in-memory feature flags cache on reset()

> ⚠️ WARNING: This release contains a crash bug ([#537](https://github.com/PostHog/posthog-ios/issues/537)) fixed in **3.48.3**. Avoid pinning to this version especially in workflows where you may be downgrading between SDK versions (e.g. TestFlight distributions) and use **3.48.3** or later instead.

## 3.48.0

### Minor Changes

- 80f39ca: feat: add support for session replay event triggers

## 3.47.0

### Minor Changes

- 8f44e92: feat: Add `captureFeatureView` and `captureFeatureInteraction` methods for tracking feature flag analytics
- a9366ad: support survey event property filters

## 3.46.0

### Minor Changes

- 1f987f4: Add ObjC convenience overloads for captureException methods without requiring properties parameter
- 20ba9dc: Flush event queue when the app enters background to ensure pending events are sent before the app is suspended
- 6f65947: Capture `$feature_flag_called` event when session replay is gated behind a linked feature flag

## 3.45.2

### Patch Changes

- ff6c2ab: Skip dSYM upload for non-Release builds to avoid unnecessary network work and build failures during local development

## 3.45.1

### Patch Changes

- d6e54f1: fix: process pending crash reports

## 3.45.0

### Minor Changes

- 33fe226: feat: add experimental error tracking support

⚠️ **Known issue (Swift 5.3 + older Xcode):** This release introduced a Swift 5.3 compatibility regression when building with older Xcode versions (Swift 5.3 toolchain). If you compile with Swift 5.3 and experience errors, use a version before 3.45.0 or upgrade to 3.53.1+.

## 3.44.0

### Minor Changes

- cbd7024: support survey wait period

## 3.43.0

### Minor Changes

- d85e393: feat: support 'always' survey schedule

### Patch Changes

- 4a8496c: fix: queue pending feature flags reload instead of dropping concurrent requests

## 3.42.1

### Patch Changes

- 59befaf: Use remote config as sole config loading mechanism: remove `config=true` from flags endpoint, add `timezone` to flags requests, deprecate `remoteConfig` config option

## 3.42.0

### Minor Changes

- 5df2c40: feat: Support session recording `sampleRate` from remote config

## 3.41.2

### Patch Changes

- 9b67e4c: test new release process

## 3.41.1 - 2026-02-12

fix: Session Replay now correctly checks the `network_timing` flag in remote config when `capturePerformance` is an object ([#470](https://github.com/PostHog/posthog-ios/pull/470))

## 3.41.0 - 2026-02-10

- feat: session replay config `sessionReplayConfig.captureLogs` and `sessionReplayConfig.captureNetworkTelemetry` now respect project settings ([#452](https://github.com/PostHog/posthog-ios/pull/452))
  > **Note**: requires `PostHogConfig.remoteConfig` to be enabled (default)
- fix: prevent crashes from non JSON-serializable property types (Date, URL, Data, infinity, NaN, etc.) ([#466](https://github.com/PostHog/posthog-ios/pull/466))
- feat: add `$is_testflight` and `$is_sideloaded` event properties ([#443](https://github.com/PostHog/posthog-ios/pull/443))

## 3.40.0 - 2026-02-05

> ⚠️ **Warning**: This version contains a crash when using `setPersonProperties` with non-JSON-serializable types like `Date` in properties. Please upgrade to the next version.

- feat: Add `getFeatureFlagResult` method to client ([#455](https://github.com/PostHog/posthog-ios/pull/455))

## 3.39.0 - 2026-02-03

- feat: add `setPersonProperties` method to update person profile properties ([#441](https://github.com/PostHog/posthog-ios/pull/441))
- fix: do not capture $set events if user props have not changed ([#441](https://github.com/PostHog/posthog-ios/pull/441))

## 3.38.0 - 2026-01-22

- chore: support new surveys color options for ios+flutter ([#440](https://github.com/PostHog/posthog-ios/pull/440))
- feat: support thumbs up/down surveys for ios ([#437](https://github.com/PostHog/posthog-ios/pull/437))
- fix: Retain cached flags when quota limited ([#438](https://github.com/PostHog/posthog-ios/pull/438))
- Renamed `evaluationEnvironments` to `evaluationContexts` for clearer semantics ([#434](https://github.com/PostHog/posthog-ios/pull/434)). The term "contexts" better reflects that this feature is for specifying evaluation contexts (e.g., "web", "mobile", "checkout") rather than deployment environments (e.g., "staging", "production").
- The API now sends `evaluation_contexts` instead of `evaluation_environments` to the server.

### Deprecated

- `PostHogConfig.evaluationEnvironments` is now deprecated in favor of `PostHogConfig.evaluationContexts`. The old property will continue to work and will print a deprecation warning. It will be removed in a future major version.

### Migration Guide

```swift
// Before
config.evaluationEnvironments = ["production", "web", "checkout"]

// After
config.evaluationContexts = ["production", "web", "checkout"]
```

No immediate action required - existing code using `evaluationEnvironments` will continue to work with a deprecation warning.

## 3.37.2 - 2026-01-09

- fix: remove person processing requirements for flag property overrides ([#431](https://github.com/PostHog/posthog-ios/pull/431))

## 3.37.1 - 2026-01-06

- fix: parse $app_build as integer when possible ([#423](https://github.com/PostHog/posthog-ios/pull/423))
- fix: macOS device name now uses hardware model instead of hostname to avoid blocking DNS lookups ([#422](https://github.com/PostHog/posthog-ios/pull/422))

## 3.37.0 - 2025-12-30

- feat: add ability to override sendFeatureFlagEvent for exact feature flag call ([#396](https://github.com/PostHog/posthog-ios/pull/396))

## 3.36.2 - 2025-12-19

- fix: SwiftUI view modifiers .postHogMask() and .postHogNoMask() on iOS 26 ([#415](https://github.com/PostHog/posthog-ios/pull/415))

## 3.36.1 - 2025-12-16

- fix: SwiftUI view masking on iOS 26 ([#409](https://github.com/PostHog/posthog-ios/pull/409))
  > Note: If you are building with Xcode 26, update to this version to fix the SwiftUI view masking issue.
  > Note: Because of the changes of the SwiftUI rendering engine, the SwiftUI modifiers .posthogMask() and .posthogNoMask() may behave inconsistently for SwiftUI primitive views. Use with caution.

## 3.36.0 - 2025-12-08

- feat: include `evaluated_at` properties in `$feature_flag_called` events ([#394](https://github.com/PostHog/posthog-ios/pull/394))
- fix: only report $feature_flag_called if the flag value has changed ([#405](https://github.com/PostHog/posthog-ios/pull/405))

## 3.35.1 - 2025-12-02

- fix: avoid memory leaks on foat conversions ([#401](https://github.com/PostHog/posthog-ios/pull/401))
- fix: app group migration now skips identity-related keys from extensions ([#402](https://github.com/PostHog/posthog-ios/pull/402))

## 3.35.0 - 2025-11-07

- fix: call the flags api with the correct groups key name (the api has a back compatible fix already) ([#389](https://github.com/PostHog/posthog-ios/pull/389))
- fix: only set getDefaultPersonProperties with person properties that are evaluated on the server ([#389](https://github.com/PostHog/posthog-ios/pull/389))
- feat: set and reset PersonPropertiesForFlags and GroupPropertiesForFlags reload flags automatically (or set reloadFeatureFlags: false) ([#389](https://github.com/PostHog/posthog-ios/pull/389))

## 3.34.0 - 2025-10-15

- feat: add config option to disable swizzling ([#388](https://github.com/PostHog/posthog-ios/pull/388))
- feat: SDK instance now manages its own session ([#388](https://github.com/PostHog/posthog-ios/pull/388))
  > **Note**: A potentially breaking change for users with multiple SDK instances. Each SDK instance now manages its own `$session_id` instead of sharing a global session across all instances.
  > This aligns with PostHog JS SDK behavior and ensures proper session isolation when using multiple SDK instances.
  > For single-instance usage (the common case), this change has no impact.

## 3.33.0 - 2025-10-13

- feat: add evaluation tags to iOS SDK ([#387](https://github.com/PostHog/posthog-ios/pull/387))

## 3.32.0 - 2025-10-03

- feat: iOS surveys use the new response question id format ([#383](https://github.com/PostHog/posthog-ios/pull/383))

## 3.31.0 - 2025-08-29

- feat: surveys GA ([#381](https://github.com/PostHog/posthog-ios/pull/381))
  > Note: Surveys are now enabled by default

## 3.30.1 - 2025-08-12

- fix: map missing content type for Surveys ([#377](https://github.com/PostHog/posthog-ios/pull/377))

## 3.30.0 - 2025-07-28

- feat: add person and group properties for feature flags ([#373](https://github.com/PostHog/posthog-ios/pull/373))
- feat: support default properties for feature flag evaluation ([#375](https://github.com/PostHog/posthog-ios/pull/375))

## 3.29.0 - 2025-07-15

- feat: add support for custom survey UI ([#369](https://github.com/PostHog/posthog-ios/pull/369))

## 3.28.3 - 2025-07-14

- fix: don't clear flags on remote config error or if hasFeatureFlags is nil ([#368](https://github.com/PostHog/posthog-ios/pull/368))

## 3.28.2 - 2025-06-26

- fix: survey question header padding ([#365](https://github.com/PostHog/posthog-ios/pull/365))
- fix: session replay perforamnce improvements ([#364](https://github.com/PostHog/posthog-ios/pull/364))

## 3.28.1 - 2025-06-23

- fix: surveys decoding error ([#363](https://github.com/PostHog/posthog-ios/pull/363))

## 3.28.0 - 2025-06-19

- feat: add support for beforeSend function to edit or drop events ([#357](https://github.com/PostHog/posthog-ios/pull/357))

## 3.27.0 - 2025-06-16

- fix: unify storage path for `appGroupIdentifier` across targets ([#356](https://github.com/PostHog/posthog-ios/pull/356))
- fix: do not call flags callback with invalid flags ([#355](https://github.com/PostHog/posthog-ios/pull/355))
- use new `/flags` endpoint instead of `/decide` ([#345](https://github.com/PostHog/posthog-ios/pull/345))

## 3.26.2 - 2025-06-03

- fix: pause network capture when app is backgrounded ([#352](https://github.com/PostHog/posthog-ios/pull/352))
- fix: prevent duplicate application lifecycle events ([#354](https://github.com/PostHog/posthog-ios/pull/354))

## 3.26.1 - 2025-05-30

- fix: clear cached flags if remote config response hasFeatureFlags is false ([#347](https://github.com/PostHog/posthog-ios/pull/347))§

## 3.26.0 - 2025-05-20

- feat: capture console logs for session replay ([#350](https://github.com/PostHog/posthog-ios/pull/350))

## 3.25.1 - 2025-05-13

- fix: edge case where session manager would not rotate session id ([#349](https://github.com/PostHog/posthog-ios/pull/349))

## 3.25.0 - 2025-04-30

- feat: add support for conditional survey questions ([#343](https://github.com/PostHog/posthog-ios/pull/343))

## 3.24.3 - 2025-04-29

- fix: feature flags not loading on sdk init ([#346](https://github.com/PostHog/posthog-ios/pull/346))

## 3.24.2 - 2025-04-24

- fix: optional link in survey question type ([#341](https://github.com/PostHog/posthog-ios/pull/341))
- fix: app hangs on iPad with floating keyboard when session replay is enabled ([#340](https://github.com/PostHog/posthog-ios/pull/340))

## 3.24.1 - 2025-04-23

- fix: Send correct `$feature_flag_response` for the `$feature_flag_called` event when calling `isFeatureEnabled` ([#337](https://github.com/PostHog/posthog-ios/pull/337))
- fix: support ISO8601 dates with missing milliseconds ([#338](https://github.com/PostHog/posthog-ios/pull/338))

## 3.24.0 - 2025-04-17

- chore: Autocapture GA ([#334](https://github.com/PostHog/posthog-ios/pull/334))
- feat: reuse `anonymousId` between user changes ([#332](https://github.com/PostHog/posthog-ios/pull/332))

## 3.23.0 - 2025-04-14

- fix: postHogMask() view modifier breaks navigation bar ([#331](https://github.com/PostHog/posthog-ios/pull/331))
- fix: manually start session recording even when `config.sessionReplay` is disabled ([#330](https://github.com/PostHog/posthog-ios/pull/330))
- feat: start/stop integrations when calling optIn() or optOut() ([#329](https://github.com/PostHog/posthog-ios/pull/329))
- feat: add `$feature_flag_id`, `$feature_flag_version`, `$feature_flag_reason` and `$feature_flag_request_id` properties to `$feature_flag_called` event ([#327](https://github.com/PostHog/posthog-ios/pull/327))

## 3.22.1 - 2025-04-10

- no user facing changes

## 3.22.0 - 2025-04-09

- feat: add support for surveys on iOS ([#325](https://github.com/PostHog/posthog-ios/pull/325))

## 3.21.0 - 2025-03-28

- fix: visionOS builds ([#291](https://github.com/PostHog/posthog-ios/pull/291))
  Thanks @harlanhaskins ❤️

- feat: improve session replay throttle logic ([#322](https://github.com/PostHog/posthog-ios/pull/322))
  > Note: `debouncerDelay` is deprecated and will be removed in next major update. Use `throttleDelay` instead which provides identical functionality for controlling session replay capture frequency.

## 3.20.1 - 2025-03-13

- fix: disk storage not working on tvOS ([#316](https://github.com/PostHog/posthog-ios/pull/316))
- fix: wrong is_identified fallback value ([#317](https://github.com/PostHog/posthog-ios/pull/317))

## 3.20.0 - 2025-03-04

- feat: support multiple SDK instances ([#310](https://github.com/PostHog/posthog-ios/pull/310))
  > Note: Now event storage is per API key. Any pending events in legacy storage will be migrated to the first API key used.

## 3.19.9 - 2025-02-28

- fix: SwiftUI view masking when using clipShape view modifier ([#312](https://github.com/PostHog/posthog-ios/pull/312))
- fix: reported crash on PostHogSessionManager ([#311](https://github.com/PostHog/posthog-ios/pull/311))

## 3.19.8 - 2025-02-26

- feat: add support for quota-limited feature flags ([#308](https://github.com/PostHog/posthog-ios/pull/308))

## 3.19.7 - 2025-02-20

- fix: recordings not always properly masked during screen transitions ([#306](https://github.com/PostHog/posthog-ios/pull/306))

## 3.19.6 - 2025-02-18

- fix: crash on autocapture when a segmented control has not selection ([#304](https://github.com/PostHog/posthog-ios/pull/304))

## 3.19.5 - 2025-02-11

- fix: flutter session recordings not working ([#297](https://github.com/PostHog/posthog-ios/pull/297))

## 3.19.4 - 2025-02-07

- fix: occasional crash when converting to Int in session replay wireframe ([#294](https://github.com/PostHog/posthog-ios/pull/294))

## 3.19.3 - 2025-02-04

- fix: custom hosts with a path ([#290](https://github.com/PostHog/posthog-ios/pull/290))
- fix: identify macOS when running Mac Catalyst or iOS on Mac ([#287](https://github.com/PostHog/posthog-ios/pull/287))

## 3.19.2 - 2025-01-30

- fix: XCFramework builds failing ([#288](https://github.com/PostHog/posthog-ios/pull/288))
- chore: Session Replay GA ([#286](https://github.com/PostHog/posthog-ios/pull/286))

## 3.19.1 - 2025-01-13

- fix: RN Expo builds failing ([#281](https://github.com/PostHog/posthog-ios/pull/281))

## 3.19.0 - 2025-01-08

- feat: ability to manually start and stop session recordings ([#276](https://github.com/PostHog/posthog-ios/pull/276))
- feat: change screenshot encoding format from JPEG to WebP ([#273](https://github.com/PostHog/posthog-ios/pull/273))

## 3.18.0 - 2024-12-27

- feat: add `postHogNoMask` SwiftUI view modifier to explicitly mark any View as non-maskable ([#277](https://github.com/PostHog/posthog-ios/pull/277))

## 3.17.2 - 2024-12-23

- fix: ignore additional keyboard windows for $screen event ([#279](https://github.com/PostHog/posthog-ios/pull/279))

## 3.17.1 - 2024-12-18

- fix: avoid masking SwiftUI Gradient views ([#275](https://github.com/PostHog/posthog-ios/pull/275))

## 3.17.0 - 2024-12-10

- feat: ability to add a custom label to autocapture elements ([#271](https://github.com/PostHog/posthog-ios/pull/271))

## 3.16.2 - 2024-12-05

- fix: ignore autocapture events from keyboard window ([#269](https://github.com/PostHog/posthog-ios/pull/269))

## 3.16.1 - 2024-12-04

- fix: screen flicker when capturing a screenshot when a sensitive text field is on screen ([#270](https://github.com/PostHog/posthog-ios/pull/270))

## 3.16.0 - 2024-12-03

- fix: deprecate `maskPhotoLibraryImages` due to unintended masking issues ([#268](https://github.com/PostHog/posthog-ios/pull/268))

## 3.15.9 - 2024-11-28

- fix: skip capturing a snapshot during view controller transitions ([#265](https://github.com/PostHog/posthog-ios/pull/265))

## 3.15.8 - 2024-11-28

- no user facing changes

## 3.15.7 - 2024-11-25

- fix: detect and mask out system photo library and user photos ([#261](https://github.com/PostHog/posthog-ios/pull/261))
  - This can be disabled through the following `sessionReplayConfig` options:
  ```swift
  config.sessionReplayConfig.maskAllSandboxedViews = false
  config.sessionReplayConfig.maskPhotoLibraryImages = false
  ```

## 3.15.6 - 2024-11-20

- fix: read accessibilityLabel from parent's view to avoid performance hit on RN ([#259](https://github.com/PostHog/posthog-ios/pull/259))

## 3.15.5 - 2024-11-19

- fix: properly mask SwiftUI Text (and text-based views) ([#257](https://github.com/PostHog/posthog-ios/pull/257))

## 3.15.4 - 2024-11-19

- fix: avoid zero touch locations ([#256](https://github.com/PostHog/posthog-ios/pull/256))
- fix: reading screen size could sometimes lead to a deadlock ([#252](https://github.com/PostHog/posthog-ios/pull/252))

## 3.15.3 - 2024-11-18

- fix: mangled wireframe layouts ([#250](https://github.com/PostHog/posthog-ios/pull/250))
- recording: do not rotate the session id for hybrid SDKs ([#253](https://github.com/PostHog/posthog-ios/pull/253))

## 3.15.2 - 2024-11-13

- fix: allow changing person properties after identify ([#249](https://github.com/PostHog/posthog-ios/pull/249))

## 3.15.1 - 2024-11-12

- fix: accessing UI APIs off main thread to get screen size ([#247](https://github.com/PostHog/posthog-ios/pull/247))

## 3.15.0 - 2024-11-11

- add autocapture support for UIKit ([#224](https://github.com/PostHog/posthog-ios/pull/224))

## 3.14.2 - 2024-11-08

- fix issue with resetting accent color in SwiftUI app ([#238](https://github.com/PostHog/posthog-ios/pull/238))
- fix $feature_flag_called not captured after reloading flags ([#232](https://github.com/PostHog/posthog-ios/pull/232))

## 3.14.1 - 2024-11-05

- recording: fix RN iOS masking ([#230](https://github.com/PostHog/posthog-ios/pull/230))

## 3.14.0 - 2024-11-05

- add option to pass a custom timestamp when calling capture() ([#228](https://github.com/PostHog/posthog-ios/pull/228))
- fix crash when loading dynamic colors from storyboards ([#229](https://github.com/PostHog/posthog-ios/pull/229))

## 3.13.3 - 2024-10-25

- fix race condition in PostHogFileBackedQueue.deleteFiles ([#218](https://github.com/PostHog/posthog-ios/pull/218))

## 3.13.2 - 2024-10-18

- add missing capture method for objC with groups overload ([#217](https://github.com/PostHog/posthog-ios/pull/217))

## 3.13.1 - 2024-10-16

- add optional distinctId parameter to capture methods ([#216](https://github.com/PostHog/posthog-ios/pull/216))

## 3.13.0 - 2024-10-14

- recording: session replay respect feature flag variants ([#209](https://github.com/PostHog/posthog-ios/pull/209))
- add `postHogMask` view modifier to manually mask a SwiftUI view ([#202](https://github.com/PostHog/posthog-ios/pull/202))

## 3.12.7 - 2024-10-09

- add appGroupIdentifier in posthog config ([#207](https://github.com/PostHog/posthog-ios/pull/207))

## 3.12.6 - 2024-10-02

- recording: capture network logs from dataTask requests without CompletionHandler ([#203](https://github.com/PostHog/posthog-ios/pull/203))

## 3.12.5 - 2024-09-24

- no user facing changes

## 3.12.4 - 2024-09-19

- no user facing changes

## 3.12.3 - 2024-09-18

- no user facing changes

## 3.12.2 - 2024-09-17

- fix: some public APIs such as unregister weren't checking for isEnabled ([#196](https://github.com/PostHog/posthog-ios/pull/196))

## 3.12.1 - 2024-09-12

- recording: missing import for url session extensions ([#194](https://github.com/PostHog/posthog-ios/pull/194))
- recording: network logs not counting the request transferSize but only the response transferSize ([#193](https://github.com/PostHog/posthog-ios/pull/193))

## 3.12.0 - 2024-09-12

- chore: add Is Emulator support ([#190](https://github.com/PostHog/posthog-ios/pull/190))
- recording: PostHog URLSession extensions for capturing network logs ([#189](https://github.com/PostHog/posthog-ios/pull/189))

## 3.11.0 - 2024-09-11

- chore: add personProfiles support ([#187](https://github.com/PostHog/posthog-ios/pull/187))

## 3.10.0 - 2024-09-09

- recording: mask swiftui picker if masking enabled ([#184](https://github.com/PostHog/posthog-ios/pull/184))
- chore: add is identified property ([#186](https://github.com/PostHog/posthog-ios/pull/186))
- recording: create timers in the main thread since it requires a run loop ([#188](https://github.com/PostHog/posthog-ios/pull/188))

## 3.9.1 - 2024-09-06

- recording: detect swiftui images not too agressively ([#181](https://github.com/PostHog/posthog-ios/pull/181))

## 3.9.0 - 2024-09-06

- chore: add SwiftUI View extensions to capture screen view and views in general (postHogViewEvent, postHogScreenView) ([#180](https://github.com/PostHog/posthog-ios/pull/180))
- recording: send meta event again if session rotates ([#183](https://github.com/PostHog/posthog-ios/pull/183))

## 3.8.3 - 2024-09-03

- recording: use non deprecated methods for getCurrentWindow if available ([#178](https://github.com/PostHog/posthog-ios/pull/178))

## 3.8.2 - 2024-09-03

- chore: cache flags, distinct id and anon id in memory to avoid file IO every time ([#177](https://github.com/PostHog/posthog-ios/pull/177))

## 3.8.1 - 2024-08-30

- fix: do not clear events when reset is called ([#175](https://github.com/PostHog/posthog-ios/pull/175))
- fix: reload feature flags as anon user after reset is called ([#175](https://github.com/PostHog/posthog-ios/pull/175))

## 3.8.0 - 2024-08-29

- fix: rotate session id when reset is called ([#174](https://github.com/PostHog/posthog-ios/pull/174))
- chore: expose session id ([#165](https://github.com/PostHog/posthog-ios/pull/165)), ([#170](https://github.com/PostHog/posthog-ios/pull/170)) and ([#171](https://github.com/PostHog/posthog-ios/pull/171))

## 3.7.2 - 2024-08-16

- recording: improve ios session recording performance by avoiding redrawing after screen updates ([#166](https://github.com/PostHog/posthog-ios/pull/166))
  - `debouncerDelay` is changed from 500ms to 1s since the iOS screenshot has to be taken in the main thread and its more sensitive to performance issues

## 3.7.1 - 2024-08-13

- recording: improve ios session recording performance by doing some work off of the main thread ([#158](https://github.com/PostHog/posthog-ios/pull/158))

## 3.7.0 - 2024-08-07

- chore: Support the `propertiesSanitizer` config ([#154](https://github.com/PostHog/posthog-ios/pull/154))

## 3.6.3 - 2024-07-26

- recording: fix respect session replay project settings from app start ([#150](https://github.com/PostHog/posthog-ios/pull/150))

## 3.6.2 - 2024-07-25

- recording: fix MTLTextureDescriptor has width of zero issue ([#149](https://github.com/PostHog/posthog-ios/pull/149))

## 3.6.1 - 2024-06-26

- recording: improvements to screenshot masking ([#147](https://github.com/PostHog/posthog-ios/pull/147))

## 3.6.0 - 2024-06-26

- recording: screenshot masking ([#146](https://github.com/PostHog/posthog-ios/pull/146))

## 3.5.2 - 2024-06-18

- chore: migrate UUID from v4 to v7 ([#145](https://github.com/PostHog/posthog-ios/pull/145))

## 3.5.1 - 2024-06-12

- recording: fix `screenshotMode` typo ([#143](https://github.com/PostHog/posthog-ios/pull/143))

## 3.5.0 - 2024-06-11

- chore: change host to new address ([#139](https://github.com/PostHog/posthog-ios/pull/139))
- fix: rename groupProperties to groups for capture methods ([#140](https://github.com/PostHog/posthog-ios/pull/140))
- recording: add `screenshotMode` option for session replay instead of wireframe ([#142](https://github.com/PostHog/posthog-ios/pull/142))

## 3.4.0 - 2024-05-23

- allow anonymous id generation to be configurable ([#133](https://github.com/PostHog/posthog-ios/pull/133))
- fix: PrivacyInfo warning when using Cocoapods ([#138](https://github.com/PostHog/posthog-ios/pull/138))

## 3.3.0 - 2024-05-21

- chore: apply patches from 3.2.5 to 3.3.0 and session recording fixes [#135](https://github.com/PostHog/posthog-ios/pull/135)
  - iOS session recording is still experimental

## 3.2.5 - 2024-05-14

- fix: `reset` deletes only sdk files instead of the whole folder [#132](https://github.com/PostHog/posthog-ios/pull/132)

## 3.3.0-alpha.2 - 2024-04-16

- chore: silence `shared` warning for strict concurrency [#129](https://github.com/PostHog/posthog-ios/pull/129)

## 3.3.0-alpha.1 - 2024-03-27

- iOS session recording - very first alpha release [#115](https://github.com/PostHog/posthog-ios/pull/115)

## 3.2.4 - 2024-03-12

- `maxQueueSize` wasn't respected when capturing events [#116](https://github.com/PostHog/posthog-ios/pull/116)

## 3.2.3 - 2024-03-05

- `optOut` wasn't respected in capture methods [#114](https://github.com/PostHog/posthog-ios/pull/114)

## 3.2.2 - 2024-03-01

- API requests do a 10s timeoutInterval instead of 60s [#113](https://github.com/PostHog/posthog-ios/pull/113)

## 3.2.1 - 2024-02-26

- PrivacyInfo manifest set in the SPM and CocoaPods config [#112](https://github.com/PostHog/posthog-ios/pull/112)

## 3.2.0 - 2024-02-23

- read `$app_name` from `CFBundleDisplayName` as a fallback if `CFBundleName` isn't available [#108](https://github.com/PostHog/posthog-ios/pull/108)
- add PrivacyInfo manifest [#110](https://github.com/PostHog/posthog-ios/pull/110)

## 3.1.4 - 2024-02-19

- fix reset session when reset or close are called [#107](https://github.com/PostHog/posthog-ios/pull/107)

## 3.1.3 - 2024-02-09

- fix ISO8601 formatter to always use the 24h format [#106](https://github.com/PostHog/posthog-ios/pull/106)

## 3.1.2 - 2024-02-09

- fix and improve logging if the `debug` flag is enabled [#104](https://github.com/PostHog/posthog-ios/pull/104)

## 3.1.1 - 2024-02-08

- `Application Opened` respects the `captureApplicationLifecycleEvents` config. [#102](https://github.com/PostHog/posthog-ios/pull/102)

## 3.1.0 - 2024-02-07

- Add session tracking [#100](https://github.com/PostHog/posthog-ios/pull/100)

## 3.0.0 - 2024-01-29

Check out the updated [docs](https://posthog.com/docs/libraries/ios).

Check out the [docs](https://posthog.com/docs/libraries/ios/usage) guide.

### Changes

- Rewritten in Swift.
- [Breaking changes](https://github.com/PostHog/posthog-ios/blob/3.0.0/USAGE.md#breaking-changes) in the API.

## 3.0.0-RC.1 - 2024-01-16

- better macOS support with more event properties [#96](https://github.com/PostHog/posthog-ios/pull/96)

## 3.0.0-beta.3 - 2024-01-11

- Do not report dupe `Application Opened` event during the first time [#95](https://github.com/PostHog/posthog-ios/pull/95)

## 3.0.0-beta.2 - 2024-01-09

- Internal changes only

## 3.0.0-beta.1 - 2024-01-08

- Promoted to beta since no issues were found in the alpha release

## 3.0.0-alpha.5 - 2023-11-03

- Just testing the release automation

## 3.0.0-alpha.4 - 2023-11-03

- Just testing the release automation

## 3.0.0-alpha.3 - 2023-11-02

- Add more targets and change default branch to main [#75](https://github.com/PostHog/posthog-ios/pull/75)

## 3.0.0-alpha.2 - 2023-11-02

- Just testing the release automation

## 3.0.0-alpha.1 - 2023-11-02

- First alpha of the new major version of the iOS SDK
- Just testing the release automation

## 2.1.0 - 2023-10-10

- isFeatureEnabled now returns false if disabled [#74](https://github.com/PostHog/posthog-ios/pull/74)
- Add preloadFeatureFlags configuration flag [#71](https://github.com/PostHog/posthog-ios/pull/71)

## 2.0.5 - 2023-10-06

- Update device type [#63](https://github.com/PostHog/posthog-ios/pull/63)
- `$active_feature_flags` event should filter non active flags ([#73](https://github.com/PostHog/posthog-ios/pull/73))

## 2.0.4 - 2023-10-05

- CoreTelephony should not be added to tvOS builds [#67](https://github.com/PostHog/posthog-ios/pull/67)
- Remote notifications methods do not throw if no default implementation [#67](https://github.com/PostHog/posthog-ios/pull/67)

## 2.0.3 - 2023-06-02

- Fixes an issue that interfered with a SwiftUI bug

## 2.0.2 - 2023-04-04

- Remove adclient

## 2.0.1 - 2023-03-20

- Accept `options` parameter on feature flag methods to enable/disable emitting usage events

## 2.0.0 - 2022-08-29

- Add support for groups, simplefeature flags, and multivariate feature flags

## 1.4.4 - 2021-11-19

Make enabled property public.

## 1.4.3 - 2021-11-02

Add `shouldSendDeviceID` config option.

## 1.4.2 - 2021-09-17

Fix Info.plist warning for Swift Package Manager

## 1.4.1 - 2021-09-17

Fix warning with Swift Package Manager

## 1.4.0 - 2021-05-27

Fix support for Swift Package Manager

## 1.3.0 - 2021-05-11

In the `identify` call the `distinct_id` field can no longer be `nil`.

## 1.2.3 - 2021-02-24

Renamed functions which were causing conflicts with Segment iOS library

## 1.2.2 - 2020-02-22

Swift Package Manager

## 1.2.1 - 2020-12-18

Also remove the `enableAdvertisingCapturing` and `adSupportBlock` config options

## 1.2.0 - 2020-12-18

Completely remove reference to the AdSupport framework

## 1.1.0 - 2020-10-03

Shift responsibility of IDFA collection to clients ([#5](https://github.com/PostHog/posthog-ios/pull/5))
by removing any references to Apple's AdSupport framework from the library. In case you need to
use the $device_advertisingId field, [see here](https://posthog.com/docs/libraries/ios) for how to enable it.

## 1.0.5 - 2020-08-25

Add Swift Package Manager support

## 1.0.4 - 2020-05-25

Fix selector typo with ad capturing, which resulted in a crash when moving your app to the foreground.

## 1.0.3 - 2020-05-20

Support passing in custom library version and name. This is used in the React Native client.

## 1.0.2 - 2020-05-18

Fix issues with launching the library and screen tracking.

## 1.0.0 - 2020-04-22

First Release.
