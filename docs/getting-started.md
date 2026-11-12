# Getting started

The iOS SDK runs in iOS and other Apple platform apps.

To send your first event, add the package, then call `setup` once at app startup with your project token and host from your [project settings](https://app.posthog.com/project/settings).

After `setup`, PostHog captures app lifecycle events, such as `Application Opened`, by itself. Use `capture` for your own events.

## Install

PostHog 4.x.x is published with Swift Package Manager only. In Xcode, choose **File > Add Package Dependencies…** and enter `https://github.com/PostHog/posthog-ios`, or add it to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/PostHog/posthog-ios.git", from: "4.0.0")
]
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

## Install with the wizard

Run this command in your project directory to add PostHog to your iOS project:

```bash
npx -y @posthog/wizard@latest
```

The wizard detects your framework, installs the SDK, and sets up your first events. To set it up by hand, follow the rest of this page.

## Link the library

In an Xcode project, add PostHog under **Package Dependencies** and select your app's target.

In a Swift Package Manager project, add PostHog as a dependency of the target that uses it in `Package.swift`:

```swift
  .target(
    name: "myApp",
    dependencies: [.product(name: "PostHog", package: "posthog-ios")]),
```

> **CocoaPods isn't supported.** 4.x.x isn't published to CocoaPods, and CocoaPods trunk becomes read-only on December 2, 2026. To move, remove the `PostHog` entry from your `Podfile`, run `pod install`, and add the package as shown in Install. See the [migration guide](https://posthog.com/docs/libraries/ios/migration) for the full steps.

## Set up your app

You configure the SDK through a `PostHogConfig` object. Create it and call `setup` before any screen is displayed.

In a UIKit app, call `setup` in your app delegate:

```swift
import Foundation
import PostHog
import UIKit

class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_: UIApplication, didFinishLaunchingWithOptions _: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        let POSTHOG_PROJECT_TOKEN = "<ph_project_token>"
        // usually 'https://us.i.posthog.com' or 'https://eu.i.posthog.com'
        let POSTHOG_HOST = "<ph_client_api_host>"

        let config = PostHogConfig(projectToken: POSTHOG_PROJECT_TOKEN, host: POSTHOG_HOST) // TIP: host is optional if you use https://us.i.posthog.com
        PostHogSDK.shared.setup(config)

        return true
    }
}
```

In a SwiftUI app, call `setup` in your app's initializer:

```swift
import SwiftUI
import PostHog

@main
struct YourGreatApp: App {
    
    // Add PostHog to your app's initializer.
    // If using UIApplicationDelegateAdaptor, see the UIKit tab.

    init() {
        
        let POSTHOG_PROJECT_TOKEN = "<ph_project_token>"
        // usually 'https://us.i.posthog.com' or 'https://eu.i.posthog.com'
        let POSTHOG_HOST = "<ph_client_api_host>"
        
        let config = PostHogConfig(projectToken: POSTHOG_PROJECT_TOKEN, host: POSTHOG_HOST) // TIP: host is optional if you use https://us.i.posthog.com
        PostHogSDK.shared.setup(config)
        
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
```

Every option is listed under `PostHogConfig` in the Types section of this reference.

## Capture custom events

Send a custom event with `capture`:

```swift
PostHogSDK.shared.capture("user_signed_up")
```

> **Name events as `[object] [verb]`.** `[object]` is the entity the behavior relates to, and `[verb]` is the behavior itself. For example, `project created`, `user signed up`, or `invite sent`.

To send more information with the event, add a [properties](https://posthog.com/docs/data/events#event-properties) object:

```swift
PostHogSDK.shared.capture("user_signed_up", properties: ["login_type": "email"], userProperties: ["is_free_trial": true])
```

## The autocaptured events

PostHog autocapture tracks these events for you:

- **Application Opened.** The app is opened from a closed state, or it comes to the foreground, for example from the app switcher.
- **Application Backgrounded.** The user sends the app to the background.
- **Application Installed.** The app is installed.
- **Application Updated.** The app is updated.
- **$screen.** The user navigates, if you use `UIViewController`.
- **$autocapture.** The user interacts with elements in a screen. It needs UIKit and `captureElementInteractions`.
- **$rageclick.** The user rapidly taps in the same area. It needs UIKit, on iOS or Mac Catalyst.

> **SwiftUI is partly covered.** `$autocapture` and `$rageclick` are captured from UIKit interactions. Some SwiftUI views use UIKit under the hood, for example `TextField` uses `UITextField` and `Toggle` uses `UISwitch`, so those interactions may also be autocaptured. In other SwiftUI cases, interactions might still be captured, but element metadata such as `$elements_chain` may be incomplete.

You turn autocapture on or off through the `PostHogConfig` object:

```swift
let POSTHOG_PROJECT_TOKEN = "<ph_project_token>"
// usually 'https://us.i.posthog.com' or 'https://eu.i.posthog.com'
let POSTHOG_HOST = "<ph_client_api_host>"

let config = PostHogConfig(projectToken: POSTHOG_PROJECT_TOKEN, host: POSTHOG_HOST)

// capture screen views
config.captureScreenViews = true 
// capture application lifecycle events (installed, updated, opened, backgrounded)
config.captureApplicationLifecycleEvents = true
// capture element interactions (button presses, text input changes, etc.)
config.captureElementInteractions = true // TIP: Disabled by default

PostHogSDK.shared.setup(config) 
```

## Capture screen views

With `captureScreenViews` set to `true`, PostHog tries to record every screen change by itself.

To send a screen event yourself, use the `screen` function:

```swift
PostHogSDK.shared.screen("Dashboard", properties: ["fromIcon": "bottom"])
```

> **Turn `captureScreenViews` off in SwiftUI apps.** It works with both UIKit and SwiftUI, but the SwiftUI screen names come from internal view identifiers, so they may not mean much. Use the `.postHogScreenView()` view modifier instead.

In SwiftUI, apply the `postHogScreenView` modifier to your full-screen views. PostHog sends a `$screen` event when `onAppear` runs, and infers the screen name from the view's type. You can pass a custom name and event properties:

```swift
// This will trigger a screen view event with $screen_name: "HomeViewContent"
struct HomeView: View {
    var body: some View {
        HomeViewContent()
            .postHogScreenView()
    }
}

// This will trigger a screen view event with $screen_name: "My Home View" and an additional event property from_button: "start"
struct HomeView: View {
    var body: some View {
        HomeViewContent()
            .postHogScreenView("My Home View", ["from_button": "start"])
    }
}
```

SwiftUI views range from whole screens to small components, and SwiftUI doesn't tell these levels apart. That makes automatic tracking of full-screen views harder than in UIKit.

To drop screen events you don't want, filter them in a `beforeSend` block. Amend or drop events has an example.

## Capture element interactions

Interaction autocapture records when users interact with UI elements in your app:

- **User interactions.** `touch`, `swipe`, `pan`, `pinch`, `rotation`, `long_press`, `scroll`.
- **Control types.** `value_changed`, `submit`, `toggle`, `primary_action`, `menu_action`, `change`.

Interaction autocapture is off by default. Set `captureElementInteractions` to `true` to turn it on:

```swift
let config = PostHogConfig(projectToken: "<ph_project_token>", host: "<ph_client_api_host>")
config.captureElementInteractions = true // Disabled by default
PostHogSDK.shared.setup(config)
```

A rage click is when a user taps an area several times in quick succession, for example 3 taps in 1 second. PostHog captures it as a `$rageclick` event. It's a good sign that users are frustrated, so use it to find UI you can improve.

Rage click autocapture works on iOS and Mac Catalyst, and it's on by default:

```swift
let config = PostHogConfig(projectToken: "<ph_project_token>", host: "<ph_client_api_host>")
config.rageClickConfig.enabled = true // Enabled by default
config.rageClickConfig.minimumTapCount = 3 // Optional, default is 3
config.rageClickConfig.thresholdPoints = 30 // Optional, default is 30
config.rageClickConfig.timeoutInterval = 1.0 // Optional, default is 1.0s
PostHogSDK.shared.setup(config)
```

## Label autocaptured elements

PostHog identifies autocaptured interactions by element type, like `UIButton`, `UITextField`, or `UILabel`. That makes one element hard to tell from another in your analytics. Give an element a custom label, and you can find, filter, and analyze its events.

In UIKit, set the `postHogLabel` property on a `UIView`:

```swift
let view = UIView()
view.postHogLabel = "usernameTextField"
```

In SwiftUI, use the `.postHogLabel(_:)` modifier:

```swift
var body: some View {
    ...
    TextField("username", text: $username)
        .postHogLabel("usernameTextField")
}
```

SwiftUI's `TextField` uses `UITextField` under the hood, so its interactions are autocaptured with the identifier `usernameTextField`. The captured element looks like this:

```swift
<UITextField id="usernameTextField">text value</UITextField>
```

To find a labeled element in PostHog, use the autocapture element filters:

- **Tag name.** `UITextField` in this example.
- **Text.** `text value` in this example.
- **CSS selector.** The generated `id` attribute, so `#usernameTextField` in this example.

## Hide sensitive data

To keep a UI element out of autocapture and session replay, add `ph-no-capture` as its `accessibilityLabel` or its `accessibilityIdentifier`. See [privacy controls](https://posthog.com/docs/session-replay/privacy?tab=iOS) for masking behavior and iOS examples.

## Identify users

> **Identifying users is required.** Call `PostHogSDK.shared.identify("your-user-id")` after login to link events to a known user. This connects event captures, [session replays](https://posthog.com/docs/session-replay), [LLM traces](https://posthog.com/docs/ai-engineering), and [error tracking](https://posthog.com/docs/error-tracking) to the same person, and lets backend events link back too.

Use a stable ID from your auth system when you can, not an email or a display name. Send those as person properties instead. If your app has no other stable key, a unique email works as a fallback.

Never use a shared literal like `"anonymous"` or `"user"`. It pools many people onto one person and corrupts their data. When no ID is available at all, skip `identify` and keep the anonymous distinct ID the SDK assigns.

An `identify` call takes these arguments:

- **`distinctId`.** The ID that uniquely identifies your user in your database.
- **`userProperties`.** Optional. A dictionary of [person properties](https://posthog.com/docs/product-analytics/person-properties) to set.
- **`userPropertiesSetOnce`.** Optional. Like `userProperties`, but it only sets a property the person doesn't have yet. See [the difference between the two](https://posthog.com/docs/product-analytics/person-properties#what-is-the-difference-between-set-and-set_once).

```swift
PostHogSDK.shared.identify("user_id_from_your_database",
                            userProperties: ["name": "Peter Griffin", "email": "peter@familyguy.com"],
                            userPropertiesSetOnce: ["date_of_first_log_in": "2024-03-01"])
```

Call `identify` as soon as you can, typically right after your user logs in. Events sent during the session are then associated with the user, and all earlier anonymous events are linked to them.

To check whether you've already identified a user, call `getDistinctId()`. It returns the ID PostHog generated, or the ID you passed to `identify()`.

Call `reset` on logout to reset the user's ID and anonymous ID, so the next person to use the device doesn't inherit the last one's identity. See the guide on [identifying users](https://posthog.com/docs/getting-started/identify-users) and [reset on logout](https://posthog.com/docs/product-analytics/identify#reset-on-logout).

## Assign an alias

Use `alias` to assign another distinct ID to the same user. It helps when your primary distinct ID is out of reach, for example when the ID you use on the frontend isn't available in your backend.

```swift
PostHogSDK.shared.alias("alias_id")
```

Read the docs on [alias](https://posthog.com/docs/product-analytics/identify#alias-assigning-multiple-distinct-ids-to-the-same-user) before you use this method.

## Choose person profiles

PostHog captures two types of events: [anonymous and identified](https://posthog.com/docs/data/anonymous-vs-identified-events).

- **Identified events.** PostHog creates a [person profile](https://posthog.com/docs/data/persons) for the user, so you can attribute events to specific users and attach [person properties](https://posthog.com/docs/product-analytics/person-properties). Use them for logged-in users in B2B and B2C SaaS apps, for user-segmented product analysis, and when growth and marketing teams analyze the complete conversion lifecycle.
- **Anonymous events.** They carry no individually identifiable data, and PostHog creates no person profile. Use them for marketing websites, content-focused sites, and B2C apps where users don't sign up or log in.

> **Anonymous events cost less.** They're cheaper to process, so they can be up to 4x cheaper than identified events. Capture identified events only when you need them.

The `personProfiles` option decides which type the SDK captures:

- **`.identifiedOnly`.** The default, and recommended. Events are anonymous until a person profile exists for the user.
- **`.always`.** Every event is identified.
- **`.never`.** Every event is anonymous.

```swift
let config = PostHogConfig(
    projectToken: POSTHOG_PROJECT_TOKEN,
    host: POSTHOG_HOST
)
config.personProfiles = .identifiedOnly
PostHogSDK.shared.setup(config)
```

With `.identifiedOnly`, call one of these functions to create a person profile for the user:

- [`identify()`](https://posthog.com/docs/product-analytics/identify)
- [`alias()`](https://posthog.com/docs/product-analytics/identify#alias-assigning-multiple-distinct-ids-to-the-same-user)
- [`group()`](https://posthog.com/docs/product-analytics/group-analytics)

Once the profile exists, all later events for this user are identified.

## Set person properties

To set [person properties](https://posthog.com/docs/product-analytics/person-properties) with an event, pass `userProperties` or `userPropertiesSetOnce` to `capture`. The SDK sends them as `$set` and `$set_once` on the event.

```swift
PostHogSDK.shared.capture("signed_up", properties: ["plan": "Pro++"], userProperties: ["user_property_name": "your_value"])
```

`userPropertiesSetOnce` works like `userProperties`, except that it only sets a property the user doesn't have yet.

```swift
PostHogSDK.shared.capture("signed_up", properties: ["plan": "Pro++"], userPropertiesSetOnce: ["user_property_name": "your_value"])
```

Use `setPersonProperties` to update the current person's profile without a custom event. It sends a `$set` event to PostHog.

```swift
PostHogSDK.shared.setPersonProperties(userPropertiesToSet: ["plan": "Pro++"])

PostHogSDK.shared.setPersonProperties(
    userPropertiesToSet: ["plan": "Pro++"],
    userPropertiesToSetOnce: ["first_seen_source": "ios"]
)
```

## Use super properties

Super properties are event properties you set once. The SDK then sends them with every `capture` call, a `$screen` event included, and they persist across sessions.

Set them with `PostHogSDK.shared.register`, which takes a properties object:

```swift
PostHogSDK.shared.register(["team_id": 22])
```

Every event the user sends after this call includes `"team_id": 22`. Filter events by `team_id = 22`, and you get all of them.

Super properties are stored on events, not on the user. To store properties on the user, use `PostHogSDK.shared.identify`.

To stop sending a super property, remove it with `PostHogSDK.shared.unregister`:

```swift
PostHogSDK.shared.unregister("team_id")
```

Later events don't include it. On logout, call `PostHogSDK.shared.reset` instead, which clears all super properties and more.

## Use feature flags

PostHog's [feature flags](https://posthog.com/docs/feature-flags) let you safely deploy and roll back new features, and target specific users and groups with them.

Check a boolean flag:

```swift
if let result = PostHogSDK.shared.getFeatureFlagResult("flag-key"), result.enabled {
    // Do something differently for this user

    // Optional: fetch the payload from the same evaluation result
    let matchedFlagPayload = result.payload
}
```

Check a multivariate flag:

```swift
if let result = PostHogSDK.shared.getFeatureFlagResult("flag-key"), result.variant == "variant-key" { // replace "variant-key" with the key of your variant
    // Do something differently for this user

    // Optional: fetch the payload from the same evaluation result
    let matchedFlagPayload = result.payload
}
```

If your payload is a JSON object, decode it into a `Decodable` type:

```swift
struct FlagPayload: Decodable {
    let title: String
}

if let result = PostHogSDK.shared.getFeatureFlagResult("flag-key"),
   let payload = result.payloadAs(FlagPayload.self) {
    // Use payload.title
}
```

Inspect all loaded flags with `getAllFeatureFlags()`. It doesn't send a `$feature_flag_called` event, so it won't affect your experiment results or your flag usage analytics:

```swift
for flag in PostHogSDK.shared.getAllFeatureFlags() ?? [] {
    print(flag.key, flag.enabled, flag.variant as Any, flag.payload as Any)
}
```

Flag values are cached. If something changed for your user and you want fresh values, reload them:

```swift
PostHogSDK.shared.reloadFeatureFlags()
```

To track when someone sees or interacts with a feature, use `captureFeatureView` and `captureFeatureInteraction`:

```swift
PostHogSDK.shared.captureFeatureView(flag: "flag-key", flagVariant: "variant-key")
PostHogSDK.shared.captureFeatureInteraction(flag: "flag-key", flagVariant: "variant-key")
```

## Wait for flags

Each time a user opens the app, the SDK fetches that user's flags in the background and stores them. Flags are then available right away on most screens, except the first time a user opens the app.

Use the `onFeatureFlags` callback to learn when flags are loaded or change:

```swift
let subscription = PostHogSDK.shared.onFeatureFlags { loaded in
    if loaded.errorsLoading {
        // Loading failed, so the flags are the last known values, which can be empty.
        // Fall back to your default experience if you need fresh values.
        return
    }
    if PostHogSDK.shared.isFeatureEnabled("flag-key") {
        // do something
    }
}

// Later, to stop receiving updates
subscription.unsubscribe()
```

When `errorsLoading` is `true`, for example because the device is offline, the flags hold the last known values. On a fresh install with no [bootstrap values](https://posthog.com/docs/feature-flags/bootstrapping), they're empty. `isFeatureEnabled` then returns `false` because the flag is unknown, not because PostHog evaluated it as disabled.

You can also use the completion block of `reloadFeatureFlags(_:)` to run logic right after a reload:

```swift
// Reload feature flags and check if a specific feature is enabled
PostHogSDK.shared.reloadFeatureFlags { _ in
    if PostHogSDK.shared.isFeatureEnabled("flag-key") {
        // do something
    }
}
```

## Bootstrap feature flags

The SDK fetches flags after it starts, so flags aren't always available right away. That's a problem when startup logic depends on a flag, like which screen to show first.

Bootstrapping fixes this. You initialize PostHog with precomputed values, and the SDK uses them until it fetches flags from PostHog.

Set `config.bootstrap` before you call `setup()`:

```swift
let config = PostHogConfig(projectToken: "<ph_project_token>", host: "<ph_client_api_host>")
config.bootstrap = PostHogBootstrapConfig(
    distinctId: "distinct_id_of_your_user",
    isIdentifiedId: true,
    featureFlags: [
        "flag-1": true,
        "variant-flag": "control"
    ],
    featureFlagPayloads: nil
)
PostHogSDK.shared.setup(config)
```

Bootstrapped identity applies during setup. On a fresh install, events captured during initialization, like `Application Installed`, carry your distinct ID instead of the SDK-generated UUID.

- **Anonymous bootstrap.** With `isIdentifiedId: false`, the default, it seeds the anonymous ID only when none is persisted yet. Once an anonymous ID exists on disk, or the person is identified, the SDK ignores it.
- **Identified bootstrap.** With `isIdentifiedId: true`, it's for a signed-in identity your app already has, for example from a backend session token. On a fresh install, it seeds the distinct ID, marks the person identified, and generates a separate device ID.
- **Identified bootstrap on a returning install.** A matching anonymous ID is marked identified without an `$identify` event. A different anonymous ID is merged with `identify()` when person profiles are enabled, which sends `$identify` unless capturing is opted out. A different, already identified person is left untouched.

Bootstrapped flags are served until the first `/flags` response, then replaced. A complete `/flags` response takes over entirely, so keys that were only bootstrapped don't persist past it.

- **Only enabled flags are seeded.** That's a `true` boolean or a non-empty variant string. A `false` or empty value is dropped.
- **Payloads are separate.** Seed them with the `featureFlagPayloads` option.
- **Values must be JSON-serializable.** Flag values and payloads that aren't are dropped.
- **`reset()` clears them.** Bootstrapped flags don't survive a reset.

The `onFeatureFlags` callback fires as soon as bootstrapped flags are applied, so startup logic can read them right away. The SDK doesn't support the `sessionID` bootstrap option. When `personProfiles` is `.never`, the SDK keeps a different anonymous identity instead of merging it into an identified bootstrap.

See the [SDK bootstrapping guide](https://posthog.com/docs/libraries/bootstrapping) for the overview across SDKs.

## Send AI events

To send [AI observability](https://posthog.com/docs/ai-observability) events you build yourself, such as `$ai_generation`, `$ai_span`, or `$ai_embedding`, call `captureAi` instead of `capture`. It takes the same arguments and runs the same `beforeSend` hooks. It then sends the event to PostHog's [AI endpoint](https://posthog.com/docs/ai-observability/large-events), which accepts much larger events than `capture`.

```swift
let uuid = PostHogSDK.shared.captureAi("$ai_generation", properties: [
    "$ai_trace_id": traceId,
    "$ai_model": "gpt-5",
    "$ai_provider": "openai",
    "$ai_input_tokens": 120,
    "$ai_output_tokens": 45,
])
```

AI events have their own queue on disk, so large events don't push your other events out. `flush()` and `close()` send both queues.

The `captureAi` entry in this reference lists the size limits and what's dropped. The `captureAiCompression`, `captureAiMaxQueueSize`, `captureAiTimeout`, and `captureAiMaxEventBytes` entries under `PostHogConfig` list the settings.

## The event queue

The SDK puts events in a queue so calls are fast and don't block. It sends them in batches, in the background.

The SDK keeps capturing events when the device is offline. It stores the queue in the device's file storage and flushes it when the device is back online.

- **Size.** The queue holds at most `maxQueueSize` events.
- **Overflow.** When the queue is full, the oldest event is deleted first.
- **Flush.** The queue is flushed only when the device is online.

`flushAt` sets how many events queue before a flush. The default is `20`. A value of `1` sends events immediately and uses more battery.

`flushIntervalSeconds` sets the flush interval. The default is `30`. After it passes, queued events are sent however many there are.

```swift
configuration.flushAt = 1
configuration.flushIntervalSeconds = 30
```

To send queued events now instead of waiting for the next batch, flush the queue yourself:

```swift
PostHogSDK.shared.capture("logged_out")
PostHogSDK.shared.flush()
```

Flushing is best-effort and asynchronous. It starts sending queued events in the background but doesn't wait for the request to finish, so it isn't a delivery guarantee.

## Amend or drop events

Pass a `BeforeSendBlock` to `setBeforeSend` to amend, drop, or sample events before they're sent to PostHog. It gives you one place to edit or redact information.

> **Leave PostHog's own events alone.** Amending and sampling events is advanced and needs care. Core PostHog features may need 100% of unmodified events to work. Modify or sample only your own custom events if you can.

Redact URLs in event properties:

```swift
let config = PostHogConfig(projectToken: "<ph_project_token>", host: "<ph_client_api_host>")

config.setBeforeSend { event in
    // Redact URLs
    if let url = event.properties["url"] as? String {
        event.properties["url"] = url.map { _ in "*" }.joined()
    }
    return event
}
```

Redact sensitive information from event properties:

```swift
let config = PostHogConfig(projectToken: "<ph_project_token>", host: "<ph_client_api_host>")

config.setBeforeSend { event in
    // Redact sensitive information
    if let email = event.properties["email"] as? String {
        event.properties["email"] = email.map { _ in "*" }.joined()
    }
    
    return event
}
```

Drop events by event name:

```swift
let config = PostHogConfig(projectToken: "<ph_project_token>", host: "<ph_client_api_host>")

config.setBeforeSend { event in
    // Drop all events named "Stale Event"
    if event.event == "Stale Event" {
        return nil
    }
    return event
}
```

To stop specific screens from being autocaptured, return `nil` for any `$screen` event whose `$screen_name` matches a screen you don't want. It's dropped before it's sent.

```swift
let config = PostHogConfig(projectToken: "<ph_project_token>", host: "<ph_client_api_host>")

let ignoredScreens: Set<String> = ["Splash", "Debug"]

config.setBeforeSend { event in
    if event.event == "$screen",
       let screenName = event.properties["$screen_name"] as? String,
       ignoredScreens.contains(screenName) {
        return nil
    }
    return event
}
```

It's a function, so you can filter however you like:

- **Ignorelist.** Drop the screens you name.
- **Allowlist.** Invert the check to capture only the screens you name.
- **Custom rule.** Match a name prefix, a regex, or the event's properties.

Sampling sends only a percentage of events to PostHog. It controls your costs without turning SDK features off. Sample events by event name:

```swift
let config = PostHogConfig(projectToken: "<ph_project_token>", host: "<ph_client_api_host>")

config.setBeforeSend { event in
    // Sample 10% of Sampled Event events
    if event.event == "Sampled Event" {
        if Double.random(in: 0...1) < 0.1 {
            event.properties["$sample_type"] = ["sampleByEvent"]
            event.properties["$sample_threshold"] = 0.1
            event.properties["$sampled_events"] = ["Sampled Event"]
            return event
        }
        return nil
    }
    return event
}
```

To chain blocks, pass several `BeforeSendBlock` functions. They're called one after the other:

```swift
let config = PostHogConfig(projectToken: "<ph_project_token>", host: "<ph_client_api_host>")

config.setBeforeSend(
    // First block: Drop all events named "Stale Event"
    { event in
        if event.event == "Stale Event" {
            return nil
        }
        return event
    },
    // Second block: Redact sensitive information
    { event in
        if let email = event.properties["email"] as? String {
            event.properties["email"] = email.map { _ in "*" }.joined()
        }
        return event
    }
)
```

> **Order matters.** The first block runs first, and the event it returns is passed to the second block, and so on. If a block drops the event, the blocks after it don't run.

## Send tracing headers

Use `tracingHeaders` to connect iOS network requests to backend events, errors, and LLM traces captured by a server-side PostHog SDK:

```swift
let configuration = PostHogConfig(projectToken: "<ph_project_token>", host: "<ph_client_api_host>")
configuration.tracingHeaders = ["api.example.com"]
PostHogSDK.shared.setup(configuration)
```

Hostnames are matched exactly. Don't include protocols, paths, ports, or wildcard subdomains. Matching `URLSession` requests include `X-POSTHOG-DISTINCT-ID` and `X-POSTHOG-SESSION-ID` when those values are available.

Tracing headers need method swizzling, so `configuration.enableSwizzling` must stay `true`.

## Share data with extensions

By default, each iOS app target stores its data in its own sandboxed directory. A user who uses your main app and then a widget or an extension looks like two different anonymous users to PostHog. That leads to:

- Inflated user counts in your analytics
- Fragmented user journeys
- Feature adoption that's hard to track across your app and its extensions

App Groups fix this. Your main app and its extensions, such as widgets, app clips, share extensions, and custom keyboards, share analytics data, so users keep the same identity everywhere.

1. Set up an [App Group](https://developer.apple.com/documentation/xcode/configuring-app-groups) in Xcode for your main app and extension targets.
2. Use the same App Group identifier in all targets:

```swift
let config = PostHogConfig(projectToken: "<ph_project_token>", host: "<ph_client_api_host>")
config.appGroupIdentifier = "group.com.yourcompany.yourapp"
PostHogSDK.shared.setup(config)
```

> **Custom keyboards need Open Access.** Custom keyboard extensions have stricter security rules than other extension types. The keyboard must have [Open Access permission](https://developer.apple.com/documentation/uikit/configuring-open-access-for-a-custom-keyboard) for network requests and write access to shared containers. Users grant it in **Settings > General > Keyboard > Keyboards > [Your Keyboard] > Allow Full Access**.

## The swizzled features

Method swizzling lets the SDK intercept and modify method calls at runtime. The SDK uses it for these features:

| Feature | Config option |
| --- | --- |
| Screen view tracking | `config.captureScreenViews` |
| Element interactions | `config.captureElementInteractions` |
| Rage clicks | `config.rageClickConfig.enabled` |
| Session replay | `config.sessionReplay` |
| Surveys | `config.surveys` |
| Advanced metrics tracking | None |

Swizzling is on by default. To turn one feature off, set its config option to `false`. Advanced metrics tracking detects user activity and idleness, which gives a more precise session ID calculation and rotation.

To opt out of all swizzling, set `enableSwizzling` to `false`. The SDK then turns off every feature in the table.

```swift
let config = PostHogConfig(projectToken: "<ph_project_token>", host: "<ph_client_api_host>")
config.enableSwizzling = false
PostHogSDK.shared.setup(config)
```

> **Swizzling wins over the feature options.** With swizzling off, features that depend on it don't work, even if you turn them on in the config. For example, with `config.sessionReplay = true` and `config.enableSwizzling = false`, session replay isn't enabled.

Swizzling matters most for accurate [session metrics](https://posthog.com/tutorials/session-metrics). With swizzling on, the SDK detects user activity and idle time, which gives a better session rotation. With swizzling off, it only uses the app opened and backgrounded events, which can lead to a worse session calculation.

## Turn on debug

If you don't see the events, flag evaluations, or surveys you expect, turn on debug mode. The SDK then logs what it's doing in detail.

Set the `debug` option to `true` in `PostHogConfig`. A common pattern is to do this only in development builds.

```swift
let config = PostHogConfig(projectToken: "<ph_project_token>", host: "<ph_client_api_host>")
config.debug = true
PostHogSDK.shared.setup(config)
```

You can also toggle debug mode at runtime with `PostHogSDK.shared.debug()`:

```swift
// Enable debug mode
PostHogSDK.shared.debug(true)

// Disable debug mode
PostHogSDK.shared.debug(false)
```

## The product guides

These features have their own setup guides:

- **Group analytics.** It associates the events of a person's session with a group, like a team or an organization. See [Group analytics](https://posthog.com/docs/product-analytics/group-analytics) for iOS examples. It's a paid feature, so check the [pricing page](https://posthog.com/pricing).
- **Opt out.** You can opt users out of data capture by default, or one person at a time. See [Complete opt-out](https://posthog.com/docs/product-analytics/privacy#complete-opt-out) for iOS examples.
- **Experiments.** [Experiments](https://posthog.com/docs/experiments/start-here) use feature flags, so the code is close to the feature flag code. See [adding experiment code](https://posthog.com/docs/experiments/adding-experiment-code) for iOS examples. You can also [run experiments without feature flags](https://posthog.com/docs/experiments/running-experiments-without-feature-flags).
- **Session replay.** Install the SDK, enable "Record user sessions" in [your project settings](https://us.posthog.com/settings/project-replay), and enable the `sessionReplay` option. See [session replay](https://posthog.com/docs/session-replay/mobile). It's only available on iOS. For macOS support, follow [this GitHub issue](https://github.com/PostHog/posthog-ios/issues/200).
- **Surveys.** [Surveys](https://posthog.com/docs/surveys) with [popover presentation](https://posthog.com/docs/surveys/creating-surveys#presentation) are shown by themselves to users who match your [display conditions](https://posthog.com/docs/surveys/creating-surveys#display-conditions).
- **Error tracking.** See the [error tracking docs](https://posthog.com/docs/error-tracking).
- **Logs.** See [Logs installation](https://posthog.com/docs/logs/installation/ios).
- **Push notifications.** The SDK can register a device for [Workflows](https://posthog.com/docs/workflows) push notifications and capture when a user opens one. See [Push notifications](https://posthog.com/docs/workflows/push-notifications) for automatic and manual registration, capturing opens, and identity verification.

## The IDFA

The SDK has no references to Apple's AdSupport framework, so it doesn't collect the identifier for advertisers (IDFA). Any reference to AdSupport, even in strings, [trips](https://github.com/PostHog/posthog-ios/issues/6) the App Store's static analysis for apps that track users.
