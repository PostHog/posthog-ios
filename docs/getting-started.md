# Getting started

## Install

Add the package with Swift Package Manager, `https://github.com/PostHog/posthog-ios.git`, or with CocoaPods:

```ruby
pod "PostHog"
```

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
