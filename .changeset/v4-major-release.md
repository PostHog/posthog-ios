---
'posthog-ios': major
---

PostHog iOS 4.0: see the [migration guide](https://github.com/PostHog/posthog-ios/blob/main/MIGRATION.md) to upgrade from 3.x.

- **Breaking:** stop publishing to CocoaPods — install with Swift Package Manager (3.x versions stay on CocoaPods)
- **Breaking:** raise minimum deployment targets to iOS and Mac Catalyst 15.0, macOS 11.0, tvOS 15.0 and watchOS 10.0
- **Breaking:** require Xcode 26 or later (`swift-tools-version` 6.2)
- **Breaking:** always record session replay as masked screenshots, which shows custom-drawn content and uses more bandwidth and CPU than wireframes — remove `screenshotMode` and `screenshotModeBackgroundCapture` assignments and mask sensitive content with `postHogMask()` or `ph-no-capture`
- **Breaking:** pass a `PostHogFeatureFlagsLoaded` to the `reloadFeatureFlags(_:)` callback — use `{ result in ... }` or `{ _ in ... }`
- **Breaking:** mark `reloadFeatureFlags(_:)`, `setBeforeSend(_:)`, `getAnonymousId`, `pushIdentityProvider` and `logSanitizer` callbacks `@Sendable`, fixing a crash in Swift 6 apps
- **Breaking:** rename `PostHogLogLevel` to `PostHogConsoleLogLevel` and `PostHogLogEntry` to `PostHogConsoleLogEntry`
- **Breaking:** return `nil` instead of the raw string for a malformed, empty or whitespace-only feature flag payload
- **Breaking:** stop decoding string payloads in `PostHogBootstrapConfig.featureFlagPayloads` a second time, so a bootstrapped `"123"` stays a `String`
- **Breaking:** delete events still queued on disk by a 2.x SDK instead of sending them, and ignore a top-level `$set` and `message_id` in queued events
- **Breaking:** remove `version` and `build` from `Application Installed`, `Application Updated` and `Application Opened` events — use `$app_version` and `$app_build`
- **Breaking:** remove `PostHogConfig.apiKey`, `PostHogConfig(apiKey:)` and `PostHogConfig(apiKey:host:)` — use `projectToken`, `PostHogConfig(projectToken:)` and `PostHogConfig(projectToken:host:)`
- **Breaking:** remove `PostHogConfig.propertiesSanitizer` and `PostHogPropertiesSanitizer` — use `setBeforeSend(_:)`
- **Breaking:** remove `PostHogConfig.evaluationEnvironments` — use `evaluationContexts`
- **Breaking:** remove the no-op `PostHogConfig.remoteConfig` and `PostHogSessionReplayConfig.maskPhotoLibraryImages` options
- **Breaking:** remove `PostHogSDK.getFeatureFlagPayload(_:)` — use `getFeatureFlagResult(_:sendFeatureFlagEvent:)?.payload`
- **Breaking:** remove `PostHogSessionReplayConfig.debouncerDelay` — use `throttleDelay`
- **Breaking:** remove the `PostHogSDK.didReceiveFeatureFlags` notification — use `onFeatureFlags(_:)`
- **Breaking:** remove `PostHogDataMode.cellular` — use `.any`
- **Breaking:** move `postHogSdkName`, `postHogVersion`, `PostHogConfig.snapshotEndpoint`, `PostHogSessionManager`, `PostHogStorageManager` and `PostHogConfig.storageManager` behind `@_spi(PostHogInternal)` — use `PostHogSDK` session and identity methods
- **Breaking:** remove `dateToMillis(_:)`, `imageToBase64(_:_:)`, `toISO8601String(_:)`, `toISO8601Date(_:)`, `sanitizeDictionary(_:)`, `deleteSafely(_:)`, `postHogiOSSdkName`, `Gzip`, `GzipError`, `CompressionLevel`, `ReachabilityError`, `ReachabilityChangedNotification`, `UIColor.init(hex:)` and `UIColor.hexDescription(_:)` from the public API
- Add `SessionReplay`, `CrashReporting` and `Surveys` Swift package traits (on by default) that remove the feature and its public API when turned off
- Change network reachability detection to `NWPathMonitor`, so a path needing user action counts as reachable, queues pause while cellular data is off for the app, and early events may omit `$network_wifi` and `$network_cellular`
- Change the replay screen name to the visible screen, reporting the view name for SwiftUI screens and no longer using a plain `UIViewController`'s `title`
- Fix session replay recording nothing for apps whose window root is a SwiftUI view
- Fix secure-entry text fields being unmasked inside a `postHogNoMask()` or `ph-no-mask` subtree
