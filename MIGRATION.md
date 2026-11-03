# Migrating from PostHog iOS 3.x to 4.0

This guide covers what you need to change when you upgrade an app from PostHog iOS 3.x to 4.0.

1. [Before you upgrade](#before-you-upgrade): toolchain, deployment targets and installation.
2. [Changes the compiler won't flag](#changes-the-compiler-wont-flag): behavior that changes without a build error. Read this even if your app builds cleanly.
3. [Compile errors and how to fix them](#compile-errors-and-how-to-fix-them): removed and renamed APIs.
4. [Package traits](#package-traits): leaving out session replay, crash reporting or surveys.
5. [Upgrade checklist](#upgrade-checklist).

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

### Replay screen names

- The screen name shown for a recording comes from the screen that is visible. SwiftUI screens report their view name.
- A plain `UIViewController`'s `title` is no longer used as the replay screen name, so it reports no name. This includes storyboard scenes without a custom class. Subclasses still report their type name without `ViewController` (`CheckoutViewController` becomes `Checkout`).

`$screen` events are named as in 3.x.

### Feature flag payloads

- A malformed, empty or whitespace-only payload now reads as `nil` from `getFeatureFlagResult(_:)` and `getAllFeatureFlags()`. In 3.x you got the raw string. The flag's value and enabled state don't change.
- Bootstrapped string payloads in `PostHogBootstrapConfig.featureFlagPayloads` stay strings. In 3.x, a bootstrapped `"123"` or `"true"` was decoded a second time and read back as a number or `Bool`.

If your code relied on getting the raw string back, make the payload valid JSON in PostHog.

If an app's last 3.x launch cached a bootstrapped string payload, got no `/flags` response afterwards and no longer passes bootstrap values, that payload can read as `nil` until the next `/flags` response.

### Lifecycle events lose `version` and `build`

`Application Installed`, `Application Updated` and `Application Opened` no longer send `version` and `build`. Every event already has `$app_version` and `$app_build`, so update insights, cohorts and actions that filter on `version` or `build`. `Application Updated` still sends `previous_version` and `previous_build`. If you used "`version` is set" on `Application Opened` to find cold launches, filter on `from_background = false` instead. Events already stored keep the old fields.

### Apps updating straight from 2.x

If an app updates from a 2.x SDK straight to 4.0, events still queued on disk by 2.x are deleted instead of sent. Distinct ID, anonymous ID, groups and cached feature flags still carry over. Updates from 3.x aren't affected.

### Network reachability

4.0 detects connectivity with `NWPathMonitor`:

- A connection that needs user action, such as a VPN waiting for a password, counts as reachable.
- Queues pause while cellular data is turned off for your app.
- Events captured in the first 100 ms after `setup()` may leave out `$network_wifi` and `$network_cellular`.

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
| `postHogSdkName`, `postHogVersion`, `config.snapshotEndpoint` | No longer public. A wrapper SDK that must read or set them can use `@_spi(PostHogInternal) import PostHog`, with no stability guarantees. |
| ObjC: `[PostHogSessionManager shared]`, `setSessionId:`, `config.snapshotEndpoint` | No longer exposed to Objective-C. `[[PostHogSDK shared] getSessionId]`, `startSession` and `endSession` replace the session calls. |
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

## Upgrade checklist

- [ ] Build with Xcode 26 or later, and raise your deployment targets to at least iOS 15, macOS 11, tvOS 15 and watchOS 10.
- [ ] Move from CocoaPods to Swift Package Manager, including any dSYM upload script path.
- [ ] If you use session replay, review recordings on a test build: custom-drawn content, maps, video and web views can now appear. Add masks where needed.
- [ ] If your app is SwiftUI-rooted and has replay on, expect recordings to start, and check quota and consent.
- [ ] Update insights, cohorts and actions that use `version` or `build` on lifecycle events, or `wireframe` in `$sdk_debug_replay_capture_mode`.
- [ ] Check code that reads feature flag payloads and could get `nil` for a malformed one.
- [ ] Fix the compile errors using the tables above, including `reloadFeatureFlags` closures.
- [ ] If you use package traits, list every trait you want to keep.
