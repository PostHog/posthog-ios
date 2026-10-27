---
'posthog-ios': major
---

PostHog iOS 4.0. Every breaking change below names what to use instead.

**Changed**

- **Breaking:** raise the minimum deployment targets to iOS 15.0 (from 13.0, Mac Catalyst follows iOS), macOS 11.0 (from 10.15), tvOS 15.0 (from 13.0) and watchOS 10.0 (from 6.0).
- **Breaking:** require Xcode 26 or later (`swift-tools-version` 6.2) to build PostHog; the SDK still compiles in Swift 5 language mode.
- **Breaking:** pass a `PostHogFeatureFlagsLoaded` to the `reloadFeatureFlags(_:)` callback, whose `errorsLoading` is `true` when the reload failed. Update closures to `{ result in ... }` (or `{ _ in ... }`); in Objective-C the block takes a `PostHogFeatureFlagsLoaded *`.
- **Breaking:** mark callbacks the SDK can call off the main thread `@Sendable` and make `PostHogFeatureFlagsLoaded` `Sendable`, fixing a crash in Swift 6 apps when a `reloadFeatureFlags(_:)` callback is written in main-actor code.
  - Affected: `reloadFeatureFlags(_:)`, the `BeforeSendBlock` and `PostHogBeforeSendLogBlock` passed to `setBeforeSend(_:)` on `PostHogConfig` and `PostHogLogsConfig`, `PostHogConfig.getAnonymousId`, `PostHogConfig.pushIdentityProvider` and its `completion`, and `sessionReplayConfig.captureLogsConfig.logSanitizer`.
  - To update main-actor state from `reloadFeatureFlags(_:)` or `pushIdentityProvider`, hop with `Task { @MainActor in ... }`; the other callbacks return immediately and must not read main-actor state.
- **Breaking:** rename `PostHogLogLevel` to `PostHogConsoleLogLevel` and `PostHogLogEntry` to `PostHogConsoleLogEntry` (`PostHogConsoleLogLevelInfo`/`Warn`/`Error` in Objective-C).
- **Breaking:** return `nil` instead of the raw string for a malformed, empty or whitespace-only feature flag payload from `getFeatureFlagResult(_:)` and `getAllFeatureFlags()`, and stop JSON-decoding string payloads in `PostHogBootstrapConfig.featureFlagPayloads` a second time, so a bootstrapped `"123"` stays a `String`.
- **Breaking:** always record session replay as masked screenshots, which uses more bandwidth and CPU per frame than wireframes for apps that didn't set `screenshotMode`.
  - Custom-drawn content (custom `draw(_:)` views, maps, video, charts) is now visible in recordings: wrap anything sensitive in `postHogMask()` or tag it `ph-no-capture`.
  - `PostHogSessionReplayConfig.screenshotMode` is deprecated and has no effect: delete the assignment. Setting it to `false` no longer prevents screenshots.
- **Breaking:** delete events still queued on disk by a 2.x SDK instead of sending them when an app updates straight from 2.x to 4.0, and ignore a top-level `$set` and `message_id` in queued events. Distinct ID, anonymous ID, groups and cached feature flags still carry over.
- Name the visible screen in the replay screen name (SwiftUI screens report their view name) and stop sending a plain `UIViewController`'s `title`.
- Detect network reachability with `NWPathMonitor`: a path that needs user action (such as a VPN waiting for a password) counts as reachable, queues pause while cellular data is off for the app, and events captured in the first 100 ms after setup may leave out `$network_wifi` and `$network_cellular`.

**Added**

- Add `SessionReplay`, `CrashReporting` and `Surveys` Swift package traits (on by default) so SwiftPM apps can leave out session replay and the vendored libwebp, the vendored PLCrashReporter, or the survey engine and UI.

**Removed**

- **Breaking:** remove deprecated APIs.
  - `PostHogConfig.apiKey`, `PostHogConfig(apiKey:)` and `PostHogConfig(apiKey:host:)`: use `projectToken`, `PostHogConfig(projectToken:)` and `PostHogConfig(projectToken:host:)` (`projectToken:` and `projectToken:host:` in Objective-C).
  - `PostHogConfig.propertiesSanitizer` and `PostHogPropertiesSanitizer`: use `PostHogConfig.setBeforeSend(_:)` (`[config setBeforeSend:@[...]]` with `BoxedBeforeSendBlock`s in Objective-C).
  - `PostHogConfig.evaluationEnvironments`: use `evaluationContexts`.
  - `PostHogConfig.remoteConfig`: delete the assignment. Remote config is always loaded.
  - `PostHogSDK.getFeatureFlagPayload(_:)`: use `getFeatureFlagResult(_:)?.payload`, with `sendFeatureFlagEvent: false` to keep not capturing `$feature_flag_called` (`[sdk getFeatureFlagResultWithKey:key sendFeatureFlagEvent:NO].payload` in Objective-C).
  - `PostHogSessionReplayConfig.debouncerDelay`: use `throttleDelay`.
  - `PostHogSessionReplayConfig.maskPhotoLibraryImages`: delete the assignment. It had no effect.
- **Breaking:** remove `PostHogDataMode.cellular`, which behaved like `.any`: use `.any` (`PostHogDataModeAny` in Objective-C). `PostHogDataMode(rawValue: 1)` now returns `nil`.
- **Breaking:** remove the experimental `PostHogSessionReplayConfig.screenshotModeBackgroundCapture` option: delete the assignment. Screenshots are always captured on the main thread.
- **Breaking:** remove `version` and `build` from `Application Installed`, `Application Updated` and `Application Opened` events: use `$app_version` and `$app_build`.
- **Breaking:** remove SDK internals from the public API that were only public for PostHog's wrapper SDKs.
  - Moved behind `@_spi(PostHogInternal)`, with no stability guarantees: `postHogSdkName`, `postHogVersion`, `PostHogConfig.snapshotEndpoint`, `PostHogSessionManager` (use `PostHogSDK.getSessionId()`, `startSession()` and `endSession()`), and `PostHogStorageManager` and `PostHogConfig.storageManager` (use `identify`, `getDistinctId()` and `reset()`).
  - No longer public: `dateToMillis(_:)` (use `Int64(date.timeIntervalSince1970 * 1000)`), `imageToBase64(_:_:)`, `toISO8601String(_:)`, `toISO8601Date(_:)`, `sanitizeDictionary(_:)`, `deleteSafely(_:)`, `postHogiOSSdkName`, `Gzip`, `GzipError`, `CompressionLevel`, `ReachabilityError`, `UIColor.init(hex:)` and `UIColor.hexDescription(_:)`.
  - No longer exposed to Objective-C: `PostHogSessionManager.shared`, `PostHogSessionManager.setSessionId(_:)` and `PostHogConfig.snapshotEndpoint`.
- Remove the unavailable `ReachabilityChangedNotification` global.

**Fixed**

- Fix session replay recording nothing for apps whose window root is a SwiftUI view.
- Fix secure-entry text fields being unmasked inside a `postHogNoMask()` or `ph-no-mask` subtree.
