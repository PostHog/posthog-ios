# Migrating from PostHog iOS 3.x to 4.0

This guide covers what you need to change when you upgrade an app from PostHog iOS 3.x to 4.0.

1. [Before you upgrade](#before-you-upgrade): toolchain, deployment targets and installation.
2. [Changes the compiler won't flag](#changes-the-compiler-wont-flag): behavior that changes without a build error. Read this even if your app builds cleanly.
3. [Compile errors and how to fix them](#compile-errors-and-how-to-fix-them): removed and renamed APIs.
4. [Package traits](#package-traits): leaving out session replay, crash reporting or surveys.

For the full list of changes, see the [changelog](CHANGELOG.md).

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

The SDK still compiles in Swift 5 language mode, so your app can use Swift 5 or Swift 6 mode.

### Move from CocoaPods to Swift Package Manager

PostHog 4.0 is not published to CocoaPods. 3.x versions stay installable from CocoaPods.

1. Remove `pod 'PostHog'` from your `Podfile` and run `pod install`.
2. Add the package. In Xcode, choose **File > Add Package Dependencies…** and enter `https://github.com/PostHog/posthog-ios`. In a `Package.swift`:

   ```swift
   dependencies: [
       .package(url: "https://github.com/PostHog/posthog-ios.git", from: "4.0.0")
   ]
   ```

3. Add the `PostHog` library to your app target. `import PostHog` doesn't change.

### React Native and Flutter apps

Don't add posthog-ios 4.0 to a React Native or Flutter app yourself. These apps get the iOS SDK through their PostHog package (`posthog-react-native`, `posthog_flutter`). Upgrade to the major version of that package that moves to iOS SDK 4.0, and follow its migration notes.

## Changes the compiler won't flag

### Session replay always records screenshots

In 3.x, session replay recorded wireframes unless you set `screenshotMode = true`. In 4.0 it always records screenshots of the screen, with sensitive content masked. Wireframe recording is gone.

If your app didn't set `screenshotMode = true`:

- Recordings now show real pixels for everything that isn't masked, including custom-drawn content such as `draw(_:)` views, maps, video and charts.
- Each frame uses more bandwidth and CPU than a wireframe.

Check what your screens show before you ship 4.0. Text inputs and images are masked by default (`maskAllTextInputs` and `maskAllImages` are `true`). To hide anything else:

| To mask | SwiftUI | UIKit |
| --- | --- | --- |
| A view and everything inside it | `.postHogMask()` | add `ph-no-capture` to the view's `accessibilityIdentifier` |
| All text and text inputs | `sessionReplayConfig.maskAllTextInputs = true` | same |
| Every image | `sessionReplayConfig.maskAllImages = true` | same |
| System pickers (photos, contacts) | `sessionReplayConfig.maskAllSandboxedViews = true` | same |

`ph-no-capture` also works in `accessibilityLabel`. To keep pixels out of recordings entirely, turn replay off with `config.sessionReplay = false`.

In UIKit, a tagged view that fills the whole window and has subviews isn't masked itself: only its subviews are. If it draws sensitive content itself, move that drawing into a subview and tag the subview, or turn replay off.

Masking also covers more than in 3.x: content a masked view draws outside its bounds (unclipped images, layer shadows, button titles) is masked, and so are image attachments in labels and text views when `maskAllImages` is on. Secure-entry text fields stay masked inside a `.postHogNoMask()` or `ph-no-mask` subtree.

### Replay screen names

- The screen name shown for a recording comes from the screen that is visible. SwiftUI screens report their view name.
- A plain `UIViewController`'s `title` is no longer used as the replay screen name; its type name is used instead.

`$screen` events are named as in 3.x.

### Feature flag payloads

- A malformed, empty or whitespace-only payload now reads as `nil` from `getFeatureFlagResult(_:)` and `getAllFeatureFlags()`. In 3.x you got the raw string. The flag's value and enabled state don't change.
- Bootstrapped string payloads in `PostHogBootstrapConfig.featureFlagPayloads` stay strings. In 3.x, a bootstrapped `"123"` or `"true"` was decoded a second time and read back as a number or `Bool`.

If your code relied on getting the raw string back, make the payload valid JSON in PostHog.

### Lifecycle events lose `version` and `build`

`Application Installed`, `Application Updated` and `Application Opened` no longer send `version` and `build`. Every event already has `$app_version` and `$app_build`, so update insights, cohorts and actions that filter on `version` or `build`. `Application Updated` still sends `previous_version` and `previous_build`.

### Apps updating straight from 2.x

If an app updates from a 2.x SDK straight to 4.0, events still queued on disk by 2.x are deleted instead of sent. Distinct ID, anonymous ID, groups and cached feature flags still carry over. Updates from 3.x aren't affected.

### Network reachability

4.0 detects connectivity with `NWPathMonitor`:

- A connection that needs user action, such as a VPN waiting for a password, counts as reachable.
- Queues pause while cellular data is turned off for your app.
- Events captured in the first 100 ms after `setup()` may leave out `$network_wifi` and `$network_cellular`.

### Capture v1

4.0 sends analytics events to `/i/v1/analytics/events` instead of `/batch`. Session replay (`/s/`), logs (`/i/v1/logs`) and feature flags (`/flags`) keep their endpoints. Check these if they apply to you:

- **Reverse proxies and self-hosted instances:** forward `/i/v1/analytics/events` before you upgrade. PostHog Cloud already serves it. A 404 makes the SDK resend to `/batch` until the app restarts. 408, 500, 502, 503 and 504 keep the events and retry them; other errors, such as 403, 405 or 429, drop them.
- **`Authorization` in `requestHeaders`:** capture requests now send `Authorization: Bearer <projectToken>`, which replaces yours. Authenticate your proxy with another header, such as `X-Proxy-Token`.
- **Redirects:** only 307 and 308 redirects to the same origin as `host` are followed, at most 5 times. Other redirects drop the events, so point `host` at the final host.
- **Event validation:** PostHog drops an event with an empty event name, an empty distinct ID, or an event name or distinct ID over 200 UTF-8 bytes. The rest of the batch is still delivered. Shorten or hash long distinct IDs, such as JWTs, before you upgrade.
- **`projectToken`:** a personal API key (`phx_...`) now disables the SDK at setup. Use your project token (`phc_...`).
- **`$lib` and `$lib_version`:** PostHog sets these from the SDK. A value you set in properties, a super property or `beforeSend` is ignored.
- **Property precedence:** super properties now override SDK properties such as `$os`, and the properties you pass override `$is_identified`, `$process_person_profile` and `$geoip_disable`.
- **`$process_person_profile`, `$cookieless_mode`, `$ignore_sent_at`, `$product_tour_id`:** still work, but are sent as capture options. PostHog drops an event whose option value it can't read, such as `"maybe"`. New code can pass `options:` to `capture` instead.
- **Retries:** 429 and 3xx responses are no longer retried, `Retry-After` pauses sending for at most 30 seconds, and the wait between failed sends doubles from 1 second up to 30 seconds. Queued events are still kept until they're delivered.

## Compile errors and how to fix them

Removed and renamed APIs fail to build. For most of them Xcode names the replacement, and offers a fix-it for plain renames. Objective-C names are listed where they differ.

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
| `config.storageManager`, `PostHogStorageManager` | `identify(_:)`, `getDistinctId()` and `reset()` on `PostHogSDK` |

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
| `reloadFeatureFlags { ... }`<br>ObjC: `^{ ... }` | `reloadFeatureFlags { result in ... }` (or `{ _ in ... }`). `result.errorsLoading` is `true` when the reload failed.<br>ObjC: `^(PostHogFeatureFlagsLoaded *result) { ... }` |
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

Callbacks the SDK can call off the main thread are now `@Sendable`: `reloadFeatureFlags(_:)`, the blocks passed to `setBeforeSend(_:)` on `PostHogConfig` and `PostHogLogsConfig`, `getAnonymousId`, `pushIdentityProvider` and its `completion`, and `sessionReplayConfig.captureLogsConfig.logSanitizer`.

In Swift 6 mode, a closure that reads or writes main-actor state no longer compiles (Swift 5 mode warns). For `reloadFeatureFlags(_:)` and `pushIdentityProvider`, hop to the main actor:

```swift
PostHogSDK.shared.reloadFeatureFlags { result in
    Task { @MainActor in
        self.showNewFeature = !result.errorsLoading
    }
}
```

The other callbacks must return right away, so don't read main-actor state in them.

Arrays of plain closures still work with `setBeforeSend(_:)`. You don't need to retype them as `[BeforeSendBlock]`.

### Internal and utility APIs

These were public only for PostHog's own React Native and Flutter SDKs, or by accident:

| 3.x | 4.0 |
| --- | --- |
| `PostHogSessionManager` | `getSessionId()`, `startSession()` and `endSession()` on `PostHogSDK` |
| `postHogSdkName`, `postHogVersion`, `config.snapshotEndpoint` | No longer public. |
| `dateToMillis(_:)` | `Int64(date.timeIntervalSince1970 * 1000)` |
| `imageToBase64(_:_:)`, `toISO8601String(_:)`, `toISO8601Date(_:)`, `sanitizeDictionary(_:)`, `deleteSafely(_:)`, `postHogiOSSdkName`, `Gzip`, `GzipError`, `CompressionLevel`, `UIColor(hex:)`, `UIColor.hexDescription(_:)` | No longer public. Copy the code you need into your app. |
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
