# Getting started

The iOS SDK runs in iOS and other Apple platform apps.

To send your first event, add the package, then call `setup` once at app startup with your project token and host from your [project settings](https://app.posthog.com/project/settings).

After `setup`, PostHog captures app lifecycle events, such as `Application Opened`, by itself. Use `capture` for your own events.

## Install

Add the package with Swift Package Manager, `https://github.com/PostHog/posthog-ios.git`. 4.x.x isn't published to CocoaPods.

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

## Sample events

To send only a share of an event, drop the rest in `setBeforeSend`. Set the sampling properties on the events you keep.

```swift
config.setBeforeSend { event in
    guard event.event == "Sampled Event" else { return event }
    guard Double.random(in: 0...1) < 0.1 else { return nil }
    event.properties["$sample_type"] = ["sampleByEvent"]
    event.properties["$sample_threshold"] = 0.1
    event.properties["$sampled_events"] = ["Sampled Event"]
    return event
}
```

## Surveys and method swizzling

Surveys need method swizzling. They don't show when `enableSwizzling` is `false`, even if `surveys` is `true`.

## Custom keyboard extensions

A custom keyboard can only send events when it has [Open Access](https://developer.apple.com/documentation/uikit/configuring-open-access-for-a-custom-keyboard). Network requests and writes to the shared App Group container both need it. Users grant it in **Settings > General > Keyboard > Keyboards > [Your Keyboard] > Allow Full Access**.

## IDFA

The SDK doesn't collect the IDFA. It has had no references to Apple's AdSupport framework since 1.2.0, so it doesn't trip App Store static analysis.
