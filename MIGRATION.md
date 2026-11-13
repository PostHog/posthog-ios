# Migrate the iOS SDK from 3.x.x to 4.0.0

The iOS SDK 4.x.x sends analytics and AI events to the [capture v1](https://posthog.com/docs/api/capture-v1) endpoints, `/i/v1/analytics/events` and `/i/v1/ai/events`.

Use the top right copy page button to work through this with your agents.

You don't need to make every change on the day you upgrade your SDK. Required changes fall in these categories:

- **Before you upgrade**: you should make these changes before you upgrade your SDK to posthog-ios 4.x.x.
- **During your upgrade**: These are changes that you need to make in the same PR that upgrades your SDK version.
- **Follow ups**: These are changes that can come in follow up PRs, because 4.x.x still accepts the old names and options.

## Checklist

Read the checklist first, then the sections that apply to you.

**Before you upgrade**

- [ ] You build with an Xcode older than 26, or your deployment targets are below iOS 15, macOS 11, tvOS 15, or watchOS 10 → [Check your toolchain](#check-your-toolchain)
- [ ] You install the SDK with CocoaPods, or a dSYM upload script uses the pod's path → [Leave CocoaPods](#leave-cocoapods)
- [ ] Your app is a React Native, Flutter, or Kotlin Multiplatform app → [Upgrade wrapper packages](#upgrade-wrapper-packages)
- [ ] You send events through a reverse proxy that doesn't serve `/i/v1/analytics/events` → [Prepare your proxy](#prepare-your-proxy)
- [ ] You authenticate your proxy with an `Authorization` header in `requestHeaders` → [Prepare your proxy](#prepare-your-proxy)
- [ ] You send events through a reverse proxy set up from PostHog's proxy guides before 29 October 2026, which strips `Authorization` → [Prepare your proxy](#prepare-your-proxy)
- [ ] You send events through a proxy that redirects capture requests, other than with a 307 or 308 to the same origin as `host` → [Prepare your proxy](#prepare-your-proxy)
- [ ] You set `projectToken` to a personal API key (`phx_...`) → [Use a project token](#use-a-project-token)
- [ ] You capture events with a distinct ID over 200 bytes → [Shorten distinct IDs](#shorten-distinct-ids)
- [ ] You have a flag whose variant is an empty string, which now reads as disabled → [Rename empty variants](#rename-empty-variants)

**During your upgrade**

- [ ] Your build fails on a removed or renamed API, such as a `reloadFeatureFlags` closure or `maxRetries` → [Fix removed APIs](#fix-removed-apis)
- [ ] You pass `@Sendable` callbacks such as `setBeforeSend` in Swift 6 mode → [Fix Sendable callbacks](#fix-sendable-callbacks)
- [ ] You leave features out with package traits → [Choose package traits](#choose-package-traits)
- [ ] You use session replay, where custom-drawn content, maps, video, and web views can now appear → [Review session replay](#review-session-replay)
- [ ] Your app is SwiftUI-rooted and has replay on → [Review session replay](#review-session-replay)
- [ ] An insight, cohort, or action uses `wireframe` in `$sdk_debug_replay_capture_mode` → [Review session replay](#review-session-replay)
- [ ] You rely on a plain `UIViewController`'s `title` as the replay screen name → [Check replay screen names](#check-replay-screen-names)
- [ ] Your code reads feature flag payloads and could get `nil` for a malformed one → [Check flag payloads](#check-flag-payloads)
- [ ] An insight, cohort, or action uses `version` or `build` on lifecycle events → [Update lifecycle filters](#update-lifecycle-filters)
- [ ] A cohort, insight, or action matches `$locale`, which now includes the region → [Update locale filters](#update-locale-filters)
- [ ] You set event properties to `NSNull()` or a `nil` optional → [Check null properties](#check-null-properties)
- [ ] You filter insights, cohorts, or actions on a `null` `$feature_flag_response` of `$feature_flag_called` to find missing flags → [Check null properties](#check-null-properties)
- [ ] You use `$network_wifi` or `$network_cellular` on events → [Check network reachability](#check-network-reachability)
- [ ] Your users can update from a 2.x.x SDK straight to 4.x.x → [Check 2.x.x upgrades](#check-2xx-upgrades)
- [ ] You capture events with an empty event name, or with an event name over 200 bytes → [Check dropped events](#check-dropped-events)
- [ ] You set an empty distinct ID in `beforeSend` → [Check dropped events](#check-dropped-events)
- [ ] You set `$cookieless_mode`, `$ignore_sent_at`, or `$product_tour_id` to a value PostHog can't read, such as `"maybe"` → [Check dropped events](#check-dropped-events)
- [ ] You read the SDK's debug log, for example in log-based alerts → [Check dropped events](#check-dropped-events)
- [ ] You read `$session_id` or `$window_id` from the raw request body, for example in a proxy → [Check session IDs](#check-session-ids)
- [ ] You register a super property, or pass an event property, with the same key as one the SDK sets, such as `$os`, `$is_identified`, or `$geoip_disable`, and expect the SDK's value to win → [Check property precedence](#check-property-precedence)
- [ ] You replace `event.options` in `beforeSend`, or return an event kept from an earlier call → [Keep options in beforeSend](#keep-options-in-beforesend)
- [ ] You register `$process_person_profile` as `false` and expect it to keep every event personless → [Check registered person processing](#check-registered-person-processing)
- [ ] You rely on a `Retry-After` longer than 30 seconds → [Check retries and batches](#check-retries-and-batches)
- [ ] You might go back to 3.x.x after you ship 4.x.x → [Plan your rollback](#plan-your-rollback)

**Follow ups**

- [ ] You set legacy option properties like `$cookieless_mode` → [Move to event options](#move-to-event-options)
- [ ] You capture `$ai_*` events with `capture` → [Send AI events with captureAi](#send-ai-events-with-captureai)

## Before you upgrade

### Check your toolchain

posthog-ios 4.x.x raises the Xcode version and the deployment targets:

| | 3.x.x | 4.x.x |
| --- | --- | --- |
| Xcode | `swift-tools-version` 5.3 | 26 or later (`swift-tools-version` 6.2) |
| iOS and Mac Catalyst | 13.0 | 15.0 |
| macOS | 10.15 | 11.0 |
| tvOS | 13.0 | 15.0 |
| watchOS | 6.0 | 10.0 |
| visionOS | 1.0 | 1.0 |
| Installation | Swift Package Manager or CocoaPods | Swift Package Manager only |

The SDK still compiles in Swift 5 language mode, so your app can use Swift 5 or Swift 6 mode.

App Store Connect uploads already require Xcode 26. The toolchain floor mainly affects ad-hoc, enterprise, Mac, and local builds still on Xcode 16 or older.

### Leave CocoaPods

posthog-ios 4.x.x isn't published to CocoaPods. The repository no longer has a `PostHog.podspec`, so `pod 'PostHog', :git => ...` can't install 4.x.x either.

posthog-ios 3.x.x versions stay installable from CocoaPods, but [CocoaPods trunk becomes read-only on December 2, 2026](https://blog.cocoapods.org/CocoaPods-Specs-Repo/).

Move to Swift Package Manager:

1. Remove `pod 'PostHog'` from your `Podfile` and run `pod install`.
2. Add the package. In Xcode, choose **File > Add Package Dependencies…** and enter `https://github.com/PostHog/posthog-ios`. In a `Package.swift`:

   ```swift
   dependencies: [
       .package(url: "https://github.com/PostHog/posthog-ios.git", from: "4.0.0")
   ]
   ```

3. Add the `PostHog` library to your app target. `import PostHog` doesn't change.
4. If a Run Script phase uploads dSYMs with `${PODS_ROOT}/PostHog/build-tools/upload-symbols.sh`, change the path to `${BUILD_DIR%/Build/*}/SourcePackages/checkouts/posthog-ios/build-tools/upload-symbols.sh`. The old path no longer exists once the pod is gone, so symbol upload fails and crash reports lose symbolication.

### Upgrade wrapper packages

Don't add the iOS SDK 4.x.x to a React Native, Flutter, or Kotlin Multiplatform app yourself. These apps get the iOS SDK through their PostHog package (`@posthog/react-native-plugin`, `posthog_flutter`, `posthog-kmp`).

Upgrade to the version of that package that moves to the iOS SDK 4.x.x, and follow its migration notes.

### Prepare your proxy

posthog-ios 4.x.x sends data to these endpoints:

| Data | 3.x.x | 4.x.x |
| --- | --- | --- |
| Analytics events | `/batch` | `/i/v1/analytics/events` |
| Session replay | `/s/` | `/s/`, unchanged |
| AI events (`captureAi`) | None | `/i/v1/ai/events` |
| Logs | `/i/v1/logs` | `/i/v1/logs`, unchanged |
| Feature flags | `/flags` | `/flags`, unchanged |

For AI events, see [Send AI events with captureAi](#send-ai-events-with-captureai).

Capture v1 requests send the project token in an `Authorization: Bearer <projectToken>` header instead of an `api_key` body field.

This header replaces any `Authorization` header you set in `PostHogConfig.requestHeaders`, so authenticate your proxy with a different header, such as `X-Proxy-Token`. Other requests still send your `Authorization` header.

PostHog Cloud (`us.i.posthog.com`, `eu.i.posthog.com`) serves both capture v1 endpoints.

If you send events through your own reverse proxy, update it before you upgrade:

- **Forward both routes.** Forward `/i/v1/analytics/events` and `/i/v1/ai/events` to PostHog.
- **Pass the headers through unchanged.** Pass `Authorization`, every `PostHog-*` header, `Content-Type`, `Content-Encoding`, and `User-Agent`. `Authorization` holds the project token, sent as `Bearer <token>`. PostHog answers `401` without `Authorization` and `400` without the others, and the batch is dropped.
- **Keep PostHog's credentials.** If your proxy strips other credentials, keep `Authorization` values that start with `Bearer phc_`, `Bearer phs_`, or `Bearer phx_`, or the exact `Bearer <key>` of an older key without a prefix.
- **Pass the response body through unchanged.** A 2xx response whose body isn't PostHog's `{"results": {...}}` drops the events instead of retrying them.
- **Accept request bodies up to 20 MB.** AI requests are often larger than 1 MB, the default limit in nginx and ingress-nginx. On a `413` from the proxy, the SDK splits the batch and drops any event that is still too large on its own.

PostHog's managed reverse proxy already does this and needs no change.

A proxy set up from PostHog's [proxy guides](https://posthog.com/docs/advanced/proxy) before 29 October 2026 strips `Authorization`, so PostHog answers `401` and the events are dropped. Update it from the current guide.

The SDK doesn't fall back to `/batch`. A 404 is retried, so events stay queued until the route is served. Other error statuses that aren't retried, such as 403 or 405, drop the events.

The SDK follows a 307 or 308 redirect only to the origin of `host`, at most 5 times, and resends the same body and headers. The origin is the same scheme, host, and port.

Any other redirect isn't followed, and the events are dropped. In 3.x.x, `URLSession` followed redirects to any host.

If a proxy redirects capture requests to another host, point `host` at the final host.

### Use a project token

A personal API key (`phx_...`) in `projectToken` disables the SDK at setup, as an empty or whitespace-only token does. The SDK prints a warning that explains why, also without `debug`.

In 3.x.x, the SDK started and PostHog rejected every event with a 401. Use your project token (`phc_...`).

The SDK trims whitespace from `projectToken`, as in 3.x.x. To turn the SDK off in tests, use an empty token.

### Shorten distinct IDs

PostHog drops an event whose distinct ID is over 200 UTF-8 bytes. Legacy capture shortened the ID to 200 characters and kept the event.

The distinct ID can come from `identify(_:)`, the `distinctId` argument of `capture`, or `beforeSend`.

If you identify users with a long ID, such as a JWT or a long email address, shorten or hash it before you upgrade. Otherwise every event for that user is dropped.

### Rename empty variants

A flag whose variant is an empty string reads as disabled in 4.x.x, so rename the variant before you upgrade.

PostHog no longer accepts empty variants for new flags, so only flags created earlier through the API, MCP, or Terraform are affected. `/flags` still returns `enabled: true` for them, and other PostHog SDKs can still report them as enabled.

In 4.x.x the flag reads like this:

- **`isFeatureEnabled(_:)`.** It returns `false`, with or without `defaultValue`. In 3.x.x it returned `true`.
- **`enabled`.** It's `false` in `getFeatureFlagResult(_:)` and `getAllFeatureFlags()`. In 3.x.x it was `true`.
- **`PostHogFeatureFlagsLoaded`.** It leaves the flag out of `flags` and `variants`.
- **Captured events.** They leave the flag out of `$active_feature_flags`. In 3.x.x, events listed the flag.
- **The variant.** `variant`, `getFeatureFlag(_:)`, and the event's `$feature/<key>` property still return `""`.

## During your upgrade

### Fix removed APIs

Removed and renamed APIs fail to build. For most of them Xcode names the replacement, and offers a fix-it for plain renames.

Internal and utility APIs get a plain "cannot find in scope" error, so look those up here. Objective-C names are listed where they differ.

Of the capture v1 changes, only the `maxRetries` rename produces a compile error. The compile error names the new property, and Xcode offers a fix-it. Since 3.73.0 it has only limited push-notification subscription retries.

Rename these configuration APIs:

| 3.x.x | 4.x.x |
| --- | --- |
| `PostHogConfig(apiKey:)`<br>ObjC: `apiKey:` | `PostHogConfig(projectToken:)`<br>ObjC: `projectToken:` |
| `PostHogConfig(apiKey:host:)`<br>ObjC: `apiKey:host:` | `PostHogConfig(projectToken:host:)`<br>ObjC: `projectToken:host:` |
| `config.apiKey` | `config.projectToken` |
| `config.evaluationEnvironments` | `config.evaluationContexts` |
| `config.remoteConfig` | Delete the assignment |
| `config.propertiesSanitizer`, `PostHogPropertiesSanitizer` | `config.setBeforeSend(_:)` (see below) |
| `config.dataMode = .cellular`<br>ObjC: `PostHogDataModeCellular` | `.any`<br>ObjC: `PostHogDataModeAny` |
| `config.maxRetries` | `config.pushNotificationSubscriptionMaxRetries` |
| `config.storageManager`, `PostHogStorageManager` | Methods on `PostHogSDK` |

Remote config is always loaded, so `config.remoteConfig` has nothing to set.

`PostHogDataMode(rawValue: 1)` now returns `nil`.

`config.maxRetries` only ever limited push-notification subscription retries.

Instead of a storage manager, use `identify(_:)`, `getDistinctId()`, `getAnonymousId()`, `getDeviceId()` and `reset()` on `PostHogSDK`. There's no public way to supply your own storage manager or set the IDs directly.

Replace `propertiesSanitizer` with a `beforeSend` block:

```swift
// 3.x.x
config.propertiesSanitizer = MySanitizer()

// 4.x.x
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

Replace these session replay APIs:

| 3.x.x | 4.x.x |
| --- | --- |
| `sessionReplayConfig.screenshotMode` | Delete the assignment |
| `sessionReplayConfig.maskPhotoLibraryImages` | Delete the assignment |
| `sessionReplayConfig.debouncerDelay` | `sessionReplayConfig.throttleDelay` |
| `PostHogLogLevel` | `PostHogConsoleLogLevel` |
| `PostHogLogEntry` | `PostHogConsoleLogEntry` |
| ObjC: `PostHogLogLevelInfo` | ObjC: `PostHogConsoleLogLevelInfo` |
| ObjC: `PostHogLogLevelWarn` | ObjC: `PostHogConsoleLogLevelWarn` |
| ObjC: `PostHogLogLevelError` | ObjC: `PostHogConsoleLogLevelError` |

Replay always records masked screenshots, so `screenshotMode` has nothing to set (see [Review session replay](#review-session-replay)).

`sessionReplayConfig.maskPhotoLibraryImages` had no effect.

Replace these feature flag APIs:

| 3.x.x | 4.x.x |
| --- | --- |
| `getFeatureFlagPayload(key)`<br>ObjC: `getFeatureFlagPayload:` | `payload` of `getFeatureFlagResult`<br>ObjC: `payload` of `getFeatureFlagResultWithKey:sendFeatureFlagEvent:` |
| `reloadFeatureFlags { ... }`<br>ObjC: `^{ ... }` | `reloadFeatureFlags { result in ... }`<br>ObjC: `^(PostHogFeatureFlagsLoaded *result) { ... }` |
| `PostHogSDK.didReceiveFeatureFlags` notification | `onFeatureFlags(_:)` (see below) |

To read a payload, call `getFeatureFlagResult(key, sendFeatureFlagEvent: false)?.payload`. In Objective-C, call `[sdk getFeatureFlagResultWithKey:key sendFeatureFlagEvent:NO].payload`.

The `reloadFeatureFlags` closure now takes a result. Write `{ _ in ... }` if you don't use it.

`result.errorsLoading` is `true` when the reload failed or the SDK isn't set up. After a failed reload, `result.variants` holds the last known flags. `result.errorsLoading` is `false` when the project is over its flag quota.

Replace the `didReceiveFeatureFlags` notification with `onFeatureFlags(_:)`:

```swift
// 3.x.x
NotificationCenter.default.addObserver(
    self, selector: #selector(flagsLoaded),
    name: PostHogSDK.didReceiveFeatureFlags, object: nil
)

// 4.x.x: runs on the main thread after each flag load
let subscription = PostHogSDK.shared.onFeatureFlags { loaded in
    // loaded.flags, loaded.variants, loaded.errorsLoading
}
// later, to stop listening:
subscription.unsubscribe()
```

In Objective-C, call `[[PostHogSDK shared] onFeatureFlags:^(PostHogFeatureFlagsLoaded *loaded) { ... }]`. You can subscribe before `setup()`.

These internal and utility APIs were public only for PostHog's own React Native and Flutter SDKs, or by accident:

| 3.x.x | 4.x.x |
| --- | --- |
| `PostHogSessionManager` | `getSessionId()`, `startSession()`, `endSession()` |
| `postHogSdkName`, `postHogVersion`, `config.snapshotEndpoint` | No longer public |
| ObjC: `[PostHogSessionManager shared]`, `setSessionId:`, `config.snapshotEndpoint` | No longer exposed to Objective-C |
| `dateToMillis(_:)`, `imageToBase64(_:_:)` | No longer public |
| `toISO8601String(_:)`, `toISO8601Date(_:)`, `sanitizeDictionary(_:)`, `deleteSafely(_:)` | No longer public |
| `postHogiOSSdkName`, `Gzip`, `GzipError`, `CompressionLevel` | No longer public |
| `UIColor(hex:)`, `UIColor.hexDescription(_:)` | No longer public |
| `ReachabilityError`, `ReachabilityChangedNotification` | Removed |

`getSessionId()`, `startSession()` and `endSession()` are on `PostHogSDK`. Custom session IDs (`setSessionId(_:)`) have no public replacement in 4.x.x.

A wrapper SDK that must read or set `postHogSdkName`, `postHogVersion`, or `config.snapshotEndpoint` can use `@_spi(PostHogInternal) import PostHog`, with no stability guarantees.

In Objective-C, `[[PostHogSDK shared] getSessionId]`, `startSession` and `endSession` replace the session calls.

For `dateToMillis(_:)`, use `Int64(date.timeIntervalSince1970 * 1000)`. For `imageToBase64(_:_:)`, copy the code you need into your app. A wrapper SDK can still use both through `@_spi(PostHogInternal) import PostHog`, with no stability guarantees.

For the ISO 8601 functions, `sanitizeDictionary(_:)`, `deleteSafely(_:)`, `postHogiOSSdkName`, the gzip types, and the `UIColor` hex functions, copy the code you need into your app.

Use `NWPathMonitor` if your app needs reachability.

For the full list of changes, see the [changelog](https://github.com/PostHog/posthog-ios/blob/main/CHANGELOG.md).

### Fix Sendable callbacks

Callbacks the SDK can call off the main thread are `@Sendable` in 4.x.x:

- **Feature flags.** `reloadFeatureFlags(_:)`.
- **`beforeSend`.** The blocks passed to `setBeforeSend(_:)` on `PostHogConfig` and `PostHogLogsConfig`.
- **Identity.** `getAnonymousId`, and `pushIdentityProvider` and its `completion`.
- **Replay logs.** `sessionReplayConfig.captureLogsConfig.logSanitizer`.
- **Type aliases.** `BeforeSendBlock` and `PostHogBeforeSendLogBlock`.

In Swift 6 mode, a closure that reads or writes main-actor state no longer compiles. Swift 5 mode warns.

For `reloadFeatureFlags(_:)` and `pushIdentityProvider`, hop to the main actor:

```swift
PostHogSDK.shared.reloadFeatureFlags { result in
    Task { @MainActor in
        self.showNewFeature = !result.errorsLoading
    }
}
```

The other callbacks must return right away, so don't read main-actor state in them.

A closure written inline in the call, such as `config.setBeforeSend { event in ... }`, works in both modes. A closure stored in a variable, or a method reference, depends on the language mode:

- **Swift 6 mode.** `config.setBeforeSend(sanitize)` fails with "converting non-Sendable function value to '@Sendable ...' may introduce data races". Declare the closure as `BeforeSendBlock` (`let sanitize: BeforeSendBlock = { ... }`), or pass it in an array: `config.setBeforeSend([sanitize])`.
- **Swift 5 mode.** `config.setBeforeSend([sanitize])` fails with "ambiguous use of 'setBeforeSend'". Pass the closure directly instead: `config.setBeforeSend(sanitize)`, or declare it as `BeforeSendBlock`.

An array of closures stored in a variable works in both modes, so you don't need to retype it as `[BeforeSendBlock]`.

The same applies to `config.logs.setBeforeSend(_:)`, with `PostHogBeforeSendLogBlock`.

### Choose package traits

posthog-ios 4.x.x splits three features into Swift package traits, all on by default:

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

Use `traits: []` to leave out all three. If you leave features out, list every trait you want to keep.

In an Xcode app project, you can choose traits for a package dependency from Xcode 26.4. Check that the build leaves the feature out.

When a trait is off, its public API is removed too. Code that uses it fails to compile instead of silently doing nothing, except where noted:

- **`SessionReplay` off.** It removes `config.sessionReplay`, `config.sessionReplayConfig`, `PostHogSessionReplayConfig`, the console log types, `startSessionRecording()`, `startSessionRecording(resumeCurrent:)`, `stopSessionRecording()`, `isSessionReplayActive()`, and `.postHogNoMask()`. The `URLSession` helpers `postHogData`, `postHogDownload` and `postHogUpload` still compile, but record no network requests.
- **`CrashReporting` off.** It removes `errorTrackingConfig.autoCapture`. `captureException` and the rest of `errorTrackingConfig` still work.
- **`Surveys` off.** It removes `config.surveys`, `config.surveysConfig`, `PostHogSurveysConfig`, `PostHogSurveysDelegate` and the survey display types.

`.postHogMask()` stays available, because it also keeps tap autocapture out of masked areas.

SwiftPM turns a trait on if any package in your dependency graph depends on posthog-ios with the default traits. You can only leave a feature out if every dependency does too.

### Review session replay

Session replay always records screenshots of the screen in 4.x.x, with sensitive content masked. In 3.x.x, it recorded wireframes unless you set `screenshotMode = true`. Wireframe recording is gone.

If your app didn't set `screenshotMode = true`:

- **Real pixels.** Recordings show real pixels for everything that isn't masked, including custom-drawn content such as `draw(_:)` views, maps, video, and charts.
- **Web views.** `WKWebView` content is recorded in full when both `maskAllTextInputs` and `maskAllImages` are off. Wireframes only sent a placeholder.
- **Cost.** Each frame uses more bandwidth and CPU than a wireframe.

If your app's window root is a SwiftUI view, replay recorded nothing in 3.x.x unless you set `screenshotMode = true`. With `config.sessionReplay = true`, these apps start recording on 4.x.x. That counts against your replay quota and may need a consent or privacy disclosure update.

`$sdk_debug_replay_capture_mode` is always `screenshot`, so update any filter on `wireframe`.

Check what your screens show before you ship 4.x.x. Review recordings on a test build, and add masks where needed.

Text inputs, images, and system pickers are masked by default: `maskAllTextInputs`, `maskAllImages`, and `maskAllSandboxedViews` are `true`. Set any of them to `false` to show that content. To hide anything else:

| To mask | SwiftUI | UIKit |
| --- | --- | --- |
| A view and everything inside it | `.postHogMask()` | `ph-no-capture` in the view's `accessibilityIdentifier` |
| All text and text inputs | `sessionReplayConfig.maskAllTextInputs = true` (default) | same |
| Every image | `sessionReplayConfig.maskAllImages = true` (default) | same |
| System pickers (photos, contacts) | `sessionReplayConfig.maskAllSandboxedViews = true` (default) | same |

In UIKit, `maskAllImages` doesn't mask SF Symbols or images bundled with your app. To mask an exempt image, tag its image view with `ph-no-capture`. `ph-no-capture` also works in `accessibilityLabel`. To keep pixels out of recordings entirely, turn replay off with `config.sessionReplay = false`.

Secure-entry text fields stay masked inside a `.postHogNoMask()` or `ph-no-mask` subtree.

If you upgrade from a version before 3.93.1, masking also covers two more things, with the same UIKit exceptions:

- **Content outside a masked view's bounds.** Unclipped images, layer shadows, and button titles that a masked view draws outside its bounds.
- **Image attachments.** Image attachments in labels and text views, when `maskAllImages` is on.

> **Known limitation.** If a masked view sits inside a view backed by your app's own `CALayer` subclass, such as a Lottie animation view, the SDK can't safely read where the masked view is on screen. It masks the whole window for that frame. Fast scrolling on a screen that holds such a layer may also drop replay frames.

### Check replay screen names

- **Visible screen.** The screen name shown for a recording comes from the screen that is visible. SwiftUI screens report their view name.
- **Plain view controllers.** A plain `UIViewController`'s `title` is no longer used as the replay screen name, so it reports no name. This includes storyboard scenes without a custom class.
- **Subclasses.** Subclasses still report their type name without `ViewController`. `CheckoutViewController` becomes `Checkout`.

`$screen` events are named as in 3.x.x.

### Check flag payloads

- **Malformed payloads.** A malformed, empty, or whitespace-only payload reads as `nil` from `getFeatureFlagResult(_:)` and `getAllFeatureFlags()`. In 3.x.x you got the raw string. The flag's value and enabled state don't change.
- **Bootstrapped payloads.** Bootstrapped string payloads in `PostHogBootstrapConfig.featureFlagPayloads` stay strings. In 3.x.x, a bootstrapped `"123"` or `"true"` was decoded a second time and read back as a number or `Bool`.

If your code relied on getting the raw string back, make the payload valid JSON in PostHog.

A cached bootstrapped string payload can read as `nil` until the next `/flags` response. That happens when an app's last 3.x.x launch cached the payload, got no `/flags` response afterwards, and no longer passes bootstrap values.

For flags whose variant is an empty string, see [Rename empty variants](#rename-empty-variants).

### Update lifecycle filters

`Application Installed`, `Application Updated`, and `Application Opened` no longer send `version` and `build`.

Every event already has `$app_version` and `$app_build`, so update insights, cohorts, and actions that filter on `version` or `build`.

- **`Application Updated`.** It still sends `previous_version` and `previous_build`.
- **Cold launches.** If you used "`version` is set" on `Application Opened` to find cold launches, filter on `from_background = false` instead.
- **Stored events.** Events already stored keep the old fields.

### Update locale filters

`$locale` means the device's preferred language, with its region: `de-CH` instead of `de`, and `fr-FR` when your app only supports English. This matches Android's format and the property's definition.

If a user picks a language for your app in iOS Settings, iOS reports that language as the first preferred language, so `$locale` follows it.

The Android SDK 4.x.x reports the device-wide language even when a per-app language is set, so for those users `$locale` means different things on iOS and Android.

The new `$app_language` property is the language your app shows. It's the closest match to what `$locale` used to mean, but not always the same value. `$locale` sent only the language code, and `$app_language` sends your app's full localization name.

An app localized as `de` still sends `de`. An app localized as `pt-BR` or `zh-Hans` sends that, where `$locale` sent `pt` or `zh`.

If you use your own language setting instead of iOS localizations, call `PostHogSDK.shared.setAppLanguage("de")` at startup and whenever it changes.

Update cohorts, insights, and actions that match `$locale`:

- **Exact matches.** A filter on `$locale = de` stops matching `de-CH`.
- **The language your app shows.** Use `$app_language`, with a regex such as `^pt(-|$)` if you ship regional or script localizations.
- **Device language.** Use a regex on `$locale` such as `^de(-|$)`, because "contains" also matches `en-DE`.
- **Older events.** Events already stored and app versions still on 3.x.x keep the old `$locale` and have no `$app_language`.

Feature flags aren't affected. The SDK doesn't send `$locale` or `$app_language` with flag requests, so flags only see these if you set them as person properties yourself.

### Check null properties

An event property set to `NSNull()` or to a `nil` optional is left out of the event instead of being sent as `null`. This also applies inside nested dictionaries and dictionaries in arrays, and when `beforeSend` sets it.

- **Arrays.** An array keeps a `null` element at its position.
- **Empty dictionaries.** A dictionary left empty is sent as `{}`.
- **Other values.** `false`, `0`, `""`, and empty arrays are sent as before.
- **`NSNull()`.** You can still pass it.
- **Person and group properties.** To clear a person or group property, `$set`, `$set_once`, and `$group_set` still send `null` values.
- **Flag events.** A `$feature_flag_called` event for a flag with no value has no `$feature_flag_response` instead of `null`. Filters on a `null` `$feature_flag_response` stop matching new events without any error, so use an `is not set` filter instead.

### Check network reachability

posthog-ios 4.x.x detects connectivity with `NWPathMonitor`:

- **Connections that need user action.** A connection that needs user action, such as a VPN waiting for a password, counts as reachable.
- **Cellular data turned off.** Queues pause while cellular data is turned off for your app.
- **Early events.** Events captured in the first 100 ms after `setup()` may leave out `$network_wifi` and `$network_cellular`.

### Check 2.x.x upgrades

If an app updates from a 2.x.x SDK straight to 4.x.x, events still queued on disk by 2.x.x are deleted instead of sent. Distinct ID, anonymous ID, groups, and cached feature flags still carry over. Events created by 3.x.x aren't affected.

If 3.x.x copied a 2.x.x event into its queue and it's still unsent, 4.x.x sends it but ignores its top-level `$set` and `message_id`. Those person properties aren't set, and the event gets a new uuid unless it has a `uuid` field.

### Check dropped events

Capture v1 checks each event on its own and drops only the invalid ones, so the rest of the batch is delivered. In 3.x.x, an empty event name or distinct ID made legacy capture reject the whole batch it was in.

The SDK drops an event with an empty event name before sending it, for example `capture("")` or a name `beforeSend` sets to `""`. `captureAi` then returns `nil`, and with `debug` on the SDK logs the first one.

The SDK doesn't check these events before sending. PostHog drops the event, and the SDK removes it from the queue:

- **Empty distinct IDs.** PostHog drops an event with an empty or whitespace-only distinct ID, for example one `beforeSend` sets to `""`.
- **Long event names.** PostHog drops an event whose name is over 200 UTF-8 bytes. Legacy capture had no limit on event name length.
- **Long distinct IDs.** PostHog drops an event whose distinct ID is over 200 UTF-8 bytes (see [Shorten distinct IDs](#shorten-distinct-ids)).
- **Option values.** The SDK sends option values as given, including the ones it takes from legacy option properties (see [Move to event options](#move-to-event-options)). PostHog reads common forms of a value, such as `"false"` or `0` for a boolean, and drops an event whose option value it can't read.

An empty or whitespace-only `distinctId` argument isn't dropped. Like `nil`, it uses the current distinct ID. `identify` ignores an empty or whitespace-only distinct ID. 3.x.x ignored only an empty one.

With `debug` on, the SDK logs how many events were dropped and why. The line has counts and PostHog's drop reasons, never event names, uuids, or properties.

There's no error callback, and the log text changed from 3.x.x, so update any log-based alerts. With `debug` on, the SDK no longer logs a line for each queued event, and a failed capture request no longer logs PostHog's response body. 3.x.x did both.

The SDK changes some values instead of dropping the event:

- **Non-JSON values.** A `NaN`, infinite, or other non-JSON property value is removed before sending, and the event is still sent.
- **Keys that aren't strings.** In a nested dictionary, a key that isn't a string, such as an `Int`, `Double`, or `Bool`, is sent as its string form. `["scores": [1: "gold"]]` is sent as `{"scores": {"1": "gold"}}`.
- **Keys with no string form.** The key is removed, and the rest of the dictionary is sent. In 3.x.x, the SDK removed the whole nested dictionary.

Each event needs its own uuid. PostHog keeps the first copy in a request and drops later events with the same uuid.

The SDK generates a uuid for each capture and keeps it through `beforeSend`, even when the hook returns an event kept from an earlier call. You can't send a repeated uuid by accident.

Event uuids and anonymous distinct IDs are UUID v7, as in 3.x.x. The new `PostHog-Request-Id` header is a UUID v7 too.

The SDK sends every timestamp in UTC with 3 fractional digits, for example `2026-01-01T00:00:00.000Z`, as 3.x.x did. It doesn't check for future timestamps. PostHog replaces a timestamp more than 23 hours ahead with the time it received the event.

### Check session IDs

Capture v1 sends `$session_id` and `$window_id` as top-level `session_id` and `window_id` fields, not as properties. The SDK moves them out of `properties` for you, by the value's type:

- **A string.** The SDK sends it unchanged, including an empty string.
- **A null value.** It counts as unset, and the SDK removes it without a warning.
- **Any other value.** The SDK removes it and doesn't send it. With `debug` on, the SDK logs a warning that names the key and the value's JSON type, never the value.

In PostHog, the events still have `$session_id` and `$window_id`, so insights, filters, and session replay work as before.

A registered `$session_id` overrides the SDK's session ID (see [Check property precedence](#check-property-precedence)), which can detach events from their session replay.

### Check property precedence

An event's properties are merged in this order, and later values win:

1. Properties the SDK sets itself, such as `$os`, `$app_version`, `$screen_name`, `$is_identified`, `$geoip_disable`, and the session replay debug properties.
2. Registered super properties (`register`).
3. The properties you pass to `capture` or another event-sending method.
4. `beforeSend`.

In 3.x.x, the SDK's own values won over super properties. `$is_identified`, `$process_person_profile`, `$geoip_disable`, and the session replay debug properties also won over the properties you pass.

In 4.x.x a value you register or pass wins. For example, `capture("signed_up", properties: ["$geoip_disable": false])` sends that event with GeoIP enabled even when `disableGeoIp` is on.

Person properties and groups are applied between steps 2 and 3:

- **Per-call `userProperties` and `userPropertiesSetOnce`.** They replace a registered `$set` or `$set_once` whole, as in 3.x.x.
- **`$set` or `$set_once` in the properties.** It also replaces a registered one whole. The two aren't merged.
- **Groups.** Groups set with `group()` and per-call `groups` are applied there too, and replace a registered `$groups`.
- **Both at once.** If you also pass `$set`, `$set_once`, or `$groups` in the properties, the per-call `userProperties`, `userPropertiesSetOnce`, and `groups` win key by key over them. In 3.x.x, `$set` and `$set_once` in the properties replaced the per-call values, and `$groups` in the properties won per key.

`$lib` and `$lib_version` are the exception. The SDK fills them as a pair after all of the above, before `beforeSend`.

If `$lib` is missing or empty, the SDK sets both, replacing a `$lib_version` you passed on its own. If `$lib` names another library, the SDK leaves both as you set them and doesn't add its own version.

### Keep options in beforeSend

Review your `beforeSend` hooks for the new event shape. Capture v1 reads processing settings from an `options` object sent next to `properties`, and `beforeSend` can read and change `PostHogEvent.options`.

In 3.x.x, the SDK marked person processing with the `$process_person_profile` property. In 4.x.x, it's the `process_person_profile` option, and the property isn't set.

A hook that replaces `event.options` without keeping that key, or returns an event kept from an earlier call, can lose the `false` the SDK set. That turns person processing on for anonymous users, overriding `personProfiles`.

### Check registered person processing

A registered `$process_person_profile` changes person processing for every event. In 3.x.x, the SDK replaced a registered `$process_person_profile` with its own value, so a registered `false` had no effect.

In 4.x.x a registered `false` applies, also after `identify` and with `personProfiles` set to `.always`. Those events don't change the person profile, and their `$set` is ignored. They're still linked to the person and billed as identified events.

A registered `$process_person_profile`, or a `process_person_profile` option a wrapper SDK registers, doesn't apply to identity events: `$identify`, `$create_alias`, `$merge_dangerously`, `$groupidentify`, `$set`, and `$set_once`. With person processing off, PostHog drops `$identify`, `$create_alias`, `$merge_dangerously`, and `$groupidentify`, and keeps `$set` and `$set_once` but ignores their person update. So a registered `false` would stop `identify`, `alias`, `group`, and `setPersonProperties` from working.

A value you pass on the call, or set in `beforeSend`, still applies. To create no person profiles at all, set `personProfiles` to `.never`. The SDK then skips these calls.

### Check retries and batches

| Behavior | 4.x.x | 3.x.x |
| --- | --- | --- |
| Statuses retried | Network errors and 404, 408, 429, 500, 502, 503, and 504 responses | Also 3xx, but not 404 |
| `Retry-After` cap | 30 seconds | None, or 5 minutes for logs |
| Wait after a failed send | Doubles, from 1 to 30 seconds | Grew by 1 second per failure |
| Request size limit | `maxBatchSize` events and about 5 MiB | Event count only |
| An analytics event over 1,000,000 serialized bytes | Dropped on its own | Dropped after a 413 |

In 3.x.x, the SDK didn't retry 404, and retried 3xx responses.

In 4.x.x, `Retry-After` sets the minimum wait before the next send, up to 30 seconds. This also applies to session replay and logs. In 3.x.x, analytics events and session replay had no cap, and logs allowed up to 5 minutes.

In 4.x.x, the wait after a failed send doubles from 1 second up to 30 seconds, with up to 25% random jitter. This applies to events, session replay, and logs.

A 4.x.x request holds at most `maxBatchSize` events and about 5 MiB. The SDK sends as soon as about 5 MiB of events is queued, even before `flushAt` is reached. In 3.x.x, batches were limited by event count only.

In 4.x.x, PostHog drops only the analytics event that is over 1,000,000 serialized bytes. With `debug` on, the drop line says `event_too_big`. In 3.x.x, the event got a 413 for its whole batch, and was dropped once the SDK had split the batch down to it.

These rules also apply:

- **Other statuses.** A status that isn't retried, such as a 402 when you're over your billing limit, drops the whole request. A product quota, such as for exceptions or AI events, instead drops only those events inside a 200.
- **Partial retries.** When the response asks to retry only some events, the SDK keeps those events queued and removes the rest.
- **No retry limit.** Event, session replay, and log retries have no limit, as in 3.x.x. Queued records stay until they're delivered or a full queue evicts them (`maxQueueSize`, or `logs.maxBufferSize` for logs).
- **A 413.** A 413 halves the batch and resends it, until a request carries one event. A single event that still gets a 413 is dropped. 3.x.x did the same.
- **Large events.** The SDK has no per-event size limit for analytics events, as in 3.x.x. An event larger than about 5 MiB is sent in a request of its own.
- **`beforeSend`.** It runs when you capture the event, before it's queued, so batching, splitting, and retries never change what it sees.

### Plan your rollback

If you ship 4.x.x and then go back to 3.x.x, 3.x.x sends the events still queued on the device. 3.x.x doesn't read capture options:

- **Personless events.** Events that 4.x.x marked as personless (`process_person_profile: false`) are processed as person events.
- **Other options.** Options such as `cookieless_mode` passed through `options` are lost.
- **AI events.** AI events queued by 4.x.x in their own queue aren't sent while the app runs 3.x.x. If you upgrade to 4.x.x again, 4.x.x sends them.

## Follow ups

### Move to event options

Capture v1 reads processing settings from an `options` object sent next to `properties`. `capture`, `screen`, `identify`, `setPersonProperties`, `alias`, `group`, and `captureException` take a new `options` argument:

```swift
// 3.x.x
PostHogSDK.shared.capture("signed_up", properties: ["$cookieless_mode": true])

// 4.x.x
PostHogSDK.shared.capture("signed_up", options: ["cookieless_mode": true])
```

For `identify`, the options apply to the `$identify` or `$set` event the call sends.

In Objective-C, use the selectors that end in `options:`. The selectors without `options:` still work.

- `captureWithEvent:distinctId:properties:userProperties:userPropertiesSetOnce:groups:timestamp:options:`
- `screenWithTitle:properties:options:`
- `identifyWithDistinctId:userProperties:userPropertiesSetOnce:options:`
- `setPersonPropertiesWithUserPropertiesToSet:userPropertiesToSetOnce:options:`
- `alias:options:`
- `groupWithType:key:groupProperties:options:`
- `captureExceptionWithError:properties:options:`
- `captureExceptionWithNSException:properties:options:`

The legacy option properties still work. They're the `$`-prefixed properties that legacy capture reads as settings. When the event is sent, the SDK removes each one from `properties` and uses it for its option:

| Legacy option property | Option |
| --- | --- |
| `$process_person_profile` | `process_person_profile` |
| `$cookieless_mode` | `cookieless_mode` |
| `$ignore_sent_at` | `disable_skew_correction` |
| `$product_tour_id` | `product_tour_id` |

These rules decide which value PostHog reads:

- **Precedence.** An option you pass to any of these methods or set in `beforeSend` wins over its legacy property. An option set to `NSNull()` counts as unset, so the legacy property fills it.
- **Person processing.** When `personProfiles` turns person processing off, the SDK sets the `process_person_profile` option to `false`. Otherwise it sends neither, because PostHog processes person profiles by default.
- **One event.** To change person processing for one event, pass the `process_person_profile` option or the `$process_person_profile` property.
- **Later events.** Calling `group()`, or passing `userProperties`, `userPropertiesSetOnce`, or `groups`, still turns person processing on for later events when `personProfiles` is `.identifiedOnly`, as in 3.x.x.
- **Other keys.** Other option keys are sent unchanged, and PostHog ignores keys it doesn't know.
- **Every event.** There are no global options. To set one for every event, register its legacy property, for example `register(["$cookieless_mode": true])`.
- **Queued events.** Events still queued on disk by 3.x.x are sent to capture v1 after the update, with their legacy properties moved to options.

For the changes every capture v1 SDK shares, such as event options, limits, and per-event results, see [Upgrading to capture v1 SDKs](https://posthog.com/docs/api/capture-v1).

### Send AI events with captureAi

posthog-ios 4.x.x adds `captureAi`. It sends AI events, such as `$ai_generation`, to PostHog's AI endpoint (`/i/v1/ai/events`) instead of the analytics endpoint.

`capture` never sends events to the AI endpoint, even ones named `$ai_*`.

`$ai_*` events you keep sending with `capture` still reach PostHog through the analytics endpoint, as in 3.x.x. Moving them to `captureAi` gets you the AI endpoint's much larger event size limit, and a queue of their own, so large AI events don't hold up your other events.

`captureAi` takes the same arguments as `capture`, and the events go through the same `beforeSend` hooks:

```swift
PostHogSDK.shared.captureAi("$ai_generation", properties: ["$ai_model": "gpt-5", "$ai_trace_id": traceId])
```

In Objective-C, use `captureAiWithEvent:distinctId:properties:userProperties:userPropertiesSetOnce:groups:timestamp:options:`.

- **Size.** An AI event's properties can be up to 8 MiB. The SDK drops a serialized event over 8 MiB + 64 KiB, and `captureAi` returns `nil`. Set `captureAiMaxEventBytes` to lower the limit. It measures the whole serialized event.
- **Person profiles.** Any `$ai_*` event never creates or updates a person profile, so `$set` and `$set_once` are ignored, and it's billed as an AI event. See [the `$ai_` prefix](https://posthog.com/docs/ai-observability/basics#the-ai_-prefix).
- **Event names.** PostHog drops an event sent with `captureAi` whose name doesn't start with `$ai_`.
- **Timeouts.** AI requests time out after 60 seconds without network activity, or `captureAiTimeout`. Other requests still time out after 10 seconds.
- **Queue.** AI events are queued on disk separately from other events. Up to 100 events (`captureAiMaxQueueSize`) and 50 MiB are kept, and the oldest are dropped first. `maxQueueSize` doesn't apply.
- **Compression.** AI requests are gzipped unless you set `captureAiCompression` to `.none`. `compression` doesn't apply.
- **Batching.** AI events use `flushAt`, `maxBatchSize`, and `flushIntervalSeconds`, like other events. A request carries up to about 5 MiB, as for analytics events (see [Check retries and batches](#check-retries-and-batches)).
- **Flushing.** `flush()` and `close()` also send AI events, and AI events left on disk are sent after the next launch.
- **Content.** The SDK sends AI events unchanged. It doesn't redact or truncate prompts, outputs, or media, so use `beforeSend` to remove anything you don't want to send.
