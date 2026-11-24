# Getting started

The iOS SDK runs in iOS and other Apple platform apps.

To send your first event, add the package, then call `setup` once at app startup with your project token and host from your [project settings](https://app.posthog.com/project/settings).

After `setup`, PostHog captures app lifecycle events, such as `Application Opened`, by itself. Use `capture` for your own events.

## Install

posthog-ios 4.x.x needs:

- Xcode 26 or later (`swift-tools-version` 6.2). Your app can use Swift 5 or Swift 6 language mode.
- iOS and Mac Catalyst 15.0 or later, macOS 12.0 or later, tvOS 15.0 or later, watchOS 10.0 or later, or visionOS 1.0 or later.

Add the package with Swift Package Manager. In Xcode, choose **File > Add Package Dependencies…** and enter `https://github.com/PostHog/posthog-ios.git`. In a `Package.swift`, add:

```swift
dependencies: [
    .package(url: "https://github.com/PostHog/posthog-ios.git", from: "4.0.0")
]
```

In Xcode, add the `PostHog` library to your app target. In a `Package.swift` target, add `.product(name: "PostHog", package: "posthog-ios")` to `dependencies`. `import PostHog` is the same as in 3.x.x.

Before you upgrade from 3.x.x, read the [migration guide](https://posthog.com/docs/libraries/ios/migration). It covers the toolchain, proxy, and API changes.

### Using CocoaPods?

4.x.x isn't published to CocoaPods, and the repository has no `PostHog.podspec`. If you install with CocoaPods, stay on 3.x.x or move to Swift Package Manager. 3.x.x versions remain installable from CocoaPods, but [CocoaPods trunk becomes read-only on December 2, 2026](https://blog.cocoapods.org/CocoaPods-Specs-Repo/).

To move to Swift Package Manager:

1. Remove `pod 'PostHog'` from your `Podfile` and run `pod install`.
2. Add the package, as shown above.
3. Add the `PostHog` library to your app target.
4. If a Run Script phase uploads dSYMs with `${PODS_ROOT}/PostHog/build-tools/upload-symbols.sh`, change the path to `${BUILD_DIR%/Build/*}/SourcePackages/checkouts/posthog-ios/build-tools/upload-symbols.sh`. Without this change, symbol upload fails and crash reports lose symbolication.

React Native, Flutter, and Kotlin Multiplatform apps get this SDK through their PostHog wrapper package. Upgrade through that package instead of adding `posthog-ios` directly.

## Initialize

Call `setup` once, as early as possible in app startup.

```swift
import PostHog

let config = PostHogConfig(projectToken: "<ph_project_token>", host: "<ph_client_api_host>")
PostHogSDK.shared.setup(config)
```

## Capture an event

```swift
PostHogSDK.shared.capture("button_clicked", properties: ["plan": "pro"])
```

Call `identify` to link events to a user:

```swift
PostHogSDK.shared.identify("user_123", userProperties: ["email": "max@example.com"])
```

## Shut down

Events are sent in batches. Call `flush()` to send queued events now, or `close()` to shut the SDK down.

```swift
PostHogSDK.shared.close()
```

## Custom keyboard extensions

A custom keyboard can only send events when it has [Open Access](https://developer.apple.com/documentation/uikit/configuring-open-access-for-a-custom-keyboard). Network requests and writes to the shared App Group container both need it. Users grant it in **Settings > General > Keyboard > Keyboards > [Your Keyboard] > Allow Full Access**.

## IDFA

The SDK doesn't collect the IDFA. It has had no references to Apple's AdSupport framework since 1.2.0, so it doesn't trip App Store static analysis.

## Older versions

This page covers 4.x.x. If your app is on 3.x.x, check which version you have installed:

- Swift Package Manager: find the `posthog-ios` entry in `Package.resolved` and read its `version`.
- CocoaPods: find `PostHog` in `Podfile.lock`.

For 3.x.x, see the [3.x.x reference](https://posthog.com/docs/libraries/ios/3.x.x). To upgrade to 4.x.x, see the [migration guide](https://posthog.com/docs/libraries/ios/migration).
