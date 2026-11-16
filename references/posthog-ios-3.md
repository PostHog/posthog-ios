---
title: "PostHog iOS SDK 3.x"
sidebar: Docs
showTitle: true
contentMaxWidthClass: max-w-full
platformLogo: ios
tableOfContents:
  - value: "Getting started"
    url: getting-started
    depth: 0
  - value: "Setup"
    url: setup
    depth: 0
  - value: "Capture"
    url: capture
    depth: 0
  - value: "Identify"
    url: identify
    depth: 0
  - value: "Logs"
    url: logs
    depth: 0
  - value: "Alias"
    url: alias
    depth: 0
  - value: "Capture exception"
    url: capture-exception
    depth: 0
  - value: "Debug"
    url: debug
    depth: 0
  - value: "Exception steps"
    url: exception-steps
    depth: 0
  - value: "Flush"
    url: flush
    depth: 0
  - value: "Get anonymous ID"
    url: get-anonymous-id
    depth: 0
  - value: "Get distinct ID"
    url: get-distinct-id
    depth: 0
  - value: "Get feature flag"
    url: get-feature-flag
    depth: 0
  - value: "Get feature flag payload"
    url: get-feature-flag-payload
    depth: 0
  - value: "Get feature flag result"
    url: get-feature-flag-result
    depth: 0
  - value: "Get feature flags"
    url: get-feature-flags
    depth: 0
  - value: "Get session ID"
    url: get-session-id
    depth: 0
  - value: "Group"
    url: group
    depth: 0
  - value: "Is feature enabled"
    url: is-feature-enabled
    depth: 0
  - value: "Is opt out"
    url: is-opt-out
    depth: 0
  - value: "Is session replay active"
    url: is-session-replay-active
    depth: 0
  - value: "On feature flags"
    url: on-feature-flags
    depth: 0
  - value: "Opt in"
    url: opt-in
    depth: 0
  - value: "Register"
    url: register
    depth: 0
  - value: "Reload feature flags"
    url: reload-feature-flags
    depth: 0
  - value: "Reset"
    url: reset
    depth: 0
  - value: "Reset group properties for flags"
    url: reset-group-properties-for-flags
    depth: 0
  - value: "Reset person properties for flags"
    url: reset-person-properties-for-flags
    depth: 0
  - value: "Screen"
    url: screen
    depth: 0
  - value: "Set group properties for flags"
    url: set-group-properties-for-flags
    depth: 0
  - value: "Set person properties"
    url: set-person-properties
    depth: 0
  - value: "Set person properties for flags"
    url: set-person-properties-for-flags
    depth: 0
  - value: "Shutdown"
    url: shutdown
    depth: 0
  - value: "Start session recording"
    url: start-session-recording
    depth: 0
  - value: "Stop session recording"
    url: stop-session-recording
    depth: 0
  - value: "Unregister"
    url: unregister
    depth: 0
  - value: "Autocapture"
    url: autocapture
    depth: 0
  - value: "Device ID generator"
    url: device-id-generator
    depth: 0
  - value: "Session manager"
    url: session-manager
    depth: 0
  - value: "SDK utils"
    url: sdk-utils
    depth: 0
  - value: "Types"
    url: types
    depth: 0
---

## Getting started


The iOS SDK runs in iOS and other Apple platform apps.

To send your first event, add the package, then call `setup` once at app startup with your project token and host from your [project settings](https://app.posthog.com/project/settings).

After `setup`, PostHog captures app lifecycle events, such as `Application Opened`, by itself. Use `capture` for your own events.

### Install

Add the package with Swift Package Manager, `https://github.com/PostHog/posthog-ios.git`, or with CocoaPods:

```ruby
pod "PostHog"
```

### Initialize

Call `setup` once, as early as possible in app startup.

```swift
import PostHog

let config = PostHogConfig(projectToken: "<ph_project_token>", host: "<ph_client_api_host>")
PostHogSDK.shared.setup(config)
```

### Capture an event

```swift
PostHogSDK.shared.capture("button_clicked", properties: ["plan": "pro"])
```

Call `identify` to link events to a user:

```swift
PostHogSDK.shared.identify("user_123", userProperties: ["email": "max@example.com"])
```

### Shut down

Events are sent in batches. Call `flush()` to send queued events now, or `close()` to shut the SDK down.

```swift
PostHogSDK.shared.close()
```

## Setup

### `PostHogSDK.setup(_:)`

```swift
@objc func setup(_ config: PostHogConfig)
```

Initializes this SDK instance with the provided configuration.

#### Parameters

- `config`: The configuration to install.

#### Discussion

Call this once, as early as possible in app startup. Calls made before setup completes are ignored. Calling setup again on the same instance logs a warning and has no effect.

### `PostHogSDK.with(_:)`

```swift
@objc static func with(_ config: PostHogConfig) -> PostHogSDK
```

Creates and sets up an additional SDK instance.

#### Parameters

- `config`: Configuration for the new instance.

#### Return Value

A configured `PostHogSDK` instance.

## Capture

### `PostHogSDK.capture(_:)`

```swift
@objc func capture(_ event: String)
```

Captures a custom event for the current user.

#### Parameters

- `event`: Event name to capture.

### `PostHogSDK.capture(_:distinctId:properties:userProperties:userPropertiesSetOnce:groups:)`

```swift
@objc(captureWithEvent:distinctId:properties:userProperties:userPropertiesSetOnce:groups:) func capture(_ event: String, distinctId: String? = nil, properties: [String : Any]? = nil, userProperties: [String : Any]? = nil, userPropertiesSetOnce: [String : Any]? = nil, groups: [String : String]? = nil)
```

Captures a custom event for an explicit distinct ID.

#### Parameters

- `event`: Event name to capture.
- `distinctId`: Optional distinct ID override. Defaults to the current SDK distinct ID.
- `properties`: Event properties attached only to this event.
- `userProperties`: Person properties to set. Existing values are overwritten.
- `userPropertiesSetOnce`: Person properties to set only if they do not already exist.
- `groups`: Group type/key pairs to attach to this event.

### `PostHogSDK.capture(_:distinctId:properties:userProperties:userPropertiesSetOnce:groups:timestamp:)`

```swift
@objc(captureWithEvent:distinctId:properties:userProperties:userPropertiesSetOnce:groups:timestamp:) func capture(_ event: String, distinctId: String? = nil, properties: [String : Any]? = nil, userProperties: [String : Any]? = nil, userPropertiesSetOnce: [String : Any]? = nil, groups: [String : String]? = nil, timestamp: Date? = nil)
```

Captures a custom event for an explicit distinct ID and timestamp.

#### Parameters

- `event`: Event name to capture.
- `distinctId`: Optional distinct ID override. Defaults to the current SDK distinct ID.
- `properties`: Event properties attached only to this event.
- `userProperties`: Person properties to set. Existing values are overwritten.
- `userPropertiesSetOnce`: Person properties to set only if they do not already exist.
- `groups`: Group type/key pairs to attach to this event.
- `timestamp`: Optional event timestamp. Defaults to the current time. The absolute instant is serialized in UTC, regardless of the calendar or time zone used to create it.

### `PostHogSDK.capture(_:properties:)`

```swift
@objc(captureWithEvent:properties:) func capture(_ event: String, properties: [String : Any]? = nil)
```

Captures a custom event with event properties.

#### Parameters

- `event`: Event name to capture.
- `properties`: Event properties attached only to this event.

### `PostHogSDK.capture(_:properties:userProperties:)`

```swift
@objc(captureWithEvent:properties:userProperties:) func capture(_ event: String, properties: [String : Any]? = nil, userProperties: [String : Any]? = nil)
```

Captures a custom event and updates person properties.

#### Parameters

- `event`: Event name to capture.
- `properties`: Event properties attached only to this event.
- `userProperties`: Person properties to set. Existing values are overwritten.

### `PostHogSDK.capture(_:properties:userProperties:userPropertiesSetOnce:)`

```swift
@objc(captureWithEvent:properties:userProperties:userPropertiesSetOnce:) func capture(_ event: String, properties: [String : Any]? = nil, userProperties: [String : Any]? = nil, userPropertiesSetOnce: [String : Any]? = nil)
```

Captures a custom event and updates person properties.

#### Parameters

- `event`: Event name to capture.
- `properties`: Event properties attached only to this event.
- `userProperties`: Person properties to set. Existing values are overwritten.
- `userPropertiesSetOnce`: Person properties to set only if they do not already exist.

### `PostHogSDK.capture(_:properties:userProperties:userPropertiesSetOnce:groups:)`

```swift
@objc(captureWithEvent:properties:userProperties:userPropertiesSetOnce:groups:) func capture(_ event: String, properties: [String : Any]? = nil, userProperties: [String : Any]? = nil, userPropertiesSetOnce: [String : Any]? = nil, groups: [String : String]? = nil)
```

Captures a custom event with group context.

#### Parameters

- `event`: Event name to capture.
- `properties`: Event properties attached only to this event.
- `userProperties`: Person properties to set. Existing values are overwritten.
- `userPropertiesSetOnce`: Person properties to set only if they do not already exist.
- `groups`: Group type/key pairs to attach to this event.

## Identify

### `PostHogSDK.identify(_:)`

```swift
@objc func identify(_ distinctId: String)
```

Identifies the current user with a stable distinct ID.

#### Parameters

- `distinctId`: Stable user identifier from your application.

#### Discussion

By default, the first successful identify call links prior anonymous events to the provided ID. If `PostHogConfig.reuseAnonymousId` is `true`, prior anonymous events are not linked. Empty IDs and configurations with `personProfiles == .never` are ignored. While opted out, the distinct ID and feature flags still update, but no event is captured.

### `PostHogSDK.identify(_:userProperties:)`

```swift
@objc(identifyWithDistinctId:userProperties:) func identify(_ distinctId: String, userProperties: [String : Any]? = nil)
```

Identifies the current user and sets person properties.

#### Parameters

- `distinctId`: Stable user identifier from your application.
- `userProperties`: Properties to set on the person profile. Existing values are overwritten.

### `PostHogSDK.identify(_:userProperties:userPropertiesSetOnce:)`

```swift
@objc(identifyWithDistinctId:userProperties:userPropertiesSetOnce:) func identify(_ distinctId: String, userProperties: [String : Any]? = nil, userPropertiesSetOnce: [String : Any]? = nil)
```

Identifies the current user and sets person properties.

#### Parameters

- `distinctId`: Stable user identifier from your application.
- `userProperties`: Properties to set on the person profile. Existing values are overwritten.
- `userPropertiesSetOnce`: Properties to set only if they do not already exist.

## Logs

### `PostHogSDK.logger`

```swift
@objc var logger: PostHogLogger? { get }
```

Logger facade exposing `trace/debug/info/warn/error/fatal(_:attributes:)`. `nil` before `setup(_:)` is called.

### `PostHogSDK.captureLog(_:)`

```swift
@objc(captureLogWithBody:) func captureLog(_ body: String)
```

Capture a structured log record at `.info` severity.

#### Parameters

- `body`: The log message. Required and non-empty.

#### Discussion

Log records ship to PostHog via a separate `/i/v1/logs` endpoint and are persisted to disk so they survive app restarts. The call performs a **synchronous disk write on the calling thread**, then the network send happens asynchronously — same contract as `capture(_:)` for events. Avoid calling from the main thread on hot paths. Records run through `config.logs.beforeSend` and the per-window rate cap before enqueueing — both can drop a record silently. An empty or whitespace-only `body` is always dropped.

### `PostHogSDK.captureLog(_:level:)`

```swift
@objc(captureLogWithBody:level:) func captureLog(_ body: String, level: PostHogLogSeverity)
```

Capture a structured log record at the given severity.

#### Parameters

- `body`: The log message. Required and non-empty.
- `level`: Severity. Use `.trace`/`.debug` for diagnostic detail, `.info` for regular events, `.warn`/`.error`/`.fatal` for problems.

### `PostHogSDK.captureLog(_:level:attributes:)`

```swift
@objc(captureLogWithBody:level:attributes:) func captureLog(_ body: String, level: PostHogLogSeverity, attributes: [String : Any]?)
```

Capture a structured log record with caller-supplied attributes.

#### Parameters

- `body`: The log message. Required and non-empty.
- `level`: Severity.
- `attributes`: Per-record attributes (request id, duration, etc.). Values must be JSON-serializable; non-serializable entries are dropped.

### `PostHogSDK.captureLog(_:level:attributes:traceId:spanId:traceFlags:)`

```swift
func captureLog(_ body: String, level: PostHogLogSeverity = .info, attributes: [String : Any]? = nil, traceId: String? = nil, spanId: String? = nil, traceFlags: Int? = nil)
```

Swift-native variant of `captureLog` with default values for every argument except `body`. Most call sites can write `captureLog("...")` or `captureLog("...", level: .warn, attributes: [...])`.

#### Parameters

- `body`: The log message. Required and non-empty.
- `level`: Severity. Defaults to `.info`.
- `attributes`: Per-record attributes. Values must be JSON-serializable.
- `traceId`: Optional 32-character lowercase hex W3C trace ID.
- `spanId`: Optional 16-character lowercase hex W3C span ID.
- `traceFlags`: Optional W3C trace flags bitfield.

```swift
@objc(captureLogWithBody:level:attributes:traceId:spanId:traceFlags:) func captureLog(_ body: String, level: PostHogLogSeverity, attributes: [String : Any]?, traceId: String?, spanId: String?, traceFlags: NSNumber?)
```

Capture a structured log record with W3C trace context. Intended for callers correlating logs with distributed traces; most apps should use the simpler overload.

#### Parameters

- `body`: The log message. Required and non-empty.
- `level`: Severity.
- `attributes`: Per-record attributes. Same rules as the simpler overload.
- `traceId`: 32-character lowercase hex W3C trace id.
- `spanId`: 16-character lowercase hex W3C span id.
- `traceFlags`: W3C trace flags bitfield (bit 0 is the `sampled` flag). `nil` omits the field on the wire; `0` emits an explicit zero.

## Alias

### `PostHogSDK.alias(_:)`

```swift
@objc func alias(_ alias: String)
```

Assigns an additional distinct ID to the current user.

#### Parameters

- `alias`: The additional distinct ID to associate with the current user.

#### Discussion

Use alias when a user should be connected to another identifier that was previously used to track them. This sends a `$create_alias` event.

## Capture exception

### `PostHogSDK.captureException(_:)`

```swift
@objc(captureExceptionWithNSException:) func captureException(_ exception: NSException)
```

Capture an NSException without additional properties

#### Parameters

- `exception`: The NSException to capture

#### Discussion

Convenience overload for Objective-C callers so `properties:` doesn’t need to be passed as `nil`.

```swift
@objc(captureExceptionWithError:) func captureException(_ error: Error)
```

Capture a Swift Error or NSError without additional properties

#### Parameters

- `error`: The error to capture (can be any Error or NSError)

#### Discussion

Convenience overload for Objective-C callers so `properties:` doesn’t need to be passed as `nil`.

### `PostHogSDK.captureException(_:properties:)`

```swift
@objc(captureExceptionWithNSException:properties:) func captureException(_ exception: NSException, properties: [String : Any]? = nil)
```

Capture an NSException

#### Parameters

- `exception`: The NSException to capture
- `properties`: Optional additional properties to attach to the event

#### Discussion

Captures an NSException as a `$exception` event with full stack trace. This is useful for Objective-C code that uses NSException.

Example:

```objc
@try {
    [self riskyOperation];
} @catch (NSException *exception) {
    [[PostHogSDK shared] captureExceptionWithNSException:exception properties:nil];
}
```

```swift
@objc(captureExceptionWithError:properties:) func captureException(_ error: Error, properties: [String : Any]? = nil)
```

Capture a Swift Error or NSError

#### Parameters

- `error`: The error to capture (can be any Error or NSError)
- `properties`: Optional additional properties to attach to the event

#### Discussion

Captures an error as a `$exception` event with full stack trace and error chain information. The error will be marked as handled by default.

Example:

```swift
do {
    try FileManager.default.removeItem(at: badFileUrl)
} catch {
    PostHogSDK.shared.captureException(error)
}
```

## Debug

### `PostHogSDK.debug(_:)`

```swift
@objc func debug(_ enabled: Bool = true)
```

Enables or disables SDK debug logging at runtime.

#### Parameters

- `enabled`: Pass `true` to enable verbose logs or `false` to disable them.

## Exception steps

### `PostHogSDK.addExceptionStep(_:)`

```swift
@objc(addExceptionStep:) func addExceptionStep(_ message: String)
```

Record an exception step without additional properties.

#### Parameters

- `message`: A short, non-empty description of what happened.

#### Discussion

Convenience overload for Objective-C callers so `properties:` doesn’t need to be passed as `nil`.

### `PostHogSDK.addExceptionStep(_:properties:)`

```swift
@objc(addExceptionStep:properties:) func addExceptionStep(_ message: String, properties: [String : Any]? = nil)
```

Record an exception step (breadcrumb-style context record).

#### Parameters

- `message`: A short, non-empty description of what happened. Empty messages are ignored.
- `properties`: Optional additional context to attach to the step.

#### Discussion

Steps accumulate in a session-scoped buffer and are attached to **every** captured `$exception` as `$exception_steps`, giving the error tracking UI a timeline of recent activity before each error. The buffer is not cleared by a capture — it rotates only by byte-budget eviction and is cleared on a clean launch or `close()`. On a fatal crash the buffered steps are persisted with the crash context and attached to the crash `$exception` reported on the next launch.

Reserved keys `$message` and `$timestamp` are stripped from `properties` — the SDK sets the canonical values. The `$timestamp` is captured at call time so the timeline stays accurate. This method never throws and never blocks; a failed step is silently skipped.

Example:

```swift
PostHogSDK.shared.addExceptionStep("User tapped Checkout", properties: ["screen": "cart"])
```

## Flush

### `PostHogSDK.flush()`

```swift
@objc func flush()
```

Trigger an immediate flush of every queue — events, session-replay snapshots, and structured logs.

## Get anonymous ID

### `PostHogSDK.getAnonymousId()`

```swift
@objc func getAnonymousId() -> String
```

Returns the anonymous ID generated for this install.

#### Return Value

The anonymous ID, or an empty string when the SDK is not set up.

## Get distinct ID

### `PostHogSDK.getDistinctId()`

```swift
@objc func getDistinctId() -> String
```

Returns the current PostHog distinct ID.

#### Return Value

The current distinct ID, or an empty string when the SDK is not set up.

#### Discussion

Before `identify(_:)`, this is the anonymous ID. After identify, this is the identified user’s ID.

## Get feature flag

### `PostHogSDK.getFeatureFlag(_:)`

```swift
@objc func getFeatureFlag(_ key: String) -> Any?
```

Returns a feature flag value.

#### Parameters

- `key`: The feature flag key.

#### Return Value

`Bool`, `String`, or `nil` if the flag is unavailable.

#### Discussion

Boolean flags return `Bool`. Multivariate flags return their variant `String`.

### `PostHogSDK.getFeatureFlag(_:sendFeatureFlagEvent:)`

```swift
@objc(getFeatureFlagWithKey:sendFeatureFlagEvent:) func getFeatureFlag(_ key: String, sendFeatureFlagEvent: Bool) -> Any?
```

Returns a feature flag value and optionally captures a usage event.

#### Parameters

- `key`: The feature flag key.
- `sendFeatureFlagEvent`: Whether to capture `$feature_flag_called` for this lookup.

#### Return Value

`Bool`, `String`, or `nil` if the flag is unavailable.

## Get feature flag payload

### `PostHogSDK.getFeatureFlagPayload(_:)`

```swift
@objc func getFeatureFlagPayload(_ key: String) -> Any?
```

> **Deprecated:** Use getFeatureFlagResult(_:) instead which properly tracks feature flag usage

Returns the payload for a feature flag.

#### Parameters

- `key`: The feature flag key.

#### Return Value

The flag payload, or `nil` if the flag or payload is unavailable.

#### Discussion

> **Warning:** This method does not send the `$feature_flag_called` event. Use `getFeatureFlagResult(_:)` instead for proper analytics tracking.

## Get feature flag result

### `PostHogSDK.getFeatureFlagResult(_:)`

```swift
@objc func getFeatureFlagResult(_ key: String) -> PostHogFeatureFlagResult?
```

Returns the feature flag result containing the flag value, variant, and payload.

#### Parameters

- `key`: The feature flag key

#### Return Value

A `PostHogFeatureFlagResult` containing the flag’s enabled state, variant (if any), and payload (if any), or `nil` if the flag doesn’t exist.

#### Discussion

This is the recommended method for retrieving feature flags as it provides all flag information in a single call and properly tracks flag usage.

### `PostHogSDK.getFeatureFlagResult(_:sendFeatureFlagEvent:)`

```swift
@objc(getFeatureFlagResultWithKey:sendFeatureFlagEvent:) func getFeatureFlagResult(_ key: String, sendFeatureFlagEvent: Bool) -> PostHogFeatureFlagResult?
```

Returns the feature flag result and optionally captures a usage event.

#### Parameters

- `key`: The feature flag key.
- `sendFeatureFlagEvent`: Whether to capture `$feature_flag_called` for this lookup.

#### Return Value

A result containing enabled state, variant, and payload, or `nil` if unavailable.

## Get feature flags

### `PostHogSDK.getAllFeatureFlags()`

```swift
@objc func getAllFeatureFlags() -> [PostHogFeatureFlagResult]?
```

Returns all currently loaded feature flags as structured results.

#### Return Value

An array of `PostHogFeatureFlagResult`, or `nil` if no flags are loaded.

#### Discussion

Each `PostHogFeatureFlagResult` carries the flag’s `key`, `enabled` state, `variant` (for multivariate flags), and decoded `payload`. Flags become available after they finish loading from the server; before the first load (or when the SDK is disabled) this returns `nil`. Reading does not capture `$feature_flag_called` events.

```swift
for flag in PostHogSDK.shared.getAllFeatureFlags() ?? [] {
    print(flag.key, flag.enabled, flag.payload as Any)
}
```

## Get session ID

### `PostHogSDK.getSessionId()`

```swift
@objc func getSessionId() -> String?
```

Returns the current session ID without rotating or creating a session.

#### Return Value

The current session ID, or `nil` if no session is active or the SDK is not set up.

## Group

### `PostHogSDK.group(type:key:)`

```swift
@objc(groupWithType:key:) func group(type: String, key: String)
```

Associates subsequent events with a group.

#### Parameters

- `type`: Group type, such as `"company"` or `"organization"`.
- `key`: Group key from your application.

### `PostHogSDK.group(type:key:groupProperties:)`

```swift
@objc(groupWithType:key:groupProperties:) func group(type: String, key: String, groupProperties: [String : Any]? = nil)
```

Associates subsequent events with a group and optionally updates group properties.

#### Parameters

- `type`: Group type, such as `"company"` or `"organization"`.
- `key`: Group key from your application.
- `groupProperties`: Optional properties to set on the group profile.

#### Discussion

This sends a `$groupidentify` event and reloads feature flags if the group value changed. The call is ignored if `type` or `key` is empty.

## Is feature enabled

### `PostHogSDK.isFeatureEnabled(_:)`

```swift
@objc func isFeatureEnabled(_ key: String) -> Bool
```

Returns whether a feature flag is enabled.

#### Parameters

- `key`: The feature flag key.

#### Return Value

`true` when the flag is enabled, otherwise `false`.

#### Discussion

Multivariate flags are considered enabled when a variant string is returned.

### `PostHogSDK.isFeatureEnabled(_:sendFeatureFlagEvent:)`

```swift
@objc(isFeatureEnabledWithKey:sendFeatureFlagEvent:) func isFeatureEnabled(_ key: String, sendFeatureFlagEvent: Bool) -> Bool
```

Returns whether a feature flag is enabled and optionally captures a usage event.

#### Parameters

- `key`: The feature flag key.
- `sendFeatureFlagEvent`: Whether to capture `$feature_flag_called` for this lookup.

#### Return Value

`true` when the flag is enabled, otherwise `false`.

## Is opt out

### `PostHogSDK.isOptOut()`

```swift
@objc func isOptOut() -> Bool
```

Returns whether this SDK instance is currently opted out.

#### Return Value

`true` when opted out or when the SDK is not set up.

## Is session replay active

### `PostHogSDK.isSessionReplayActive()`

```swift
@objc func isSessionReplayActive() -> Bool
```

Returns whether session replay is currently recording.

#### Return Value

`true` only when replay is active, a session ID exists, and remote config allows recording.

## On feature flags

### `PostHogSDK.onFeatureFlags(_:)`

```swift
@discardableResult @objc(onFeatureFlags:) func onFeatureFlags(_ callback: @escaping (PostHogFeatureFlagsLoaded) -> Void) -> PostHogFeatureFlagsSubscription
```

Registers a callback that’s invoked whenever feature flags are loaded or updated.

#### Parameters

- `callback`: Receives the enabled flags, their values, and whether loading failed.

#### Return Value

A subscription. Call `unsubscribe()` on it to stop receiving updates.

#### Discussion

The callback runs on the main thread. It’s invoked after the SDK loads flags at startup (including from bootstrap values), after `reloadFeatureFlags()`, and after calls that reload flags such as `identify()`, `group()` or `reset()`. If flags have already loaded when you register, it’s also invoked with the current values shortly afterwards.

You can register before `setup()`. Treat each invocation as “flags may have changed”, not as an exactly-once event.

### `PostHogSDK.didReceiveFeatureFlags`

```swift
@objc static let didReceiveFeatureFlags: Notification.Name
```

Posted after a feature flag reload finishes and cached flags are updated.

#### Discussion

The notification object is `nil`.

## Opt in

### `PostHogSDK.optIn()`

```swift
@objc func optIn()
```

Opts the current user back into data capture.

#### Discussion

This persists the opt-in state, unless opt-out persistence is disabled, and installs integrations that were disabled while opted out. Session replay restarts in a new session if the app wanted it on at `optOut()`: `config.sessionReplay` is enabled or `startSessionRecording()` was called, and `stopSessionRecording()` wasn’t called after. Sampling, linked flags and event triggers apply again to the new session.

### `PostHogSDK.optOut()`

```swift
@objc func optOut()
```

Opts the current user out of data capture.

#### Discussion

This persists the opt-out state, unless opt-out persistence is disabled, stops integrations, and causes future capture calls to be ignored. It also unregisters this device’s push subscription, so Workflows stop sending it notifications. The device token itself is kept, so `optIn()` resubscribes this device on its own — on the next `flush()` or launch at the latest — with no further call from the app.

## Register

### `PostHogSDK.register(_:)`

```swift
@objc(registerProperties:) func register(_ properties: [String : Any])
```

Registers super properties that are included with every subsequent event.

#### Parameters

- `properties`: Event properties to persist and attach to future captures.

#### Discussion

New values overwrite existing values for the same keys and persist across app restarts until removed with `unregister(_:)` or cleared by `reset()`.

## Reload feature flags

### `PostHogSDK.reloadFeatureFlags()`

```swift
@objc func reloadFeatureFlags()
```

Reloads feature flags for the current user and group context.

### `PostHogSDK.reloadFeatureFlags(_:)`

```swift
@objc(reloadFeatureFlagsWithCallback:) func reloadFeatureFlags(_ callback: @escaping () -> Void)
```

Reloads feature flags and invokes a callback when finished.

#### Parameters

- `callback`: Invoked when the reload finishes, or immediately if the reload is skipped (SDK disabled/opted-out, or no remote config available).

## Reset

### `PostHogSDK.reset()`

```swift
@objc func reset()
```

Resets local identity, super properties, feature flag cache, and session state.

#### Discussion

Call this when a user logs out. The next captured event will use a new anonymous identity unless `PostHogConfig.reuseAnonymousId` is enabled. If a push token is registered, it is unregistered for the logged-out identity and re-registered under the new anonymous id.

## Reset group properties for flags

### `PostHogSDK.resetGroupPropertiesForFlags()`

```swift
@objc func resetGroupPropertiesForFlags()
```

Clears all group properties for feature flag evaluation.

#### Example Usage

```swift
// Clear all group properties
PostHogSDK.shared.resetGroupPropertiesForFlags()
```

### `PostHogSDK.resetGroupPropertiesForFlags(_:)`

```swift
@objc(resetGroupPropertiesForFlagsWithGroupType:) func resetGroupPropertiesForFlags(_ groupType: String)
```

Clears group properties for feature flag evaluation for a specific group type.

#### Parameters

- `groupType`: The group type to clear properties for

#### Example Usage

```swift
// Clear properties for specific group type
PostHogSDK.shared.resetGroupPropertiesForFlags("organization")
```

### `PostHogSDK.resetGroupPropertiesForFlags(_:reloadFeatureFlags:)`

```swift
@objc(resetGroupPropertiesForFlagsWithGroupType:reloadFeatureFlags:) func resetGroupPropertiesForFlags(_ groupType: String, reloadFeatureFlags: Bool = true)
```

Clears group properties for feature flag evaluation for a specific group type.

#### Parameters

- `groupType`: The group type to clear properties for
- `reloadFeatureFlags`: Whether to automatically reload feature flags after clearing properties for this group type.

#### Example Usage

```swift
// Clear properties for specific group type
PostHogSDK.shared.resetGroupPropertiesForFlags("organization", reloadFeatureFlags: true)
```

### `PostHogSDK.resetGroupPropertiesForFlags(reloadFeatureFlags:)`

```swift
@objc(resetGroupPropertiesForFlagsWithReloadFeatureFlags:) func resetGroupPropertiesForFlags(reloadFeatureFlags: Bool = true)
```

Clears all group properties for feature flag evaluation.

#### Parameters

- `reloadFeatureFlags`: Whether to automatically reload feature flags after clearing all group properties.

#### Example Usage

```swift
// Clear all group properties
PostHogSDK.shared.resetGroupPropertiesForFlags(reloadFeatureFlags: true)
```

## Reset person properties for flags

### `PostHogSDK.resetPersonPropertiesForFlags()`

```swift
@objc func resetPersonPropertiesForFlags()
```

Resets all person properties that were set for feature flag evaluation.

#### Discussion

After calling this method, feature flag evaluation will only use server-side person properties and will not include any locally overridden properties.

#### Example Usage

```swift
// Clear all locally set person properties for flags
PostHogSDK.shared.resetPersonPropertiesForFlags()

// Feature flags will now use only server-side properties
let flagValue = PostHogSDK.shared.isFeatureEnabled("feature")
```

### `PostHogSDK.resetPersonPropertiesForFlags(reloadFeatureFlags:)`

```swift
@objc(resetPersonPropertiesForFlagsWithReloadFeatureFlags:) func resetPersonPropertiesForFlags(reloadFeatureFlags: Bool = true)
```

Resets all person properties that were set for feature flag evaluation.

#### Parameters

- `reloadFeatureFlags`: Whether to automatically reload feature flags after resetting properties

#### Discussion

After calling this method, feature flag evaluation will only use server-side person properties and will not include any locally overridden properties.

#### Example Usage

```swift
// Clear all locally set person properties for flags
PostHogSDK.shared.resetPersonPropertiesForFlags(reloadFeatureFlags: true)

// Feature flags will now use only server-side properties
let flagValue = PostHogSDK.shared.isFeatureEnabled("feature")
```

## Screen

### `PostHogSDK.screen(_:)`

```swift
@objc func screen(_ screenTitle: String)
```

Records a screen view by capturing a `$screen` event.

#### Parameters

- `screenTitle`: The screen name to record.

### `PostHogSDK.screen(_:properties:)`

```swift
@objc(screenWithTitle:properties:) func screen(_ screenTitle: String, properties: [String : Any]? = nil)
```

Records a screen view by capturing a `$screen` event with `screenTitle`.

#### Parameters

- `screenTitle`: The screen name to record. It takes precedence over a `$screen_name` key in `properties`.
- `properties`: Additional properties to attach to this `$screen` event.

#### Discussion

The title is also cached and automatically attached as `$screen_name` to every subsequent event (until `reset()` or `close()` clears it).

To override the auto-attached value on another event, pass `$screen_name` in that event’s `properties` dictionary.

## Set group properties for flags

### `PostHogSDK.setGroupPropertiesForFlags(_:properties:)`

```swift
@objc(setGroupPropertiesForFlags:properties:) func setGroupPropertiesForFlags(_ groupType: String, properties: [String : Any])
```

Sets properties for a specific group type to include when evaluating feature flags. These properties supplement the standard group information sent to PostHog for flag evaluation, providing additional context that can be used in flag targeting conditions.

#### Parameters

- `groupType`: The group type identifier (e.g., “organization”, “team”)
- `properties`: Dictionary of properties to set for this group type

#### Example Usage

```swift
PostHogSDK.shared.setGroupPropertiesForFlags("organization", properties: [
    "plan": "enterprise",
    "seats": 50,
    "industry": "technology"
])
```

> **Note:** This method automatically reloads feature flags to apply the new properties.

> **See Also:** `setGroupPropertiesForFlags(_:properties:reloadFeatureFlags:)` to control flag reloading behavior

### `PostHogSDK.setGroupPropertiesForFlags(_:properties:reloadFeatureFlags:)`

```swift
@objc(setGroupPropertiesForFlags:properties:reloadFeatureFlags:) func setGroupPropertiesForFlags(_ groupType: String, properties: [String : Any], reloadFeatureFlags: Bool = true)
```

Sets properties for a specific group type to include when evaluating feature flags. These properties supplement the standard group information sent to PostHog for flag evaluation, providing additional context that can be used in flag targeting conditions.

#### Parameters

- `groupType`: The group type identifier (e.g., “organization”, “team”)
- `properties`: Dictionary of properties to set for this group type
- `reloadFeatureFlags`: Whether to automatically reload feature flags after setting properties

#### Example Usage

```swift
// Set properties without automatically reloading flags
PostHogSDK.shared.setGroupPropertiesForFlags("organization", properties: [
    "plan": "enterprise",
    "seats": 50
], reloadFeatureFlags: false)

// Manually reload flags later
PostHogSDK.shared.reloadFeatureFlags()
```

## Set person properties

### `PostHogSDK.setPersonProperties(userPropertiesToSet:)`

```swift
@objc(setPersonPropertiesWithUserPropertiesToSet:) func setPersonProperties(userPropertiesToSet: [String : Any]?)
```

Sets properties on the person profile associated with the current distinct_id.

#### Parameters

- `userPropertiesToSet`: Properties to store about the user. These will overwrite existing values.

#### Discussion

Updates user properties that are stored with the person profile in PostHog. If `personProfiles` is set to `never`, this call will be ignored.

This method sends a `$set` event to PostHog.

### `PostHogSDK.setPersonProperties(userPropertiesToSet:userPropertiesToSetOnce:)`

```swift
@objc(setPersonPropertiesWithUserPropertiesToSet:userPropertiesToSetOnce:) func setPersonProperties(userPropertiesToSet: [String : Any]?, userPropertiesToSetOnce: [String : Any]?)
```

Sets properties on the person profile associated with the current distinct_id.

#### Parameters

- `userPropertiesToSet`: Properties to store about the user. These will overwrite existing values.
- `userPropertiesToSetOnce`: Properties to store about the user only if not previously set. Note: For feature flag evaluations, if the same key is present in both parameters, the value from userPropertiesToSet will take precedence.

#### Discussion

Updates user properties that are stored with the person profile in PostHog. If `personProfiles` is set to `never`, this call will be ignored.

This method sends a `$set` event to PostHog.

## Set person properties for flags

### `PostHogSDK.setPersonPropertiesForFlags(_:)`

```swift
@objc func setPersonPropertiesForFlags(_ properties: [String : Any])
```

Sets person properties that will be included in feature flag evaluation requests.

#### Parameters

- `properties`: Dictionary of person properties to include in flag evaluation

#### Discussion

This method allows you to override server-side person properties for immediate feature flag evaluation, solving the race condition where person properties from `identify()` calls may not have been processed by the server yet.

Properties are merged additively with existing properties. Feature flags are automatically reloaded after setting properties.

#### Example Usage

```swift
// Set properties and automatically reload flags
PostHogSDK.shared.setPersonPropertiesForFlags([
    "$app_version": "2.93.0",
    "plan": "premium"
])

// Now feature flags will be evaluated with these properties
let flagValue = PostHogSDK.shared.isFeatureEnabled("new_feature")
```

> **Important:** The reload is asynchronous and is **not** ordered against the automatic preload that `PostHogConfig.preloadFeatureFlags` starts at setup. See `setPersonPropertiesForFlags(_:reloadFeatureFlags:)` for the startup ordering contract and how to wait for flags evaluated with these properties.

> **See Also:** `setPersonPropertiesForFlags(_:reloadFeatureFlags:)` to control flag reloading behavior

### `PostHogSDK.setPersonPropertiesForFlags(_:reloadFeatureFlags:)`

```swift
@objc(setPersonPropertiesForFlagsWithProperties:reloadFeatureFlags:) func setPersonPropertiesForFlags(_ properties: [String : Any], reloadFeatureFlags: Bool = true)
```

Sets person properties that will be included in feature flag evaluation requests.

#### Parameters

- `properties`: Dictionary of person properties to include in flag evaluation
- `reloadFeatureFlags`: Whether to automatically reload feature flags after setting properties

#### Discussion

This method allows you to override server-side person properties for immediate feature flag evaluation, solving the race condition where person properties from `identify()` calls may not have been processed by the server yet.

Properties are merged additively with existing properties.

#### Example Usage

```swift
// Set properties without automatically reloading flags
PostHogSDK.shared.setPersonPropertiesForFlags([
    "$app_version": "2.93.0",
    "plan": "premium"
], reloadFeatureFlags: false)

// Manually reload flags later
PostHogSDK.shared.reloadFeatureFlags()
```

#### Startup ordering

Several code paths can each start a `/flags` request at launch, and none of them is ordered against this call:

- the automatic preload started during `setup()` when `PostHogConfig.preloadFeatureFlags` is `true` (the default) — it can go out before your properties are set, so an early flag read may see values evaluated without them,

- `identify(...)`, which reloads flags itself,

- any explicit `reloadFeatureFlags()` your app makes.

Requests are coalesced rather than run concurrently, so your properties always reach the server eventually. To read a flag that reflects them, set them without reloading and wait for an explicit reload rather than reading immediately after setup:

```swift
PostHogSDK.shared.setPersonPropertiesForFlags(["plan": "premium"], reloadFeatureFlags: false)
PostHogSDK.shared.reloadFeatureFlags {
    let flagValue = PostHogSDK.shared.isFeatureEnabled("new_feature")
}
```

Setting `PostHogConfig.preloadFeatureFlags = false` removes the automatic preload entirely and leaves your app in control of when flags load.

> **Note:** `reset()` clears person properties set here, so they must be set again afterwards.

> **Note:** `reloadFeatureFlags(_:)` reports that the reload finished, not that it succeeded. If the request fails, or the project is over its feature flag quota, the handler still runs and the flags you read are the previously cached ones.

## Shutdown

### `PostHogSDK.close()`

```swift
@objc func close()
```

Shuts down this SDK instance and clears its in-memory state.

#### Discussion

Starts sending queued events, session replay snapshots, and logs (up to one batch each) and returns without waiting for delivery. Anything not sent, for example while offline, stays on disk and is sent after the next setup. Integrations are uninstalled, and this instance must be set up again before reuse.

## Start session recording

### `PostHogSDK.startSessionRecording()`

```swift
@objc(startSessionRecording) func startSessionRecording()
```

Starts session recording.

#### Discussion

This method will have no effect if PostHog is not enabled, or if session replay is disabled in your project settings.

Ingestion controls are not overridden when calling this method. The recording will not start if:

- The session is not sampled,

- Event triggers are configured and have not been activated for the current session.

#### Note:

- Calling this method will resume the current session or create a new one if it doesn’t exist

- With `config.sessionReplay = false`, recording started here continues into new sessions until `stopSessionRecording()` is called

### `PostHogSDK.startSessionRecording(resumeCurrent:)`

```swift
@objc(startSessionRecordingWithResumeCurrent:) func startSessionRecording(resumeCurrent: Bool)
```

Starts session recording.

#### Parameters

- `resumeCurrent`:  Whether to resume recording of current session (true) or start a new session (false).

#### Discussion

This method will have no effect if PostHog is not enabled, or if session replay is disabled in your project settings.

Ingestion controls are not overridden when calling this method. The recording will not start if:

- The session is not sampled,

- Event triggers are configured and have not been activated for the current session.

## Stop session recording

### `PostHogSDK.stopSessionRecording()`

```swift
@objc func stopSessionRecording()
```

Stops the current session recording if one is in progress.

#### Discussion

With `config.sessionReplay = false`, this also cancels a pending `startSessionRecording()` call, so remote config loads, event triggers and session changes will not start recording until the app calls `startSessionRecording()` again. A later `optOut()` and `optIn()` don’t restart it either. While opted out this method is ignored.

Stopping also starts a best-effort, asynchronous flush of replay snapshots already recorded instead of waiting for the next scheduled flush. Normal buffering and delivery limits still apply: snapshots can be held back, for example because the session is shorter than the minimum duration, and a large backlog is sent over more than one flush.

This method will have no effect if PostHog is not enabled

## Unregister

### `PostHogSDK.unregister(_:)`

```swift
@objc(unregisterProperties:) func unregister(_ key: String)
```

Removes a previously registered super property.

#### Parameters

- `key`: The property key to stop attaching to future events.

## Autocapture

### `PostHogSDK.isAutocaptureActive()`

```swift
@objc func isAutocaptureActive() -> Bool
```

Returns whether UIKit or SwiftUI element autocapture is enabled in local state.

#### Return Value

`true` when the SDK is set up and either interaction autocapture option is enabled. This does not verify that the swizzling-backed integration was installed.

### `PostHogSDK.isRageClickActive()`

```swift
@objc func isRageClickActive() -> Bool
```

Returns whether rage click autocapture is enabled in local state.

#### Return Value

`true` when the SDK is set up and rage click detection is enabled. This does not verify that the swizzling-backed integration was installed.

## Device ID generator

### `PostHogSDK.getDeviceId()`

```swift
@objc func getDeviceId() -> String
```

Returns the stable device identifier used for device-level feature flag bucketing.

#### Return Value

The stable device ID, or an empty string when the SDK is not set up.

#### Discussion

This ID persists across `identify()` and `reset()` calls, only changing on a fresh app install, manual cache clearing, or OS-initiated storage cleanup.

## Session manager

### `PostHogSDK.endSession()`

```swift
@objc func endSession()
```

Ends the current analytics session.

### `PostHogSDK.startSession()`

```swift
@objc func startSession()
```

Starts or resumes the current analytics session.

## SDK utils

### `PostHogSDK.captureDeepLink(openURLContexts:)`

```swift
@objc func captureDeepLink(openURLContexts: Set<UIOpenURLContext>)
```

Capture a deep link from UIKit scene-based URL contexts.

#### Parameters

- `openURLContexts`: The set of URL contexts from the scene delegate.

#### Discussion

Use this method with `scene(_:openURLContexts:)` in your UISceneDelegate. Only the first URL context is captured.

### `PostHogSDK.captureDeepLink(url:)`

```swift
@objc func captureDeepLink(url: URL)
```

Captures a deep link opened event for a URL.

#### Parameters

- `url`: The URL that was opened.

### `PostHogSDK.captureDeepLink(url:options:)`

```swift
@objc func captureDeepLink(url: URL, options: [UIApplication.OpenURLOptionsKey : Any])
```

Capture a deep link with UIKit open URL options.

#### Parameters

- `url`: The URL that was opened.
- `options`: The options dictionary from UIKit containing source application info.

#### Discussion

Use this method with `application(_:open:options:)` in your UIApplicationDelegate. The source application is extracted as the referrer.

### `PostHogSDK.captureDeepLink(urls:)`

```swift
@objc func captureDeepLink(urls: [URL])
```

Capture deep link events from an array of URLs.

#### Parameters

- `urls`: The URLs that were opened.

#### Discussion

Use this method with macOS `NSApplicationDelegate.application(_:open:)`. File URLs are automatically filtered out; every other URL in the array is captured.

### `PostHogSDK.captureDeepLink(userActivity:)`

```swift
@objc func captureDeepLink(userActivity: NSUserActivity)
```

Capture a deep link from an NSUserActivity (universal links).

#### Parameters

- `userActivity`: The user activity containing the universal link.

#### Discussion

Use this method with `application(_:continue:restorationHandler:)` in your app delegate, or with SwiftUI’s `.onContinueUserActivity()` modifier. Only activities of type `NSUserActivityTypeBrowsingWeb` are processed.

### `PostHogSDK.captureFeatureInteraction(flag:flagVariant:)`

```swift
@objc func captureFeatureInteraction(flag: String, flagVariant: String?)
```

Captures a `$feature_interaction` event for the specified feature flag.

#### Parameters

- `flag`: The key of the feature flag being interacted with.
- `flagVariant`: The variant of the feature flag being interacted with. If `nil`, the SDK looks up the current flag value and skips capture when no value is available.

### `PostHogSDK.captureFeatureView(flag:flagVariant:)`

```swift
@objc func captureFeatureView(flag: String, flagVariant: String?)
```

Captures a `$feature_view` event for the specified feature flag.

#### Parameters

- `flag`: The key of the feature flag being viewed.
- `flagVariant`: The variant of the feature flag being viewed. If `nil`, the SDK looks up the current flag value and skips capture when no value is available.

### `PostHogSDK.capturePushNotificationOpened(response:)`

```swift
@objc func capturePushNotificationOpened(response: UNNotificationResponse)
```

Manually captures a `$push_notification_opened` event for a notification the user tapped.

#### Parameters

- `response`: The `UNNotificationResponse` received from the system.

#### Discussion

Use this when you’re not relying on the automatic swizzling installed by `capturePushNotificationOpened`, for example when `enableSwizzling` is `false` or when you manage your own `UNUserNotificationCenterDelegate`. Call it from your `userNotificationCenter(_:didReceive:withCompletionHandler:)` implementation.

The notification’s title/subtitle/body are included only when the push is attributed to PostHog (a `posthog` key in its `userInfo`); unattributed pushes capture the open event without content. Use the field-based overload to capture content explicitly.

A notification sent by PostHog is captured once: when the `posthog` entry of `userInfo` carries an `invocation_id`, a repeat with the same `invocation_id` and `action_id` within 5 minutes of the first capture is skipped, whether that first capture came from this method, from the field-based overload, or from the SDK’s automatic capture. Notifications without a `posthog.invocation_id` are always captured. Only the 20 most recently captured notifications are remembered, so a host that reports more than that inside the window can capture a repeat of the oldest.

A rerun of that workflow, or a loop back to its push step, sends the pair again as a new notification, and its open counts separately: two responses whose `notification.request.identifier` differ are two taps, not one reported twice.

### `PostHogSDK.capturePushNotificationOpened(title:subtitle:body:payload:action:)`

```swift
@objc func capturePushNotificationOpened(title: String? = nil, subtitle: String? = nil, body: String? = nil, payload: [AnyHashable : Any]? = nil, action: String? = nil)
```

Manually captures a `$push_notification_opened` event from raw notification fields.

#### Parameters

- `title`: The notification title; omitted from the event when `nil` or empty.
- `subtitle`: The notification subtitle; omitted when `nil` or empty.
- `body`: The notification body; omitted when `nil` or empty.
- `payload`: The notification payload (`userInfo`). The keys of its `posthog` entry — a dictionary, or a JSON string when relayed through FCM — become `$notification_<key>` properties.
- `action`: The action identifier for an action-button tap; leave `nil` for a plain tap (the default action is omitted from the event).

#### Discussion

Use this when no `UNNotificationResponse` is available — for example when you handle a push yourself in `application(_:didReceiveRemoteNotification:fetchCompletionHandler:)` or relay it from a cross-platform layer.

A notification sent by PostHog is captured once: when `payload["posthog"]` carries an `invocation_id`, a repeat with the same `invocation_id` and `action_id` within 5 minutes of the first capture is skipped, whether that first capture came from this method or from the SDK’s automatic capture. Payloads without a `posthog.invocation_id` are always captured. Only the 20 most recently captured notifications are remembered, so a host that reports more than that inside the window can capture a repeat of the oldest. This overload carries no notification identifier, so a rerun of that workflow reported through it inside the window reads as the same tap and is skipped; report a rerun through `capturePushNotificationOpened(response:)`, which can tell the deliveries apart.

### `PostHogSDK.registerPushNotificationToken(_:)`

```swift
@objc func registerPushNotificationToken(_ deviceToken: String)
```

Sends a device push token to PostHog so Workflows can deliver push notifications to this device.

#### Parameters

- `deviceToken`: The APNs token as a lowercase-hex string. Convert a `Data` token via `token.map { String(format: "%02x", $0) }.joined()`.

#### Discussion

Call this from `application(_:didRegisterForRemoteNotificationsWithDeviceToken:)` when you don’t rely on automatic swizzling (for example when `enableSwizzling` is `false`).

The token is linked to the current distinct id, so it follows the user across `identify(_:)`.

> **Note:** Push registration is available on iOS only in this version.

### `PostHogSDK.registerPushNotificationToken(_:appId:)`

```swift
@objc func registerPushNotificationToken(_ deviceToken: String, appId: String?)
```

Sends a device push token to PostHog under an explicit app id.

#### Parameters

- `deviceToken`: The push token string (APNs lowercase-hex, or an FCM token verbatim).
- `appId`: The app identifier the token belongs to, or `nil` to use the bundle identifier.

#### Discussion

Use the `appId` overload when relaying a token obtained through another provider (for example a Firebase `project_id`). When `appId` is `nil` the app’s bundle identifier is used.

> **Note:** Push registration is available on iOS only in this version.

### `PostHogSDK.unregisterPushNotificationToken()`

```swift
@objc func unregisterPushNotificationToken()
```

Unregisters this device’s push token from PostHog so Workflows stop targeting it — for example from your logout flow.

#### Discussion

Sends a `DELETE /api/push_subscriptions/` for the identity the token was delivered to — the current distinct id when nothing was delivered yet — so the backend unsets the subscription property on the person that actually holds it, and forgets the locally stored token. The delete intent is durable: an offline or failed attempt is retried on `flush()`/next launch until it succeeds or hits a terminal 4xx. Call it directly if you manage push subscriptions yourself. On `reset()` the SDK already moves any registered token to the new anonymous identity (unregister then re-register), independently of `capturePushNotificationSubscriptions` — that flag only gates automatic token subscription at startup.

### `PostHogSDK.didStartNotification`

```swift
@objc static let didStartNotification: Notification.Name
```

Posted on the main queue after `setup(_:)` finishes successfully.

#### Discussion

The notification object is `nil`.

### `PostHogSDK.shared`

```swift
@objc nonisolated(unsafe) static let shared: PostHogSDK
```

Shared singleton SDK instance used by most applications.

#### Discussion

Call `setup(_:)` once with a `PostHogConfig` before using capture APIs.

### `PostHogSDK.prewarmPushNotificationOpenCapture()`

```swift
@objc static func prewarmPushNotificationOpenCapture()
```

Installs the notification-open swizzles before `setup()` is called.

#### Discussion

A cold launch from a notification tap delivers the response to the app within a few hundred milliseconds — sooner than a cross-platform host (Flutter, React Native) can reach its own `setup()` call from the Dart/JS runtime, so the swizzles are not yet in place and the open is lost. Call this from `application(_:didFinishLaunchingWithOptions:)`, or from a plugin registration that runs inside it, and the response is held until `setup()` installs the integration, which then captures it.

Holds at most one response, and only replays it when `setup()` follows within 30 seconds. Native iOS apps that call `setup()` from `didFinishLaunchingWithOptions` do not need this.

The swizzles are installed immediately and released again when the last subscriber detaches (`close()`), or at `setup()` when the config disables push-open capture or the app is opted out. If `setup()` is never called they stay for the process lifetime. The per-class delegate wrapper, as elsewhere in this SDK, stays for the process lifetime regardless.

### `URLSession.postHogData(for:delegate:postHog:)`

```swift
func postHogData(for request: URLRequest, delegate: (any URLSessionTaskDelegate)? = nil, postHog: PostHogSDK? = nil) async throws -> (Data, URLResponse)
```

Performs `data(for:delegate:)` and captures network telemetry for session replay.

#### Parameters

- `request`: Request to execute.
- `delegate`: Task delegate for the request.
- `postHog`: SDK instance used to read the session ID and emit telemetry. Pass an initialized instance; `nil` performs the request without capturing replay telemetry.

#### Return Value

The data and URL response returned by `URLSession`.

#### Discussion

> **Throws:** Any error thrown by `URLSession.data(for:delegate:)`.

### `URLSession.postHogData(for:postHog:)`

```swift
func postHogData(for request: URLRequest, postHog: PostHogSDK? = nil) async throws -> (Data, URLResponse)
```

Performs `data(for:)` and captures network telemetry for session replay.

#### Parameters

- `request`: Request to execute.
- `postHog`: SDK instance used to read the session ID and emit telemetry. Pass an initialized instance; `nil` performs the request without capturing replay telemetry.

#### Return Value

The data and URL response returned by `URLSession`.

#### Discussion

> **Throws:** Any error thrown by `URLSession.data(for:)`.

### `URLSession.postHogData(from:delegate:postHog:)`

```swift
func postHogData(from url: URL, delegate: (any URLSessionTaskDelegate)? = nil, postHog: PostHogSDK? = nil) async throws -> (Data, URLResponse)
```

Performs `data(from:delegate:)` and captures network telemetry for session replay.

#### Parameters

- `url`: URL to request.
- `delegate`: Task delegate for the request.
- `postHog`: SDK instance used to read the session ID and emit telemetry. Pass an initialized instance; `nil` performs the request without capturing replay telemetry.

#### Return Value

The data and URL response returned by `URLSession`.

#### Discussion

> **Throws:** Any error thrown by `URLSession.data(from:delegate:)`.

### `URLSession.postHogData(from:postHog:)`

```swift
func postHogData(from url: URL, postHog: PostHogSDK? = nil) async throws -> (Data, URLResponse)
```

Performs `data(from:)` and captures network telemetry for session replay.

#### Parameters

- `url`: URL to request.
- `postHog`: SDK instance used to read the session ID and emit telemetry. Pass an initialized instance; `nil` performs the request without capturing replay telemetry.

#### Return Value

The data and URL response returned by `URLSession`.

#### Discussion

> **Throws:** Any error thrown by `URLSession.data(from:)`.

### `URLSession.postHogDownload(for:delegate:postHog:)`

```swift
func postHogDownload(for request: URLRequest, delegate: (any URLSessionTaskDelegate)? = nil, postHog: PostHogSDK? = nil) async throws -> (URL, URLResponse)
```

Performs `download(for:delegate:)` and captures network telemetry for session replay.

#### Parameters

- `request`: Download request to execute.
- `delegate`: Task delegate for the request.
- `postHog`: SDK instance used to read the session ID and emit telemetry. Pass an initialized instance; `nil` performs the request without capturing replay telemetry.

#### Return Value

The downloaded file URL and URL response returned by `URLSession`.

#### Discussion

> **Throws:** Any error thrown by `URLSession.download(for:delegate:)`.

### `URLSession.postHogDownload(from:delegate:postHog:)`

```swift
func postHogDownload(from url: URL, delegate: (any URLSessionTaskDelegate)? = nil, postHog: PostHogSDK? = nil) async throws -> (URL, URLResponse)
```

Performs `download(from:delegate:)` and captures network telemetry for session replay.

#### Parameters

- `url`: URL to download.
- `delegate`: Task delegate for the request.
- `postHog`: SDK instance used to read the session ID and emit telemetry. Pass an initialized instance; `nil` performs the request without capturing replay telemetry.

#### Return Value

The downloaded file URL and URL response returned by `URLSession`.

#### Discussion

> **Throws:** Any error thrown by `URLSession.download(from:delegate:)`.

### `URLSession.postHogDownload(resumeFrom:delegate:postHog:)`

```swift
func postHogDownload(resumeFrom resumeData: Data, delegate: (any URLSessionTaskDelegate)? = nil, postHog: PostHogSDK? = nil) async throws -> (URL, URLResponse)
```

Performs `download(resumeFrom:delegate:)` and captures network telemetry for session replay.

#### Parameters

- `resumeData`: Resume data from a previously cancelled download.
- `delegate`: Task delegate for the request.
- `postHog`: SDK instance used to read the session ID and emit telemetry. Pass an initialized instance; `nil` performs the request without capturing replay telemetry.

#### Return Value

The downloaded file URL and URL response returned by `URLSession`.

#### Discussion

> **Throws:** Any error thrown by `URLSession.download(resumeFrom:delegate:)`.

### `URLSession.postHogUpload(for:from:delegate:postHog:)`

```swift
func postHogUpload(for request: URLRequest, from bodyData: Data, delegate: (any URLSessionTaskDelegate)? = nil, postHog: PostHogSDK? = nil) async throws -> (Data, URLResponse)
```

Performs `upload(for:from:delegate:)` and captures network telemetry for session replay.

#### Parameters

- `request`: Upload request to execute.
- `bodyData`: Request body data to upload.
- `delegate`: Task delegate for the request.
- `postHog`: SDK instance used to read the session ID and emit telemetry. Pass an initialized instance; `nil` performs the request without capturing replay telemetry.

#### Return Value

The data and URL response returned by `URLSession`.

#### Discussion

> **Throws:** Any error thrown by `URLSession.upload(for:from:delegate:)`.

### `URLSession.postHogUpload(for:from:postHog:)`

```swift
func postHogUpload(for request: URLRequest, from bodyData: Data, postHog: PostHogSDK? = nil) async throws -> (Data, URLResponse)
```

Performs `upload(for:from:)` and captures network telemetry for session replay.

#### Parameters

- `request`: Upload request to execute.
- `bodyData`: Request body data to upload.
- `postHog`: SDK instance used to read the session ID and emit telemetry. Pass an initialized instance; `nil` performs the request without capturing replay telemetry.

#### Return Value

The data and URL response returned by `URLSession`.

#### Discussion

> **Throws:** Any error thrown by `URLSession.upload(for:from:)`.

### `URLSession.postHogUpload(for:fromFile:delegate:postHog:)`

```swift
func postHogUpload(for request: URLRequest, fromFile fileURL: URL, delegate: (any URLSessionTaskDelegate)? = nil, postHog: PostHogSDK? = nil) async throws -> (Data, URLResponse)
```

Performs `upload(for:fromFile:delegate:)` and captures network telemetry for session replay.

#### Parameters

- `request`: Upload request to execute.
- `fileURL`: File URL to upload.
- `delegate`: Task delegate for the request.
- `postHog`: SDK instance used to read the session ID and emit telemetry. Pass an initialized instance; `nil` performs the request without capturing replay telemetry.

#### Return Value

The data and URL response returned by `URLSession`.

#### Discussion

> **Throws:** Any error thrown by `URLSession.upload(for:fromFile:delegate:)`.

### `URLSession.postHogUpload(for:fromFile:postHog:)`

```swift
func postHogUpload(for request: URLRequest, fromFile fileURL: URL, postHog: PostHogSDK? = nil) async throws -> (Data, URLResponse)
```

Performs `upload(for:fromFile:)` and captures network telemetry for session replay.

#### Parameters

- `request`: Upload request to execute.
- `fileURL`: File URL to upload.
- `postHog`: SDK instance used to read the session ID and emit telemetry. Pass an initialized instance; `nil` performs the request without capturing replay telemetry.

#### Return Value

The data and URL response returned by `URLSession`.

#### Discussion

> **Throws:** Any error thrown by `URLSession.upload(for:fromFile:)`.

### `View.postHogDeepLinkListener(_:)`

```swift
@MainActor func postHogDeepLinkListener(_ posthog: PostHogSDK? = nil) -> some View

```

Attach a PostHog deep link listener to this view.

#### Parameters

- `posthog`: SDK instance to use for tracking. Defaults to `PostHogSDK.shared`.

#### Return Value

A modified view that captures supported deep link events.

#### Discussion

The listener forwards `.onOpenURL` and `.onContinueUserActivity` events to PostHog.

### `View.postHogLabel(_:)`

```swift
@MainActor func postHogLabel(_ label: String?) -> some View

```

Adds a custom label to this view for use with PostHog’s auto-capture functionality.

#### Parameters

- `label`: A custom label that uniquely identifies the element for analytics purposes.

#### Return Value

A modified view that applies the label to the underlying UIKit view when possible.

#### Discussion

By setting a custom label, you can easily identify and filter interactions with this specific element in your analytics data.

##### Usage

```swift
struct ContentView: View {
   var body: some View {
       Button("Login") {
           ...
       }
       .postHogLabel("loginButton")
     }
}
```

### `View.postHogMask(_:)`

```swift
@MainActor func postHogMask(_ isEnabled: Bool = true) -> some View

```

Marks a SwiftUI View to be masked in PostHog session replay recordings.

#### Parameters

- `isEnabled`: Whether masking should be enabled. Defaults to true.

#### Return Value

A modified view that will be masked in session replay recordings when enabled

#### Discussion

Use this modifier to explicitly mask sensitive views in session replay recordings.

The masked region is reported through a single passive overlay view whose frame is read live at capture time, so the redaction can never go stale — a row that scrolled, animated, or was repositioned is redacted at its current position. This does not rely on mapping SwiftUI content to backing UIKit views, so it behaves identically across OS rendering engines (including iOS 26+).

Note: an explicit `postHogMask()` always masks its region, even inside an area marked with `postHogNoMask()` — the explicit mask wins.

Note: for `.drawingGroup()` or `Canvas` content, apply this modifier to the group itself.

For example:

```swift
// This view will be masked in recordings
SensitiveDataView()
   .postHogMask()

// Conditionally mask based on a flag
SensitiveDataView()
   .postHogMask(shouldMask)
```

### `View.postHogNoMask()`

```swift
@MainActor func postHogNoMask() -> some View

```

Marks a SwiftUI View to be excluded from masking in PostHog session replay recordings.

#### Return Value

A modified view that will not be masked in session replay recordings

#### Discussion

Note: On iOS 26+ (Xcode 26 SwiftUI rendering engine), SwiftUI views may no longer map reliably to a backing `UIView`, so this modifier may behave inconsistently. A future SDK update will try to address this limitation, but for now, we recommend using this modifier with caution.

There are cases where PostHog SDK will unintentionally mask some SwiftUI views.

Because of the nature of how we intercept SwiftUI view hierarchy (and how it maps to UIKit), we can’t always be 100% confident that a view should be masked. For that reason, we prefer to take a proactive and prefer to mask views if we’re not sure.

Use this modifier to prevent views from being masked in session replay recordings.

Note: for `.drawingGroup()` or `Canvas` content, apply this modifier to the group itself.

For example:

```swift
// This view may be accidentally masked by PostHog SDK
SomeSafeView()

// This custom view (and all its subviews) will not be masked in recordings
SomeSafeView()
  .postHogNoMask()
```

### `View.postHogNoRageClick(_:)`

```swift
@MainActor func postHogNoRageClick(_ isEnabled: Bool = true) -> some View

```

Excludes a SwiftUI View from PostHog rage click detection.

#### Parameters

- `isEnabled`: Whether the view should be excluded from rage click detection. Defaults to true.

#### Return Value

A modified view that is excluded from rage click detection when enabled.

#### Discussion

Rapid repeated taps on this view (and its descendants) will not be captured as a `$rageclick` event. Use this for controls where fast repeated tapping is intentional but not auto-detected as a UIKit control — for example a custom-built stepper or carousel arrow.

For example:

```swift
// Taps on this control won't trigger rage clicks
CustomStepper()
   .postHogNoRageClick()

// Conditionally opt out based on a flag
CustomStepper()
   .postHogNoRageClick(shouldExclude)
```

### `View.postHogScreenView(_:_:postHog:)`

```swift
@MainActor func postHogScreenView(_ screenName: String? = nil, _ properties: [String : Any]? = nil, postHog: PostHogSDK? = nil) -> some View

```

Marks a SwiftUI view to be tracked as a `$screen` event when `onAppear` runs.

#### Parameters

- `screenName`: The screen name. Defaults to the view’s type name.
- `properties`: Additional properties to attach to the `$screen` event.
- `postHog`: SDK instance used to send the event. Defaults to `PostHogSDK.shared`.

#### Return Value

A modified view that captures a screen view when it appears.

### `View.postHogViewSeen(_:_:postHog:)`

```swift
@MainActor func postHogViewSeen(_ event: String, _ properties: [String : Any]? = nil, postHog: PostHogSDK? = nil) -> some View

```

Captures a custom event when this SwiftUI view appears.

#### Parameters

- `event`: Event name to capture.
- `properties`: Additional event properties.
- `postHog`: SDK instance used to send the event. Defaults to `PostHogSDK.shared`.

#### Return Value

A modified view that captures the event when it appears.

### `UIView.postHogLabel`

```swift
@MainActor var postHogLabel: String? { get set }
```

Adds a custom label to this view for use with PostHog’s auto-capture functionality.

#### Discussion

By setting a custom label, you can easily identify and filter interactions with this specific element in your analytics data.

##### Usage

```swift
let myView = UIView()
myView.postHogLabel = "customLabel"
```

## Types

### `PostHogBootstrapConfig`

```swift
@objc(PostHogBootstrapConfig) class PostHogBootstrapConfig
```

Pre-seeded identity and feature-flag state applied during setup, before any network request completes.

#### Overview

Set `bootstrap` before calling `setup(_:)` to seed identity and feature flag state. This ensures events captured synchronously during initialization (`Application Installed` / `Application Updated`, pre-identify lifecycle events) carry a caller-controlled `$distinct_id` rather than the SDK-generated UUID, and that feature flag reads return caller-provided values before the first `/flags` response. Mirrors the `bootstrap option in posthog-js`.

Identity is seeded on a fresh install. For a returning user, an identified bootstrap (`isIdentifiedId` `== true`) reconciles against the stored identity — upgrading a matching anonymous ID to identified, merging a differing anonymous user into the bootstrapped ID, or preserving a different already-identified user. An anonymous bootstrap is ignored once an anonymous ID is persisted. Bootstrapped feature flags form a temporary base layer applied on every initialization: the first complete `/flags` response replaces them, while a partial or errored response overlays only the keys it recomputed.

#### `PostHogBootstrapConfig.init()`

```swift
override init()
```

Creates an empty bootstrap; set the properties you need before assigning it to `bootstrap`.

#### `PostHogBootstrapConfig.init(anonymousId:)`

```swift
@objc convenience init(anonymousId: String)
```

Seeds an anonymous identity: `anonymousId` becomes the `$distinct_id` for events captured before the host calls `identify(...)`.

#### `PostHogBootstrapConfig.init(distinctId:isIdentifiedId:)`

```swift
@objc convenience init(distinctId: String, isIdentifiedId: Bool)
```

Seeds identity from a `distinctId`, stating explicitly whether it is already identified.

##### Discussion

Pass `isIdentifiedId: true` for a user the host has already identified (seeds `.distinctId` and marks the install identified), or `false` to seed it as an anonymous ID instead (equivalent to `init(anonymousId:)`).

#### `PostHogBootstrapConfig.init(distinctId:isIdentifiedId:featureFlags:featureFlagPayloads:)`

```swift
@objc init(distinctId: String?, isIdentifiedId: Bool = false, featureFlags: [String : Any]?, featureFlagPayloads: [String : Any]?)
```

Seeds identity and feature-flag state in one initializer. Pass `nil` for any dimension you don’t want to seed.

##### Parameters

- `distinctId`: The ID to seed on first launch, or `nil` to seed no identity. Used as the anonymous ID when `isIdentifiedId` is `false`, or an already-identified user’s ID when `true`.
- `isIdentifiedId`: Whether `distinctId` is an already-identified user. Defaults to `false`.
- `featureFlags`: Flag values served until the first `/flags` response, or `nil`.
- `featureFlagPayloads`: JSON payloads keyed by flag, paired with `featureFlags`, or `nil`.

#### `PostHogBootstrapConfig.init(featureFlags:featureFlagPayloads:)`

```swift
@objc convenience init(featureFlags: [String : Any], featureFlagPayloads: [String : Any]?)
```

Seeds feature-flag state only, without seeding identity.

#### `PostHogBootstrapConfig.distinctId`

```swift
@objc var distinctId: String?
```

The distinct ID to seed on first launch.

##### Discussion

When `isIdentifiedId` is `false` (the default), this becomes the anonymous ID — the `$distinct_id` on pre-identify events. When `true`, it is treated as an already-identified user’s distinct ID and the SDK skips the `$identify` merge for it.

#### `PostHogBootstrapConfig.featureFlagPayloads`

```swift
@objc var featureFlagPayloads: [String : Any]?
```

JSON payloads paired with `featureFlags`, keyed by flag key.

##### Discussion

Each value is the already-decoded payload (for example a dictionary, array, string, or number) for the matching flag, served alongside `featureFlags` before the first `/flags` response.

#### `PostHogBootstrapConfig.featureFlags`

```swift
@objc var featureFlags: [String : Any]?
```

Feature flag values served until the first `/flags` response arrives.

##### Discussion

Maps a flag key to its value (a `Bool` for boolean flags or a `String` for multivariate flags). These values are served immediately after setup so flag reads don’t fall back to not-loaded defaults during cold start. They are a temporary base layer: the first complete `/flags` response replaces the served set entirely, so bootstrapped-only keys are not retained after it; a partial or errored response merges, preserving keys it didn’t recompute.

#### `PostHogBootstrapConfig.isIdentifiedId`

```swift
@objc var isIdentifiedId: Bool
```

Whether `distinctId` represents an already-identified user.

##### Discussion

Defaults to `false`. Set to `true` when the host application has resolved the user’s identity outside the SDK (for example from a backend session token) and wants the iOS SDK to treat them as identified from the first event onward.

### `PostHogConfig`

```swift
@objc(PostHogConfig) class PostHogConfig
```

Runtime configuration for a `PostHogSDK` instance.

#### Overview

Create a config with your project token, mutate any options you need, then pass it to `PostHogSDK.shared.setup(_:)` or `PostHogSDK.with(_:)`. Options that control queues, integrations, or resource attributes should be set before setup; later mutations may not affect already-installed SDK components.

#### `PostHogConfig.init(apiKey:)`

```swift
@objc(apiKey:) convenience init(apiKey: String)
```

> **Deprecated:** Use init(projectToken:) instead. This will be removed in the next major version.

Creates a configuration using the deprecated `apiKey` name.

##### Parameters

- `apiKey`: Your PostHog project token.

##### Discussion

- Deprecated: Use `init(projectToken:)` instead.

#### `PostHogConfig.init(apiKey:host:)`

```swift
@objc(apiKey:host:) convenience init(apiKey: String, host: String = defaultHost)
```

> **Deprecated:** Use init(projectToken:host:) instead. This will be removed in the next major version.

Creates a configuration using the deprecated `apiKey` name and an explicit host.

##### Parameters

- `apiKey`: Your PostHog project token.
- `host`: PostHog ingestion host. Empty or invalid values fall back to `defaultHost`.

##### Discussion

- Deprecated: Use `init(projectToken:host:)` instead.

#### `PostHogConfig.init(projectToken:)`

```swift
@objc(projectToken:) init(projectToken: String)
```

Creates a configuration using the default PostHog host.

##### Parameters

- `projectToken`: Your PostHog project token. Leading and trailing whitespace is trimmed.

#### `PostHogConfig.init(projectToken:host:)`

```swift
@objc(projectToken:host:) init(projectToken: String, host: String = defaultHost)
```

Creates a configuration with an explicit PostHog ingestion host.

##### Parameters

- `projectToken`: Your PostHog project token. Leading and trailing whitespace is trimmed.
- `host`: PostHog ingestion host, for example `"https://us.i.posthog.com"` or `"https://eu.i.posthog.com"`. Empty or invalid values fall back to `defaultHost`.

#### `PostHogConfig.apiKey`

```swift
@objc var apiKey: String { get }
```

> **Deprecated:** Use projectToken instead. This will be removed in the next major version.

Obsolete alias for `projectToken`.

#### `PostHogConfig.appGroupIdentifier`

```swift
@objc var appGroupIdentifier: String?
```

The identifier of the App Group that should be used to store shared analytics data. PostHog will try to get the physical location of the App Group’s shared container, otherwise fallback to the default location Default: nil

#### `PostHogConfig.bootstrap`

```swift
@objc var bootstrap: PostHogBootstrapConfig?
```

Pre-seeded identity and feature-flag state applied during setup, before any network request completes.

##### Discussion

Set this before calling `setup(_:)` so events captured synchronously during initialization (`Application Installed` / `Application Updated`, pre-identify lifecycle events) carry a caller-controlled `$distinct_id` rather than the SDK-generated UUID, and so feature flag reads return caller-provided values before the first `/flags` response. Mirrors the `bootstrap option in posthog-js`.

Identity is seeded on a fresh install. For a returning user, an identified bootstrap (`isIdentifiedId == true`) reconciles against the stored identity — upgrading a matching anonymous ID to identified, merging a differing anonymous user into the bootstrapped ID, or preserving a different already-identified user. An anonymous bootstrap is ignored once an anonymous ID is persisted.

Feature flags are applied on every initialization and take precedence over the persisted flag cache. They are a temporary base layer: the first complete `/flags` response replaces them entirely, while a partial or errored response overlays only the keys it recomputed.

Defaults to `nil` (use the SDK-generated UUID and no bootstrapped flags).

#### `PostHogConfig.captureApplicationLifecycleEvents`

```swift
@objc var captureApplicationLifecycleEvents: Bool
```

Whether the SDK automatically captures application lifecycle events.

##### Discussion

When enabled, the SDK records events such as `Application Installed`, `Application Updated`, `Application Opened`, and background/foreground transitions. Default: `true`.

#### `PostHogConfig.captureAutocaptureElementText`

```swift
@objc var captureAutocaptureElementText: Bool
```

Whether autocapture reads control text and selected values. Requires `captureElementInteractions` to be enabled for regular autocapture events. Also applies to rage-click events when rage-click detection is enabled independently. Explicit `postHogLabel` identifiers remain available when disabled. Manual events and session replay are unaffected. Accessibility labels may still be read to check exclusion markers. Configure before SDK setup. Defaults to `true`.

#### `PostHogConfig.captureElementInteractions`

```swift
@objc var captureElementInteractions: Bool
```

Enables UIKit element interaction autocapture on iOS and Mac Catalyst.

##### Discussion

Enable `captureSwiftUIElementInteractions` for better SwiftUI autocapture events. When that option is disabled, existing SwiftUI gesture capture is preserved. Requires `enableSwizzling = true`. Default: `false`.

#### `PostHogConfig.capturePushNotificationOpened`

```swift
@objc var capturePushNotificationOpened: Bool
```

Automatically capture a `$push_notification_opened` event when the user taps a **remote** push notification, by swizzling `UNUserNotificationCenterDelegate`. Locally-scheduled notifications are ignored — capture those yourself with `PostHogSDK.capturePushNotificationOpened(title:subtitle:body:payload:action:)`, passing the content you scheduled. `capturePushNotificationOpened(response:)` reads title/subtitle/body only from notifications PostHog sent (a `posthog` key in `userInfo`), so for a local one it captures the open with no content.

##### Discussion

A notification sent by PostHog is captured once: a manual `capturePushNotificationOpened` call for a tap this already captured (same `posthog.invocation_id` and `action_id`, within 5 minutes) is skipped, and so is the reverse. A resend of that notification is a separate tap and is captured.

> **Note:** Requires `enableSwizzling` to be `true`. To capture opens without swizzling, call `PostHogSDK.capturePushNotificationOpened(response:)` from your own `userNotificationCenter(_:didReceive:withCompletionHandler:)` implementation.

Default: true. Set to `false` to opt out.

Requires your app to set `UNUserNotificationCenter.current().delegate`. Without one, iOS reports the tap to nobody and no open can be captured, in any app state.

#### `PostHogConfig.capturePushNotificationSubscriptions`

```swift
@objc var capturePushNotificationSubscriptions: Bool
```

Automatically register the device’s APNs token with PostHog by swizzling `application(_:didRegisterForRemoteNotificationsWithDeviceToken:)`, so Workflows can deliver push notifications.

##### Discussion

> **Note:** Requires `enableSwizzling` to be `true`. To register tokens without swizzling, call `PostHogSDK.registerPushNotificationToken(_:)` from your own `application(_:didRegisterForRemoteNotificationsWithDeviceToken:)` implementation. Registration is iOS-only in this version.

Default: true. Set to `false` to opt out.

#### `PostHogConfig.captureScreenViews`

```swift
@objc var captureScreenViews: Bool
```

Automatically captures a `$screen` event whenever the visible screen changes (via `viewDidAppear` swizzling).

##### Discussion

A split view that shows several columns at once counts as one screen, named after the split view, so navigating inside one of its columns does not capture a `$screen` event. Call `PostHogSDK.shared.screen(...)` to track those screens.

`$screen_name` stamping on subsequent events is a related effect: any successful `screen()` call — whether fired by this auto-capture path **or invoked manually** via `PostHogSDK.shared.screen(...)` — caches the screen name so it lands as `$screen_name` on every later event the SDK captures. To opt out of `$screen_name` stamping entirely, set this to `false` **and** avoid calling `screen(...)` manually.

Default: `true`

#### `PostHogConfig.captureSwiftUIElementInteractions`

```swift
@objc var captureSwiftUIElementInteractions: Bool
```

Enables SwiftUI tap autocapture on iOS and Mac Catalyst.

##### Discussion

Works independently of `captureElementInteractions` and requires `enableSwizzling = true`. SwiftUI controls backed by UIKit, such as `TextField`, still require `captureElementInteractions = true` to capture their control interactions. Uses element labels and accessibility identifiers to resolve SwiftUI taps, replacing legacy hosting-view tap events. Event counts and element chains can differ from legacy capture. Unresolved elements are skipped. Configure before SDK setup. Default: `false`.

#### `PostHogConfig.compression`

```swift
@objc var compression: PostHogCompression
```

How the SDK compresses request bodies before sending them to the PostHog API.

##### Discussion

Set this to `.none` when the network between the app and PostHog changes or re-encodes the compressed body, e.g. on a managed work profile, which makes the server reject the request.

Default: `.gzip`.

#### `PostHogConfig.dataMode`

```swift
@objc var dataMode: PostHogDataMode
```

Required network connectivity mode for flushing queued data.

##### Discussion

Only `.wifi` restricts flushing. Default: `.any`.

#### `PostHogConfig.debug`

```swift
@objc var debug: Bool
```

Enables verbose SDK diagnostic logging.

##### Discussion

Default: `false`.

#### `PostHogConfig.disableGeoIp`

```swift
@objc var disableGeoIp: Bool
```

Skip GeoIP enrichment on the server for captured events and feature flag requests.

##### Discussion

When enabled, the server won’t infer the user’s location from their IP address.

Default: false

#### `PostHogConfig.enableSwizzling`

```swift
@objc var enableSwizzling: Bool
```

Enable method swizzling for SDK functionality that depends on it

##### Discussion

When disabled, functionality that require swizzling (like autocapture, screen views, session replay, surveys) will not be installed.

Note: Disabling swizzling will limit session rotation logic to only detect application open and background events. Session rotation will still work, just with reduced granularity for detecting user activity.

Default: true

#### `PostHogConfig.errorTrackingConfig`

```swift
@objc let errorTrackingConfig: PostHogErrorTrackingConfig
```

Configuration for error tracking.

##### Discussion

See known limitations: https://posthog.com/docs/error-tracking/installation/ios#limitations

#### `PostHogConfig.evaluationContexts`

```swift
@objc var evaluationContexts: [String]?
```

Evaluation contexts for feature flags.

##### Discussion

When configured, only feature flags that have at least one matching evaluation tag will be evaluated. Feature flags with no evaluation tags will always be evaluated for backward compatibility.

Example usage:

```swift
config.evaluationContexts = ["production", "web", "checkout"]
```

This helps ensure feature flags are only evaluated in the appropriate contexts for your SDK instance.

Default: nil (all flags are evaluated)

#### `PostHogConfig.evaluationEnvironments`

```swift
@objc var evaluationEnvironments: [String]? { get set }
```

> **Deprecated:** Use evaluationContexts instead. This property will continue to work but will be removed in a future version.

Deprecated alias for `evaluationContexts`.

##### Discussion

- Deprecated: Use `evaluationContexts` instead. This property will be removed in a future version.

#### `PostHogConfig.featureFlagRequestMaxRetries`

```swift
@objc var featureFlagRequestMaxRetries: Int
```

Maximum number of retries for feature flag requests after transient network errors or retryable HTTP responses. Defaults to 1. Set to 0 to disable feature flag request retries.

#### `PostHogConfig.flushAt`

```swift
@objc var flushAt: Int
```

Number of queued events that triggers an automatic flush.

##### Discussion

Lower values send data sooner but can increase battery and network usage. Default: `20` (`5` on tvOS).

#### `PostHogConfig.flushIntervalSeconds`

```swift
@objc var flushIntervalSeconds: TimeInterval
```

Interval, in seconds, between periodic queue flush checks.

##### Discussion

Lower values deliver events closer to real time but can increase battery usage. Default: `30`.

#### `PostHogConfig.getAnonymousId`

```swift
@objc var getAnonymousId: ((UUID) -> UUID)
```

Hook used to customize newly generated anonymous IDs.

##### Parameters

- `uuid`: The SDK-generated anonymous UUID.

##### Return Value

The UUID to persist as the anonymous ID.

##### Discussion

The SDK passes its generated UUID v7 and stores the UUID returned by this closure. Existing stored anonymous IDs are not regenerated.

#### `PostHogConfig.host`

```swift
@objc let host: URL
```

PostHog ingestion host used for all SDK network requests.

##### Discussion

Defaults to `PostHogConfig.defaultHost` when the initializer host is empty or invalid.

#### `PostHogConfig.logs`

```swift
@objc let logs: PostHogLogsConfig
```

Configuration for the logs subsystem (manual `captureLog` capture). Mutate fields on `config.logs` before calling `PostHogSDK.setup(_:)`.

#### `PostHogConfig.maxBatchSize`

```swift
@objc var maxBatchSize: Int
```

Maximum number of events included in a single batch request.

##### Discussion

Default: `50`.

#### `PostHogConfig.maxQueueSize`

```swift
@objc var maxQueueSize: Int
```

Maximum number of events kept in the on-disk queue before older events are dropped.

##### Discussion

Default: `1000` (`100` on tvOS).

#### `PostHogConfig.maxRetries`

```swift
@objc var maxRetries: Int
```

Maximum number of retries for push-subscription registration failures.

##### Discussion

This limit does not apply to event, replay, or log ingestion. Retryable ingestion failures retain queued records for later flush triggers, subject to backoff. Use `maxQueueSize` for events and replay, and `logs.maxBufferSize` for logs.

Default: `3`.

#### `PostHogConfig.optOut`

```swift
@objc var optOut: Bool
```

Starts the SDK in an opted-out state when set before setup.

##### Discussion

While opted out, capture calls are ignored and integrations are not installed. Use `PostHogSDK.optIn()` and `PostHogSDK.optOut()` to change the persisted state at runtime. A state persisted by an earlier launch wins over this value, unless `reset()` cleared it or opt-out persistence is turned off. Default: `false`.

#### `PostHogConfig.personProfiles`

```swift
@objc var personProfiles: PostHogPersonProfiles
```

Determines the behavior for processing user profiles.

#### `PostHogConfig.preloadFeatureFlags`

```swift
@objc var preloadFeatureFlags: Bool
```

Whether feature flags are loaded automatically during SDK setup.

##### Discussion

The preload is started automatically during `setup()` and is **not** ordered against anything your app does after `setup()`. In particular it can go out before a `setPersonPropertiesForFlags(...)` call, in which case the first `/flags` response is evaluated without those overrides and an early flag read can see the pre-override value until the reload triggered by that call lands. See `setPersonPropertiesForFlags(_:reloadFeatureFlags:)` for the ordering contract and how to wait for flags evaluated with your overrides.

Default: `true`.

#### `PostHogConfig.projectToken`

```swift
@objc let projectToken: String
```

Your PostHog project token.

##### Discussion

You can find it at: https://us.posthog.com/settings/project-details#variables

This field was formerly named `apiKey`.

#### `PostHogConfig.propertiesSanitizer`

```swift
@objc var propertiesSanitizer: PostHogPropertiesSanitizer? { get set }
```

> **Deprecated:** Use beforeSend instead

Hook that allows to sanitize the event properties The hook is called before the event is cached or sent over the wire

#### `PostHogConfig.pushIdentityProvider`

```swift
@objc var pushIdentityProvider: ((_ distinctId: String, _ appId: String, _ completion: @escaping (String?) -> Void) -> Void)?
```

Supplies a signed identity token to attach (as `identity_token`) to push subscription register/unregister requests, for projects that enable identity verification on their push integration. Invoked with the `distinct_id` and `app_id` the request carries; call `completion` **exactly once**, from any thread, with a token minted by your backend — or `nil` to send the request without one. The SDK never mints tokens itself: your backend signs an HS256 JWT with the project’s **secret** API key, claims `sub` = distinct id, `app_id`, `aud` = “posthog:push_identity”, and an `exp`.

##### Discussion

The token is cached in memory per `(distinctId, appId)` and re-requested on identity change, on the next launch, and once after a 401 rejection. If `completion` isn’t called within ~10s the SDK stops waiting and sends the request without an identity token; where your project requires identity verification the backend will likely reject it, so make sure your provider always completes.

The hook is invoked on a background queue that serializes push-registration work — never on the calling thread — and `completion` may be called from any thread. Still return promptly: blocking here stalls the SDK’s push retry/offline-resume flow (though not your app’s main thread).

Default: `nil` (requests carry no identity token).

#### `PostHogConfig.rageClickConfig`

```swift
@objc let rageClickConfig: PostHogRageClickConfig
```

Rage click detection configuration.

#### `PostHogConfig.remoteConfig`

```swift
@objc var remoteConfig: Bool { get set }
```

> **Deprecated:** Remote config is now always loaded. This option is a no-op and will be removed in a future version.

Deprecated no-op for remote config loading.

##### Discussion

Remote config is now always loaded; setting this property has no effect.

- Deprecated: Remote config is always loaded. This option will be removed in a future version.

#### `PostHogConfig.requestHeaders`

```swift
@objc var requestHeaders: [String : String]?
```

Custom headers to send with every request to the PostHog API. Useful for reverse-proxy setups that require authentication, e.g. an `Authorization` header. Read once when the SDK is set up; changes after setup are ignored.

#### `PostHogConfig.reuseAnonymousId`

```swift
@objc var reuseAnonymousId: Bool
```

Flag to reuse the anonymous Id between `reset()` and next `identify()` calls

##### Discussion

If enabled, the anonymous Id will be reused for all anonymous users on this device, essentially creating a “Guest user Id” as long as this option is enabled.

Note: Events captured *before* call to *identify()* won’t be linked to the identified user Events captured *after*  call to *reset()* won’t be linked to the identified user

Defaults to false.

#### `PostHogConfig.sendFeatureFlagEvent`

```swift
@objc var sendFeatureFlagEvent: Bool
```

Whether feature flag lookups automatically capture `$feature_flag_called` events.

##### Discussion

Individual lookup calls can override this value with their `sendFeatureFlagEvent` parameter. Default: `true`.

#### `PostHogConfig.sessionReplay`

```swift
@objc var sessionReplay: Bool
```

Enable Recording of Session Replays for iOS

##### Discussion

Note: Ingestion controls (sampling, feature flags, and event triggers) are currently applied using AND logic. All configured conditions must be satisfied for recording to start.

Default: false

#### `PostHogConfig.sessionReplayConfig`

```swift
@objc let sessionReplayConfig: PostHogSessionReplayConfig
```

Session Replay configuration

#### `PostHogConfig.setDefaultPersonProperties`

```swift
@objc var setDefaultPersonProperties: Bool
```

Automatically set common device and app properties as person properties for feature flag evaluation.

##### Discussion

When enabled, the SDK will automatically set the following person properties:

- $app_version: App version from bundle

- $app_build: App build number from bundle

- $app_namespace: App bundle identifier

- $os_name: Operating system name (iOS, macOS, etc.)

- $os_version: Operating system version

- $device_type: Device type (Mobile, Tablet, Desktop, etc.)

- $lib: SDK name

- $lib_version: SDK version

This helps ensure feature flags that rely on these properties work correctly without waiting for server-side processing of identify() calls.

Default: true

#### `PostHogConfig.snapshotEndpoint`

```swift
@objc var snapshotEndpoint: String
```

Session replay snapshot endpoint path.

##### Discussion

> **Warning:** This value is managed by the SDK from remote configuration and should not be changed by application code.

#### `PostHogConfig.storageManager`

```swift
var storageManager: PostHogStorageManager?
```

Storage manager used by this configuration.

##### Discussion

> **Warning:** This is an SDK extension point used internally to share identity storage with SDK integrations and tests. Application code should not normally replace it.

#### `PostHogConfig.surveys`

```swift
@objc var surveys: Bool { get set }
```

Enable mobile surveys

##### Discussion

Default: true

Note: Event triggers will only work with the instance that first enables surveys. In case of multiple instances, please make sure you are capturing events on the instance that has config.surveys = true

#### `PostHogConfig.surveysConfig`

```swift
@objc var surveysConfig: PostHogSurveysConfig { get set }
```

Configuration for mobile survey presentation and localization.

##### Discussion

Mutate fields on `config.surveysConfig` or replace this object before calling setup. Available on iOS 15 and later.

#### `PostHogConfig.tracingHeaders`

```swift
@objc var tracingHeaders: [String]?
```

When set, PostHog injects tracing headers into `URLSession` requests whose destination hostname exactly matches one of the configured hostnames.

##### Discussion

Injected headers on iOS:

- `X-POSTHOG-DISTINCT-ID`

- `X-POSTHOG-SESSION-ID`

Notes:

- Requires `enableSwizzling = true`

- Hostname matching is exact and does not include ports or subdomain wildcards

- iOS does not send `X-POSTHOG-WINDOW-ID` because mobile apps do not have a per-window/tab concept

- Existing values for these headers will be overwritten

#### `PostHogConfig.urlSessionConfiguration`

```swift
@objc var urlSessionConfiguration: URLSessionConfiguration?
```

Optional custom URLSessionConfiguration for network requests If not set, uses URLSessionConfiguration.default Useful for testing, proxying, or custom network configurations

#### `PostHogConfig.setBeforeSend(_:)`

```swift
func setBeforeSend(_ blocks: BeforeSendBlock...)
```

Replaces the event `beforeSend` chain with the provided blocks.

##### Parameters

- `blocks`: Ordered callbacks that can mutate or drop events.

```swift
func setBeforeSend(_ blocks: [BeforeSendBlock])
```

Replaces the event `beforeSend` chain with the provided blocks.

##### Parameters

- `blocks`: Ordered callbacks that can mutate or drop events.

##### Discussion

Blocks run synchronously in array order before an event is cached or sent. Returning `nil` from any block drops the event and skips the remaining blocks.

#### `PostHogConfig.defaultHost`

```swift
static let defaultHost: String
```

Default PostHog ingestion host for US Cloud projects.

##### Discussion

Use `"https://eu.i.posthog.com"` for EU Cloud projects.

#### `PostHogConfig.PostHogConfig.PostHogDataMode`

```swift
@frozen @objc(PostHogDataMode) enum PostHogDataMode
```

Network connectivity mode required before queued data may be flushed.

### `PostHogDisplayChoiceQuestion`

```swift
@objc class PostHogDisplayChoiceQuestion
```

Represents a multiple or single choice question where users can select one or more options

#### `PostHogDisplayChoiceQuestion.choices`

```swift
let choices: [String]
```

The list of options for the user to choose from

#### `PostHogDisplayChoiceQuestion.hasOpenChoice`

```swift
let hasOpenChoice: Bool
```

Whether the question includes an “other” option for users to input free-form text

#### `PostHogDisplayChoiceQuestion.isMultipleChoice`

```swift
let isMultipleChoice: Bool
```

Whether the user can select multiple options

#### `PostHogDisplayChoiceQuestion.shuffleOptions`

```swift
let shuffleOptions: Bool
```

Whether the options should be shuffled to randomize the order

#### `PostHogDisplayChoiceQuestion.skipSubmitButton`

```swift
let skipSubmitButton: Bool
```

Whether selection should submit automatically for single-choice questions without an open choice

### `PostHogDisplayLinkQuestion`

```swift
@objc class PostHogDisplayLinkQuestion
```

Represents a question with a clickable link

#### `PostHogDisplayLinkQuestion.link`

```swift
let link: String?
```

The URL that will be opened when the link is clicked

### `PostHogDisplayOpenQuestion`

```swift
@objc class PostHogDisplayOpenQuestion
```

Represents an open-ended question where users can input free-form text

### `PostHogDisplayRatingQuestion`

```swift
@objc class PostHogDisplayRatingQuestion
```

Represents a rating question where users can select a rating from a scale

#### `PostHogDisplayRatingQuestion.lowerBoundLabel`

```swift
let lowerBoundLabel: String
```

The label for the lower bound of the rating scale

#### `PostHogDisplayRatingQuestion.ratingType`

```swift
let ratingType: PostHogDisplaySurveyRatingType
```

The type of rating scale (numbers, emoji)

#### `PostHogDisplayRatingQuestion.scaleLowerBound`

```swift
let scaleLowerBound: Int
```

The lower bound of the rating scale

#### `PostHogDisplayRatingQuestion.scaleUpperBound`

```swift
let scaleUpperBound: Int
```

The upper bound of the rating scale

#### `PostHogDisplayRatingQuestion.skipSubmitButton`

```swift
let skipSubmitButton: Bool
```

Whether selecting a rating submits the answer without a submit button

#### `PostHogDisplayRatingQuestion.upperBoundLabel`

```swift
let upperBoundLabel: String
```

The label for the upper bound of the rating scale

### `PostHogDisplaySurvey`

```swift
@objc class PostHogDisplaySurvey
```

A model representing a PostHog survey to be displayed to users

#### `PostHogDisplaySurvey.appearance`

```swift
let appearance: PostHogDisplaySurveyAppearance?
```

Optional appearance configuration for customizing the survey’s look and feel

#### `PostHogDisplaySurvey.endDate`

```swift
let endDate: Date?
```

Optional date indicating when the survey should stop being shown

#### `PostHogDisplaySurvey.id`

```swift
let id: String
```

Unique identifier for the survey

#### `PostHogDisplaySurvey.initialQuestionIndex`

```swift
let initialQuestionIndex: Int
```

The question to show when restoring an unfinished survey. Zero for a new survey.

#### `PostHogDisplaySurvey.name`

```swift
let name: String
```

Name of the survey

#### `PostHogDisplaySurvey.questions`

```swift
let questions: [PostHogDisplaySurveyQuestion]
```

Array of questions to be presented in the survey

#### `PostHogDisplaySurvey.startDate`

```swift
let startDate: Date?
```

Optional date indicating when the survey should start being shown

### `PostHogDisplaySurveyAppearance`

```swift
@objc class PostHogDisplaySurveyAppearance
```

Model that describes the appearance customization of a PostHog survey

#### `PostHogDisplaySurveyAppearance.backgroundColor`

```swift
let backgroundColor: String?
```

Optional background color as web color (e.g. “#FFFFFF” or “white”)

#### `PostHogDisplaySurveyAppearance.borderColor`

```swift
let borderColor: String?
```

Optional border color as web color

#### `PostHogDisplaySurveyAppearance.descriptionTextColor`

```swift
let descriptionTextColor: String?
```

Optional color for description text as web color

#### `PostHogDisplaySurveyAppearance.displayIntroScreen`

```swift
let displayIntroScreen: Bool
```

Whether to show an intro screen before the first question

#### `PostHogDisplaySurveyAppearance.displayThankYouMessage`

```swift
let displayThankYouMessage: Bool
```

Whether to show a thank you message after survey completion

#### `PostHogDisplaySurveyAppearance.fontFamily`

```swift
let fontFamily: String?
```

Optional font family to use throughout the survey

#### `PostHogDisplaySurveyAppearance.inputBackground`

```swift
let inputBackground: String?
```

Optional background color for input fields as web color

#### `PostHogDisplaySurveyAppearance.inputTextColor`

```swift
let inputTextColor: String?
```

Optional text color for input fields as web color

#### `PostHogDisplaySurveyAppearance.introScreenButtonText`

```swift
let introScreenButtonText: String?
```

Optional text for the button that advances past the intro screen

#### `PostHogDisplaySurveyAppearance.introScreenDescription`

```swift
let introScreenDescription: String?
```

Optional description text for the intro screen

#### `PostHogDisplaySurveyAppearance.introScreenDescriptionContentType`

```swift
let introScreenDescriptionContentType: PostHogDisplaySurveyTextContentType?
```

Optional content type for the intro screen description

#### `PostHogDisplaySurveyAppearance.introScreenHeader`

```swift
let introScreenHeader: String?
```

Optional header text for the intro screen

#### `PostHogDisplaySurveyAppearance.placeholder`

```swift
let placeholder: String?
```

Optional placeholder text for input fields

#### `PostHogDisplaySurveyAppearance.ratingButtonActiveColor`

```swift
let ratingButtonActiveColor: String?
```

Optional color for active/selected rating buttons as web color

#### `PostHogDisplaySurveyAppearance.ratingButtonColor`

```swift
let ratingButtonColor: String?
```

Optional color for rating buttons as web color

#### `PostHogDisplaySurveyAppearance.submitButtonColor`

```swift
let submitButtonColor: String?
```

Optional background color for the submit button as web color

#### `PostHogDisplaySurveyAppearance.submitButtonText`

```swift
let submitButtonText: String?
```

Optional custom text for the submit button

#### `PostHogDisplaySurveyAppearance.submitButtonTextColor`

```swift
let submitButtonTextColor: String?
```

Optional text color for the submit button as web color

#### `PostHogDisplaySurveyAppearance.surveyPopupDelaySeconds`

```swift
let surveyPopupDelaySeconds: TimeInterval?
```

Optional delay in seconds before showing the survey

#### `PostHogDisplaySurveyAppearance.textColor`

```swift
let textColor: String?
```

Optional primary text color as web color (for questions, close button, etc.)

#### `PostHogDisplaySurveyAppearance.thankYouMessageCloseButtonText`

```swift
let thankYouMessageCloseButtonText: String?
```

Optional text for the close button in the thank you message

#### `PostHogDisplaySurveyAppearance.thankYouMessageDescription`

```swift
let thankYouMessageDescription: String?
```

Optional description text for the thank you message

#### `PostHogDisplaySurveyAppearance.thankYouMessageDescriptionContentType`

```swift
let thankYouMessageDescriptionContentType: PostHogDisplaySurveyTextContentType?
```

Optional content type for the thank you message description

#### `PostHogDisplaySurveyAppearance.thankYouMessageHeader`

```swift
let thankYouMessageHeader: String?
```

Optional header text for the thank you message

### `PostHogDisplaySurveyQuestion`

```swift
@objc class PostHogDisplaySurveyQuestion
```

Base class for all survey question types

#### `PostHogDisplaySurveyQuestion.buttonText`

```swift
@objc let buttonText: String?
```

Optional custom text for the question’s action button

#### `PostHogDisplaySurveyQuestion.id`

```swift
@objc let id: String
```

The question ID, empty if none

#### `PostHogDisplaySurveyQuestion.isOptional`

```swift
@objc let isOptional: Bool
```

Whether the question can be skipped

#### `PostHogDisplaySurveyQuestion.question`

```swift
@objc let question: String
```

The main question text to display

#### `PostHogDisplaySurveyQuestion.questionDescription`

```swift
@objc let questionDescription: String?
```

Optional additional description or context for the question

#### `PostHogDisplaySurveyQuestion.questionDescriptionContentType`

```swift
@objc let questionDescriptionContentType: PostHogDisplaySurveyTextContentType
```

Content type for the question description (HTML or plain text)

### `PostHogErrorTrackingConfig`

```swift
@objc class PostHogErrorTrackingConfig
```

Configuration for error tracking and exception capture.

#### Overview

This class controls how exceptions are captured and processed, including which stack trace frames are marked as “in-app” code.

#### `PostHogErrorTrackingConfig.init()`

```swift
override init()
```

Creates an error tracking configuration with default in-app frame detection.

#### `PostHogErrorTrackingConfig.autoCapture`

```swift
@objc var autoCapture: Bool { get set }
```

Whether crash autocapture is enabled.

##### Discussion

When enabled, fatal crashes are persisted and sent as `$exception` events on the next launch. Default: `false`.

#### `PostHogErrorTrackingConfig.exceptionSteps`

```swift
@objc var exceptionSteps: PostHogExceptionStepsConfig
```

Configuration for exception steps (breadcrumb-style context records).

##### Discussion

Steps recorded via `PostHogSDK.addExceptionStep(_:properties:)` accumulate over the run and are attached to every captured `$exception` as `$exception_steps`, giving the error tracking UI a timeline of recent activity before each error.

#### `PostHogErrorTrackingConfig.ignoredExceptionTypes`

```swift
@objc var ignoredExceptionTypes: [String]
```

Exception types to drop instead of sending them as `$exception` events.

##### Discussion

Applies to every `$exception` event, including crash autocapture and `captureException(_:)`. An exception is dropped when any entry in its `$exception_list` has a `type` (for an `NSException`, its `name`) that exactly matches a value in this list. Matching is case-sensitive.

```swift
config.errorTrackingConfig.ignoredExceptionTypes = ["MyCustomException"]
```

Default: `[]`.

#### `PostHogErrorTrackingConfig.inAppByDefault`

```swift
@objc var inAppByDefault: Bool
```

Configures whether stack trace frames are considered in-app by default when the origin cannot be determined or no explicit includes/excludes match.

##### Discussion

- If `true` (default): Frames are in-app unless explicitly excluded (allowlist approach)

- If `false`: Frames are external unless explicitly included (denylist approach)

**Default behavior when true:**

- Known system frameworks (Foundation, UIKit, etc.) are excluded

- All other packages are in-app unless in `inAppExcludes`

**Precedence:** Priority 4 (final fallback)

Default: true

#### `PostHogErrorTrackingConfig.inAppExcludes`

```swift
@objc var inAppExcludes: [String]
```

List of package/bundle identifiers to be excluded from in-app frames

##### Discussion

Frames matching these prefixes will be marked as not in-app, unless they also match `inAppIncludes` (which takes precedence).

Example:

```swift
config.errorTrackingConfig.inAppExcludes = [
    "Alamofire",
    "SDWebImage"
]
```

**Precedence:** Priority 2 (after inAppIncludes)

#### `PostHogErrorTrackingConfig.inAppIncludes`

```swift
@objc var inAppIncludes: [String]
```

List of package/bundle identifiers to be considered in-app frames

##### Discussion

Takes precedence over `inAppExcludes`. If a frame’s module matches any prefix in this list, it will be marked as in-app.

Example:

```swift
config.errorTrackingConfig.inAppIncludes = [
    "MyApp",
    "SharedUtils"
]
```

**Default behavior:**

- Automatically includes main bundle identifier

- Automatically includes executable name

**Precedence:** Priority 1 (highest)

### `PostHogEvent`

```swift
@objc(PostHogEvent) class PostHogEvent
```

Event object passed through `BeforeSendBlock` before it is queued.

#### Overview

Mutate fields in your before-send callback to redact or enrich the event, or return `nil` from the callback to drop it. Instances are created by the SDK; application code normally captures events through `PostHogSDK.capture` instead of constructing this type.

#### `PostHogEvent.distinctId`

```swift
@objc var distinctId: String
```

Distinct ID associated with the event.

#### `PostHogEvent.event`

```swift
@objc var event: String
```

Event name, such as `"user_signed_up"` or `"$screen"`.

#### `PostHogEvent.properties`

```swift
@objc var properties: [String : Any]
```

Event properties that will be serialized with the event.

#### `PostHogEvent.timestamp`

```swift
@objc var timestamp: Date
```

Event timestamp. The absolute instant is serialized in UTC, regardless of the calendar or time zone used to create it.

#### `PostHogEvent.uuid`

```swift
@objc var uuid: UUID { get }
```

Unique event identifier generated by the SDK.

### `PostHogExceptionStepsConfig`

```swift
@objc class PostHogExceptionStepsConfig
```

Configuration for exception steps (breadcrumb-style context records).

#### Overview

Steps accumulate in a FIFO buffer bounded by a UTF-8 byte budget and are attached to every captured `$exception`. On a fatal crash they are persisted with the crash context and attached to the crash `$exception` on the next launch.

#### `PostHogExceptionStepsConfig.enabled`

```swift
@objc var enabled: Bool
```

Whether exception steps are recorded and attached to exceptions.

##### Discussion

When `false`, `addExceptionStep(_:properties:)` is a no-op and no steps are attached.

Default: `true`.

#### `PostHogExceptionStepsConfig.maxBytes`

```swift
@objc var maxBytes: Int
```

Maximum total UTF-8 byte size of the buffered steps.

##### Discussion

When adding a step would exceed this budget, the oldest steps are evicted first. A single step larger than the budget is rejected outright.

Default: `32768` (32 KB).

### `PostHogFeatureFlagResult`

```swift
@objc(PostHogFeatureFlagResult) class PostHogFeatureFlagResult
```

Result object containing all information about a feature flag evaluation.

#### Overview

This class provides access to the flag’s enabled state, variant, and payload in a single convenient object.

#### Example Usage

```swift
if let result = PostHogSDK.shared.getFeatureFlagResult("my-feature") {
    if result.enabled {
        // Feature is enabled
        if let variant = result.variant {
            // Handle specific variant
            print("Variant: \(variant)")
        }
        if let payload = result.payload as? [String: Any] {
            // Use the payload data
        }
    }
}
```

#### `PostHogFeatureFlagResult.enabled`

```swift
@objc let enabled: Bool
```

Whether the feature flag is enabled.

##### Discussion

This is `true` if the flag value is:

- A boolean `true`

- A non-null string (variant)

#### `PostHogFeatureFlagResult.key`

```swift
@objc let key: String
```

The key of the feature flag.

#### `PostHogFeatureFlagResult.payload`

```swift
@objc let payload: Any?
```

The payload associated with this feature flag, if any.

##### Discussion

The payload can be any JSON-serializable value (string, number, boolean, array, or dictionary).

#### `PostHogFeatureFlagResult.variant`

```swift
@objc let variant: String?
```

The variant name if this is a multivariate flag, otherwise `nil`.

#### `PostHogFeatureFlagResult.payloadAs(_:)`

```swift
func payloadAs<T>(_ type: T.Type) -> T? where T : Decodable
```

Returns the payload deserialized as the specified Decodable type.

##### Parameters

- `type`: The type to decode the payload as

##### Return Value

The payload as type T, or nil if the payload is nil or decoding fails

##### Discussion

If the payload is already an instance of T, returns it directly. Otherwise, attempts to serialize to JSON and decode.

### `PostHogFeatureFlagsLoaded`

```swift
@objc(PostHogFeatureFlagsLoaded) final class PostHogFeatureFlagsLoaded
```

The feature flags passed to an `onFeatureFlags` callback.

#### Example Usage

```swift
let subscription = PostHogSDK.shared.onFeatureFlags { loaded in
    if loaded.errorsLoading {
        // The values are the last known (cached) flags
    }
    if loaded.variants["new-checkout"] as? String == "test" {
        // Show the test variant
    }
}

// Later, stop listening
subscription.unsubscribe()
```

#### `PostHogFeatureFlagsLoaded.errorsLoading`

```swift
@objc let errorsLoading: Bool
```

`true` if the latest attempt to load feature flags failed.

##### Discussion

When it did, `flags` and `variants` hold the last known values, which can be empty.

#### `PostHogFeatureFlagsLoaded.flags`

```swift
@objc let flags: [String]
```

The keys of the enabled feature flags.

#### `PostHogFeatureFlagsLoaded.variants`

```swift
@objc let variants: [String : Any]
```

The values of the enabled feature flags, keyed by flag key.

##### Discussion

A value is `true` for an enabled boolean flag, or the variant `String` for a multivariate flag. Disabled flags are not included.

### `PostHogFeatureFlagsSubscription`

```swift
@objc(PostHogFeatureFlagsSubscription) final class PostHogFeatureFlagsSubscription
```

A registration returned by `PostHogSDK.onFeatureFlags(_:)`.

#### Overview

The callback stays registered until you call `unsubscribe()`. You don’t need to keep a reference to this object unless you want to unsubscribe later.

#### `PostHogFeatureFlagsSubscription.unsubscribe()`

```swift
@objc func unsubscribe()
```

Stops the callback from being invoked. Calling it more than once has no effect.

### `PostHogLogEntry`

```swift
@objc class PostHogLogEntry
```

A model representing a processed console log entry for session replay.

#### Overview

Describes a single console log entry after it has been processed by `PostHogSessionReplayConsoleLogConfig.logSanitizer`. Each instance contains the log message content and its determined severity level.

#### `PostHogLogEntry.init(level:message:)`

```swift
@objc init(level: PostHogLogLevel, message: String)
```

Creates a new console log entry.

##### Parameters

- `level`: The severity level of the log entry
- `message`: The processed log message content

#### `PostHogLogEntry.level`

```swift
@objc let level: PostHogLogLevel
```

The severity level of the log entry. This determines how the log will be displayed in the session replay and whether it will be captured based on `minLogLevel` setting.

#### `PostHogLogEntry.message`

```swift
@objc let message: String
```

The actual content of the log message. This is the processed and sanitized log message

### `PostHogLogRecord`

```swift
@objc final class PostHogLogRecord
```

A captured log entry passed to your `beforeSend` callback. Mutate the fields below to redact, enrich, or rewrite the record; return `nil` to drop it.

#### Overview

Instances are created by the SDK at capture time. Mutations made after the callback returns have no effect — the record is encoded into the on-disk queue as soon as `beforeSend` finishes.

#### `PostHogLogRecord.attributes`

```swift
@objc var attributes: [String : Any]
```

Free-form attributes attached to this record. Values must be JSON-serializable (`String`, `Int`, `Double`, `Bool`, arrays/dicts of the same, `NSNumber`); anything else is silently dropped at flush time. Use this to add structured context (request ids, build numbers, experiment buckets) or to remove keys you don’t want sent.

##### Discussion

**From ObjC**: bridges to an immutable `NSDictionary`. To mutate, take a `mutableCopy`, edit it, and assign back to the property — in-place mutation on the returned dictionary will fail.

#### `PostHogLogRecord.body`

```swift
@objc var body: String
```

The log message body. Required; empty bodies are dropped at capture time.

#### `PostHogLogRecord.distinctId`

```swift
@objc var distinctId: String?
```

PostHog distinct id of the user at capture time, or `nil` if no user is identified. Set to `nil` (or to a hash) to redact.

#### `PostHogLogRecord.featureFlagKeys`

```swift
@objc var featureFlagKeys: [String]
```

Feature flag keys that were active at capture time. Empty when no flags are loaded. Useful for correlating logs with experiment cohorts; clear or filter to redact.

##### Discussion

**From ObjC**: bridges to an immutable `NSArray`. Replace the property to mutate; in-place mutation will fail.

#### `PostHogLogRecord.level`

```swift
@objc var level: PostHogLogSeverity
```

Severity of the log entry. Reassign to re-classify (e.g. demote a noisy `.warn` to `.debug`).

#### `PostHogLogRecord.screenName`

```swift
@objc var screenName: String?
```

Last screen name observed by automatic screen-view tracking, or `nil` if screen tracking is disabled or no screen has been seen yet. Set to `nil` (or rewrite) to redact navigation context.

#### `PostHogLogRecord.sessionId`

```swift
@objc var sessionId: String?
```

PostHog session id at capture time, or `nil` if no session is active. Set to `nil` to disassociate the record from the session.

#### `PostHogLogRecord.spanId`

```swift
@objc var spanId: String?
```

W3C span id (16 hex characters) if this log belongs to a span. `nil` when no span is active.

#### `PostHogLogRecord.traceFlags`

```swift
@objc var traceFlags: NSNumber?
```

W3C trace flags. Lower 8 bits are the bitfield; bit 0 is the `sampled` flag. `nil` omits the field on the wire; `0` explicitly emits zero.

#### `PostHogLogRecord.traceId`

```swift
@objc var traceId: String?
```

W3C trace id (32 hex characters) if you’ve correlated this log with a distributed trace. `nil` when no trace context is associated. Set or rewrite for tracing integrations.

### `PostHogLogger`

```swift
@objc final class PostHogLogger
```

Convenience facade for capturing log records. Use `PostHogSDK.shared.logger` to call `trace`, `debug`, `info`, `warn`, `error`, or `fatal`.

#### `PostHogLogger.debug(_:)`

```swift
@objc(debugWithBody:) func debug(_ body: String)
```

Capture a `.debug` record. Diagnostic detail useful during development.

##### Parameters

- `body`: The log message. Required and non-empty.

#### `PostHogLogger.debug(_:attributes:)`

```swift
@objc(debugWithBody:attributes:) func debug(_ body: String, attributes: [String : Any]? = nil)
```

Capture a `.debug` record with structured attributes.

##### Parameters

- `body`: The log message. Required and non-empty.
- `attributes`: Per-record attributes. Values must be JSON-serializable.

#### `PostHogLogger.error(_:)`

```swift
@objc(errorWithBody:) func error(_ body: String)
```

Capture an `.error` record. An operation failed; the app may continue.

##### Parameters

- `body`: The log message. Required and non-empty.

#### `PostHogLogger.error(_:attributes:)`

```swift
@objc(errorWithBody:attributes:) func error(_ body: String, attributes: [String : Any]? = nil)
```

Capture an `.error` record with structured attributes.

##### Parameters

- `body`: The log message. Required and non-empty.
- `attributes`: Per-record attributes. Values must be JSON-serializable.

#### `PostHogLogger.fatal(_:)`

```swift
@objc(fatalWithBody:) func fatal(_ body: String)
```

Capture a `.fatal` record. An unrecoverable failure; the app likely cannot continue.

##### Parameters

- `body`: The log message. Required and non-empty.

#### `PostHogLogger.fatal(_:attributes:)`

```swift
@objc(fatalWithBody:attributes:) func fatal(_ body: String, attributes: [String : Any]? = nil)
```

Capture a `.fatal` record with structured attributes.

##### Parameters

- `body`: The log message. Required and non-empty.
- `attributes`: Per-record attributes. Values must be JSON-serializable.

#### `PostHogLogger.info(_:)`

```swift
@objc(infoWithBody:) func info(_ body: String)
```

Capture an `.info` record. Default level for regular runtime events.

##### Parameters

- `body`: The log message. Required and non-empty.

#### `PostHogLogger.info(_:attributes:)`

```swift
@objc(infoWithBody:attributes:) func info(_ body: String, attributes: [String : Any]? = nil)
```

Capture an `.info` record with structured attributes.

##### Parameters

- `body`: The log message. Required and non-empty.
- `attributes`: Per-record attributes. Values must be JSON-serializable.

#### `PostHogLogger.trace(_:)`

```swift
@objc(traceWithBody:) func trace(_ body: String)
```

Capture a `.trace` record. Finest-grained detail; usually only enabled while diagnosing.

##### Parameters

- `body`: The log message. Required and non-empty.

#### `PostHogLogger.trace(_:attributes:)`

```swift
@objc(traceWithBody:attributes:) func trace(_ body: String, attributes: [String : Any]? = nil)
```

Capture a `.trace` record with structured attributes.

##### Parameters

- `body`: The log message. Required and non-empty.
- `attributes`: Per-record attributes. Values must be JSON-serializable.

#### `PostHogLogger.warn(_:)`

```swift
@objc(warnWithBody:) func warn(_ body: String)
```

Capture a `.warn` record. Something unexpected happened but the operation continued.

##### Parameters

- `body`: The log message. Required and non-empty.

#### `PostHogLogger.warn(_:attributes:)`

```swift
@objc(warnWithBody:attributes:) func warn(_ body: String, attributes: [String : Any]? = nil)
```

Capture a `.warn` record with structured attributes.

##### Parameters

- `body`: The log message. Required and non-empty.
- `attributes`: Per-record attributes. Values must be JSON-serializable.

### `PostHogLogsConfig`

```swift
@objc final class PostHogLogsConfig
```

Configuration for the PostHog logs subsystem. Mutate fields on `config.logs` before calling `PostHogSDK.setup(_:)`.

#### `PostHogLogsConfig.init()`

```swift
override init()
```

Creates a logs configuration with default queueing, resource, and rate-cap options.

#### `PostHogLogsConfig.environment`

```swift
@objc var environment: String?
```

OpenTelemetry `deployment.environment` resource attribute. Omitted from the payload when nil. Set before `PostHogSDK.setup(_:)`; later mutations are ignored.

#### `PostHogLogsConfig.flushAt`

```swift
@objc var flushAt: Int
```

Threshold at which the queue triggers a flush automatically. Smaller than `maxBatchSize` lets the queue fire smaller batches on a steady cadence rather than waiting for the full cap.

#### `PostHogLogsConfig.flushIntervalSeconds`

```swift
@objc var flushIntervalSeconds: TimeInterval
```

How often the queue checks for records to flush. Set before `PostHogSDK.setup(_:)`; later mutations are ignored.

#### `PostHogLogsConfig.maxBatchSize`

```swift
@objc var maxBatchSize: Int
```

Initial maximum number of records sent in a single request. May be reduced under server backpressure.

#### `PostHogLogsConfig.maxBufferSize`

```swift
@objc var maxBufferSize: Int
```

Maximum number of records held on disk. When full, the oldest record is dropped (FIFO).

#### `PostHogLogsConfig.rateCapMaxLogs`

```swift
@objc var rateCapMaxLogs: Int
```

Maximum number of records accepted per `rateCapWindowSeconds`. Set to `0` (or any non-positive value) to disable the cap. Set before `PostHogSDK.setup(_:)`; later mutations are ignored.

#### `PostHogLogsConfig.rateCapWindowSeconds`

```swift
@objc var rateCapWindowSeconds: TimeInterval
```

Tumbling window in seconds used by the rate cap. Must be positive; non-positive values disable the cap. Set before `PostHogSDK.setup(_:)`; later mutations are ignored.

#### `PostHogLogsConfig.resourceAttributes`

```swift
@objc var resourceAttributes: [String : Any]
```

Additional OpenTelemetry resource attributes attached to every batch. SDK-managed keys (`telemetry.sdk.*`, `os.*`, `service.name`) win on key collision so users can’t shadow them. Set before `PostHogSDK.setup(_:)`; later mutations are ignored.

##### Discussion

**From ObjC**: bridges to an immutable `NSDictionary`. Replace the property to change it; in-place mutation on the returned dictionary will fail.

#### `PostHogLogsConfig.serviceName`

```swift
@objc var serviceName: String
```

OpenTelemetry `service.name` resource attribute. Defaults to the host app’s bundle identifier. Set before `PostHogSDK.setup(_:)`; later mutations are ignored.

#### `PostHogLogsConfig.serviceVersion`

```swift
@objc var serviceVersion: String
```

OpenTelemetry `service.version` resource attribute. Defaults to the host app’s `CFBundleShortVersionString`, or empty if unavailable. Empty values are omitted from the wire payload. Set before `PostHogSDK.setup(_:)`; later mutations are ignored.

#### `PostHogLogsConfig.setBeforeSend(_:)`

```swift
func setBeforeSend(_ blocks: [PostHogBeforeSendLogBlock])
```

Replaces the log `beforeSend` chain with the provided blocks.

##### Parameters

- `blocks`: Ordered callbacks that can mutate or drop log records.

##### Discussion

Blocks run synchronously in array order before a log is enqueued. Returning `nil` from any block drops the log and skips the remaining blocks.

```swift
func setBeforeSend(_ blocks: PostHogBeforeSendLogBlock...)
```

Replaces the log `beforeSend` chain with the provided blocks.

##### Parameters

- `blocks`: Ordered callbacks that can mutate or drop log records.

### `PostHogNextSurveyQuestion`

```swift
@objc class PostHogNextSurveyQuestion
```

A model representing the next state of the survey progression.

#### `PostHogNextSurveyQuestion.isSurveyCompleted`

```swift
let isSurveyCompleted: Bool
```

Whether all questions have been answered and the survey is complete Depending on the survey appearance configuration, you may want to show the “Thank you” message or dismiss the survey at this point

#### `PostHogNextSurveyQuestion.questionIndex`

```swift
let questionIndex: Int
```

The index of the next question to be displayed (0-based)

### `PostHogRageClickConfig`

```swift
@objc(PostHogRageClickConfig) class PostHogRageClickConfig
```

Configuration for iOS/macCatalyst rage click autocapture.

#### Overview

Rage click detection captures `$rageclick` when a user rapidly taps the same area.

#### `PostHogRageClickConfig.enabled`

```swift
@objc var enabled: Bool
```

Enable rage click detection for iOS/macCatalyst.

##### Discussion

When enabled, rapid taps in the same area will be captured as `$rageclick` events. Works independently of `captureElementInteractions` — you can enable rage click detection without enabling full autocapture.

Default: true

#### `PostHogRageClickConfig.minimumTapCount`

```swift
@objc var minimumTapCount: Int
```

Number of consecutive taps within the threshold to qualify as a rage click.

##### Discussion

Default: 3

#### `PostHogRageClickConfig.thresholdPoints`

```swift
@objc var thresholdPoints: CGFloat
```

Manhattan distance threshold in logical points.

##### Discussion

Taps within this distance from the previous tap are considered “in the same area”. Uses Manhattan distance: `|x1 - x2| + |y1 - y2|`.

Default: 30

#### `PostHogRageClickConfig.timeoutInterval`

```swift
@objc var timeoutInterval: TimeInterval
```

Maximum time interval between consecutive taps to count as part of the same sequence.

##### Discussion

If more than this interval passes between two taps, the sequence resets.

Default: 1.0 (seconds)

### `PostHogSessionManager`

```swift
@objc class PostHogSessionManager
```

Manages the active PostHog session ID and session rotation state.

#### Overview

> **Warning:** This class is public for backwards compatibility, but is intended for SDK-internal use only. Application code should use `PostHogSDK.getSessionId()`, `startSession()`, and `endSession()` instead of interacting with this manager directly.

#### `PostHogSessionManager.setSessionId(_:)`

```swift
@objc func setSessionId(_ sessionId: String)
```

> **Deprecated:** PostHogSessionManager becomes SDK-internal in PostHog 4.0. Use PostHogSDK.shared.getSessionId(), startSession() and endSession() instead. From 4.0, wrapper SDKs must import PostHog with @_spi(PostHogInternal) to use it.

Overrides the current session ID.

##### Parameters

- `sessionId`: Session ID to use for subsequent events.

##### Discussion

Use with care: changing the session ID affects analytics session attribution and session replay.

#### `PostHogSessionManager.shared`

```swift
@objc static var shared: PostHogSessionManager { get }
```

> **Deprecated:** PostHogSessionManager becomes SDK-internal in PostHog 4.0. Use PostHogSDK.shared.getSessionId(), startSession() and endSession() instead. From 4.0, wrapper SDKs must import PostHog with @_spi(PostHogInternal) to use it.

Session manager used by `PostHogSDK.shared`.

### `PostHogSessionReplayConfig`

```swift
@objc(PostHogSessionReplayConfig) class PostHogSessionReplayConfig
```

Configuration for iOS session replay capture.

#### Overview

Mutate fields on `config.sessionReplayConfig` before calling `PostHogSDK.setup(_:)`.

#### `PostHogSessionReplayConfig.captureLogs`

```swift
@objc var captureLogs: Bool
```

Enable capturing console output for session replay.

##### Discussion

When enabled, logs from the following sources will be captured:

- Standard output (stdout)

- Standard error (stderr)

- OSLog messages

- NSLog messages

Each log entry will be tagged with a level (info/warning/error) based on the message content and the source.

Defaults to `false`

Note: When enabled, can be disabled remotely via project settings (requires `PostHogConfig.remoteConfig` to be enabled)

#### `PostHogSessionReplayConfig.captureLogsConfig`

```swift
@objc var captureLogsConfig: PostHogSessionReplayConsoleLogConfig
```

Further configuration for capturing console output

#### `PostHogSessionReplayConfig.captureNetworkTelemetry`

```swift
@objc var captureNetworkTelemetry: Bool
```

Enable capturing network telemetry Default: true

##### Discussion

Note: When enabled, can be disabled remotely via project settings (requires `PostHogConfig.remoteConfig` to be enabled)

#### `PostHogSessionReplayConfig.captureTouches`

```swift
@objc var captureTouches: Bool
```

Enable recording touch coordinates in session replay. Screenshot capture is unaffected. Set before SDK setup. Runtime changes are not supported. Default: true

#### `PostHogSessionReplayConfig.debouncerDelay`

```swift
@objc var debouncerDelay: TimeInterval { get set }
```

> **Deprecated:** Deprecated in favor of 'throttleDelay' which provides identical functionality. Will be removed in the next major release.

Debouncer delay used to reduce the number of snapshots captured and reduce performance impact This is used for capturing the view as a wireframe or screenshot The lower the number more snapshots will be captured but higher the performance impact Defaults to 1s

#### `PostHogSessionReplayConfig.maskAllImages`

```swift
@objc var maskAllImages: Bool
```

Enable masking of all images to a placeholder Default: true

#### `PostHogSessionReplayConfig.maskAllSandboxedViews`

```swift
@objc var maskAllSandboxedViews: Bool
```

Enable masking of all sandboxed system views These may include UIImagePickerController, PHPickerViewController and CNContactPickerViewController Default: true

#### `PostHogSessionReplayConfig.maskAllTextInputs`

```swift
@objc var maskAllTextInputs: Bool
```

Enable masking of all text and text input fields Default: true

#### `PostHogSessionReplayConfig.maskPhotoLibraryImages`

```swift
@objc var maskPhotoLibraryImages: Bool
```

> **Deprecated:** This property has no effect and will be removed in the next major release. To learn how to manually mask user photos please see our Privacy controls documentation: https://posthog.com/docs/session-replay/privacy?tab=iOS

Deprecated placeholder for photo-library image masking.

##### Discussion

This property has no effect. To manually mask user photos, see the privacy controls documentation: https://posthog.com/docs/session-replay/privacy?tab=iOS

Default: `false`.

#### `PostHogSessionReplayConfig.sampleRate`

```swift
@objc var sampleRate: NSNumber? { get set }
```

Session recording sample rate, between 0.0 and 1.0.

##### Discussion

1.0 means every session will be recorded, 0.0 means no sessions will be recorded. Sampling is deterministic based on the session ID, so the same session will always produce the same sampling decision.

When set, takes precedence over the remote config sample rate. When `nil`, the remote config sample rate is used (if available), otherwise all sessions are recorded.

Values outside the 0.0–1.0 range are ignored and treated as `nil`.

Defaults to `nil`

#### `PostHogSessionReplayConfig.screenshotMode`

```swift
@objc var screenshotMode: Bool
```

By default Session replay will capture all the views on the screen as a wireframe, By enabling this option, PostHog will capture the screenshot of the screen. The screenshot may contain sensitive information, use with caution. Default: false

#### `PostHogSessionReplayConfig.screenshotModeBackgroundCapture`

```swift
@objc var screenshotModeBackgroundCapture: Bool
```

Schedule screenshot image capture on a background queue when `screenshotMode` is enabled.

##### Discussion

Warning: Enabling this option will trigger Main Thread Checker warnings and may briefly freeze the app the first time a screenshot is captured. Consider disabling Main Thread Checker in your scheme’s run diagnostics when enabling this.

Experimental. Default: false

#### `PostHogSessionReplayConfig.screenshotScale`

```swift
@objc var screenshotScale: NSNumber? { get set }
```

Resolution of `screenshotMode` screenshots, as a multiplier of the screen’s native resolution.

##### Discussion

- `nil`: one pixel per point on every device, so a 402×874 pt screen uploads 402×874 pixels.

- A value: that fraction of native resolution. On a 3x device, `1.0` uploads 1206×2622 pixels (native) and `0.5` uploads 603×1311 (1.5 pixels per point).

Values are clamped to 0.1…1.0, and NaN or infinite values reset it to `nil`. The replay’s viewport in points is unchanged. Does not affect wireframe mode or compression quality. Exposed as `NSNumber` so Objective-C can leave it unset.

Experimental. Default: nil (one pixel per point)

#### `PostHogSessionReplayConfig.throttleDelay`

```swift
@objc var throttleDelay: TimeInterval
```

Throttle delay used to reduce the number of snapshots captured and reduce performance impact This is used for capturing the view as a wireframe or screenshot The lower the number more snapshots will be captured but higher the performance impact Defaults to 1s

##### Discussion

Note: Previously `debouncerDelay`

### `PostHogSessionReplayConsoleLogConfig`

```swift
@objc class PostHogSessionReplayConsoleLogConfig
```

Configuration for console log capture inside session replay recordings.

#### Overview

Used when `PostHogSessionReplayConfig.captureLogs` is enabled.

#### `PostHogSessionReplayConsoleLogConfig.logSanitizer`

```swift
@objc var logSanitizer: ((String) -> PostHogLogEntry?)
```

Block to process and format captured console output for session replay.

##### Parameters

- `output`: The raw console output to process.

##### Return Value

A `PostHogLogEntry` to capture, or `nil` to skip the log output.

##### Discussion

This block is called whenever console output is captured. It allows you to:

1. Filter or modify log messages before they are sent to session replay

1. Determine the appropriate log level (info/warn/error) for each message

1. Format, sanitize, or skip log messages (e.g. remove sensitive data or PII)

The default implementation:

- Detect log level (best effort)

- Process OSLog messages to remove metadata

#### `PostHogSessionReplayConsoleLogConfig.minLogLevel`

```swift
@objc var minLogLevel: PostHogLogLevel
```

The minimum log level to capture in session replay. Only log messages with this level or higher will be captured. For example, if set to `.warn`:

##### Discussion

- `.error` messages will be captured

- `.warn` messages will be captured

- `.info` messages will be skipped

Defaults to `.error` to minimize noise in session replays.

### `PostHogStorageManager`

```swift
class PostHogStorageManager
```

Manages persisted identity metadata for a PostHog SDK instance.

#### Overview

> **Warning:** This class is public for backwards compatibility, but is intended for SDK-internal use only. Application code should use `PostHogSDK` identity APIs instead of interacting with storage directly.

#### `PostHogStorageManager.getAnonymousId()`

```swift
func getAnonymousId() -> String
```

Returns the persisted anonymous ID, creating one if needed.

##### Return Value

The anonymous ID for this install.

#### `PostHogStorageManager.getDeviceId()`

```swift
func getDeviceId() -> String
```

Returns the stable device identifier used for device-level feature flag bucketing.

##### Return Value

The stable device ID for this install.

##### Discussion

This ID persists across `identify()` and `reset()` calls, only changing on a fresh app install or manual cache clearing.

#### `PostHogStorageManager.getDistinctId()`

```swift
func getDistinctId() -> String
```

Returns the persisted distinct ID, falling back to the anonymous ID.

##### Return Value

The current distinct ID.

#### `PostHogStorageManager.isIdentified()`

```swift
func isIdentified() -> Bool
```

Returns whether the current distinct ID is identified.

##### Return Value

`true` after a successful identify flow, otherwise `false`.

#### `PostHogStorageManager.isPersonProcessing()`

```swift
func isPersonProcessing() -> Bool
```

Returns whether person profile processing has been enabled locally.

##### Return Value

`true` when identified/person processing has been activated.

#### `PostHogStorageManager.reset(keepAnonymousId:_:)`

```swift
func reset(keepAnonymousId: Bool = false, _ resetStorage: Bool = false)
```

Clears cached identity metadata and optionally removes persisted values.

##### Parameters

- `keepAnonymousId`: Whether to keep the current anonymous ID cached and persisted.
- `resetStorage`: Whether to remove values from the backing store as well as memory.

#### `PostHogStorageManager.setAnonymousId(_:)`

```swift
func setAnonymousId(_ id: String)
```

Persists an anonymous ID.

##### Parameters

- `id`: Anonymous ID to store.

#### `PostHogStorageManager.setDistinctId(_:)`

```swift
func setDistinctId(_ id: String)
```

Persists the current distinct ID.

##### Parameters

- `id`: Distinct ID to store.

#### `PostHogStorageManager.setIdentified(_:)`

```swift
func setIdentified(_ isIdentified: Bool)
```

Persists whether the current distinct ID is identified.

##### Parameters

- `isIdentified`: New identified state.

#### `PostHogStorageManager.setPersonProcessing(_:)`

```swift
func setPersonProcessing(_ enable: Bool)
```

Persists whether person profile processing is enabled locally.

##### Parameters

- `enable`: New person-processing state.

### `PostHogSurveyResponse`

```swift
@objc @objcMembers class PostHogSurveyResponse
```

A model representing a user’s response to a survey question

#### `PostHogSurveyResponse.linkClicked`

```swift
let linkClicked: Bool?
```

Whether a link was clicked (for link questions)

#### `PostHogSurveyResponse.ratingValue`

```swift
let ratingValue: Int?
```

The numeric rating value (for rating questions)

#### `PostHogSurveyResponse.selectedOptions`

```swift
let selectedOptions: [String]?
```

The selected options (for multiple or single choice questions)

#### `PostHogSurveyResponse.textValue`

```swift
let textValue: String?
```

The text response (for open questions)

#### `PostHogSurveyResponse.type`

```swift
let type: PostHogSurveyResponseType
```

The response kind: link, rating, open-ended, single-choice, or multiple-choice.

#### `PostHogSurveyResponse.link(_:)`

```swift
static func link(_ clicked: Bool) -> PostHogSurveyResponse
```

Creates a response for a link question.

##### Parameters

- `clicked`: Whether the link was clicked.

##### Return Value

A response with type `.link` and `linkClicked` populated.

#### `PostHogSurveyResponse.multipleChoice(_:)`

```swift
static func multipleChoice(_ multipleChoice: [String]?) -> PostHogSurveyResponse
```

Creates a response for a multiple-choice question.

##### Parameters

- `multipleChoice`: The selected options.

##### Return Value

A response with type `.multipleChoice` and `selectedOptions` populated.

#### `PostHogSurveyResponse.openEnded(_:)`

```swift
static func openEnded(_ openEnded: String?) -> PostHogSurveyResponse
```

Creates a response for an open-ended question.

##### Parameters

- `openEnded`: The text response.

##### Return Value

A response with type `.openEnded` and `textValue` populated.

#### `PostHogSurveyResponse.rating(_:)`

```swift
static func rating(_ rating: Int?) -> PostHogSurveyResponse
```

Creates a response for a rating question.

##### Parameters

- `rating`: The selected rating value.

##### Return Value

A response with type `.rating` and `ratingValue` populated.

#### `PostHogSurveyResponse.singleChoice(_:)`

```swift
static func singleChoice(_ singleChoice: String?) -> PostHogSurveyResponse
```

Creates a response for a single-choice question.

##### Parameters

- `singleChoice`: The selected option.

##### Return Value

A response with type `.singleChoice` and `selectedOptions` containing the option when non-nil.

### `PostHogSurveysConfig`

```swift
@objc class PostHogSurveysConfig
```

Configuration for mobile survey rendering.

#### Overview

Mutate fields on `PostHogConfig.surveysConfig` before SDK setup to customize survey UI, lifecycle handling, or localization.

#### `PostHogSurveysConfig.overrideDisplayLanguage`

```swift
@objc var overrideDisplayLanguage: String?
```

Optional explicit override for the language used when rendering surveys.

##### Discussion

When set, surveys with matching entries in `translations` will be rendered in this language regardless of the device locale or any `language` person property.

Format: a language tag such as `"fr"`, `"pt-BR"`, `"zh-CN"`. Matching is case-insensitive and falls back to the base language (e.g. `"pt"` if `"pt-BR"` is requested but only `"pt"` is provided).

Blank or `nil` values are treated as unset.

Default: `nil`.

#### `PostHogSurveysConfig.surveysDelegate`

```swift
var surveysDelegate: PostHogSurveysDelegate
```

Delegate responsible for managing survey presentation in your app. Handles survey rendering, response collection, and lifecycle events. You can provide your own delegate for a custom survey presentation.

##### Discussion

Defaults to `PostHogSurveysDefaultDelegate` which provides a standard survey UI.

### `PostHogPropertiesSanitizer`

```swift
@objc(PostHogPropertiesSanitizer) protocol PostHogPropertiesSanitizer
```

Protocol to sanitize the event properties

#### `PostHogPropertiesSanitizer.sanitize(_:)`

```swift
@objc func sanitize(_ properties: [String : Any]) -> [String : Any]
```

Sanitizes the event properties

##### Parameters

- `properties`: The event properties to sanitize

##### Return Value

The sanitized properties

##### Discussion

> **Note:** `inout` cannot be used in Swift protocols, so clone the properties before mutating them.

```swift
private class ExampleSanitizer: PostHogPropertiesSanitizer {
    public func sanitize(_ properties: [String: Any]) -> [String: Any] {
        var sanitizedProperties = properties
        // Perform sanitization
        // For example, removing keys with empty values
        for (key, value) in properties {
            if let stringValue = value as? String, stringValue.isEmpty {
                sanitizedProperties.removeValue(forKey: key)
            }
        }
        return sanitizedProperties
    }
}
```

### `PostHogSurveysDelegate`

```swift
@objc protocol PostHogSurveysDelegate
```

Delegate used by the SDK to present surveys and receive survey lifecycle callbacks.

#### `PostHogSurveysDelegate.supportsSurveyResume`

```swift
@objc optional var supportsSurveyResume: Bool { get }
```

Whether this delegate can resume unfinished surveys. Defaults to `false` when omitted.

##### Discussion

Return `true` only if the renderer starts at `survey.initialQuestionIndex`. The SDK restores the saved answers and submission ID for that attempt. Delegates that omit this property or return `false` start a fresh attempt at question 0.

For example, a renderer that supports the restored position can opt in with:

```swift
var supportsSurveyResume: Bool { true }
// In renderSurvey, initialize the renderer at survey.initialQuestionIndex.
```

#### `PostHogSurveysDelegate.cleanupSurveys()`

```swift
@objc func cleanupSurveys()
```

Called when surveys are stopped to clean up any UI elements and reset the survey display state. This method should handle the dismissal of any active surveys and cleanup of associated resources.

#### `PostHogSurveysDelegate.renderSurvey(_:onSurveyShown:onSurveyResponse:onSurveyClosed:)`

```swift
@objc func renderSurvey(_ survey: PostHogDisplaySurvey, onSurveyShown: @escaping OnPostHogSurveyShown, onSurveyResponse: @escaping OnPostHogSurveyResponse, onSurveyClosed: @escaping OnPostHogSurveyClosed)
```

Called when an activated PostHog survey needs to be rendered on the app’s UI Delegates that opt in through `supportsSurveyResume` must start at `survey.initialQuestionIndex` to resume an unfinished survey.

##### Parameters

- `survey`: The survey to be displayed to the user
- `onSurveyShown`: To be called when the survey is successfully displayed to the user.
- `onSurveyResponse`: Call when the user submits a response to a question; use the returned state to advance or complete the survey.
- `onSurveyClosed`: To be called when the survey is dismissed

#### `PostHogSurveysDelegate.updateSurvey(_:)`

```swift
@objc optional func updateSurvey(_ survey: PostHogDisplaySurvey)
```

Called when the content of the currently displayed survey changes without restarting it, for example when the user’s language is updated and a new translation becomes available.

##### Parameters

- `survey`: The survey with refreshed (e.g. re-translated) content. Its `id` matches the survey passed to `renderSurvey`.

##### Discussion

Implementations should update the on-screen survey in place — preserving the current question, progress, and any in-progress answers — rather than presenting it again. Optional: delegates that don’t support live updates can omit it and the survey simply keeps the language it was first rendered with.

Always delivered on the main thread. May arrive *before* the survey is visibly shown — e.g. while a display delay (`surveyPopupDelaySeconds`) is still pending — so a delegate that defers presentation must also apply the update to its pending survey, otherwise the update is dropped and the survey shows the language it was first resolved with.

### `BeforeSendBlock`

```swift
typealias BeforeSendBlock = (PostHogEvent) -> PostHogEvent?
```

Callback invoked before an event is persisted or sent.

#### Parameters

- `event`: The event about to be queued.

#### Return Value

The event to queue, or `nil` to drop it.

#### Discussion

Return the event (mutated or unchanged) to continue processing, or `nil` to drop it. Blocks run synchronously on the capture caller’s thread and compose in registration order.

### `OnPostHogSurveyClosed`

```swift
typealias OnPostHogSurveyClosed = (_ survey: PostHogDisplaySurvey) -> Void
```

To be called when a survey is dismissed

#### Parameters

- `survey`: The survey that was closed

### `OnPostHogSurveyResponse`

```swift
typealias OnPostHogSurveyResponse = (_ survey: PostHogDisplaySurvey, _ index: Int, _ response: PostHogSurveyResponse) -> PostHogNextSurveyQuestion?
```

To be called when a user responds to a survey question

#### Parameters

- `survey`: The current survey being displayed
- `index`: The index of the question being answered
- `response`: The user’s response to the question

#### Return Value

The next survey state, or `nil` if the attempt is no longer valid. The built-in renderer closes an invalidated survey.

### `OnPostHogSurveyShown`

```swift
typealias OnPostHogSurveyShown = (_ survey: PostHogDisplaySurvey) -> Void
```

To be called when a survey is successfully shown to the user

#### Parameters

- `survey`: The survey that was displayed

### `PostHogBeforeSendLogBlock`

```swift
typealias PostHogBeforeSendLogBlock = (PostHogLogRecord) -> PostHogLogRecord?
```

A `beforeSend` callback gets one chance to mutate or drop a log record before it is enqueued. Returning `nil` drops the record; mutating the record’s `body` to an empty string also drops it. Multiple blocks compose left-to-right; if any returns `nil`, later blocks are skipped. Runs synchronously on the thread that called `captureLog`.

#### Parameters

- `record`: The log record about to be queued.

#### Return Value

The record to queue, or `nil` to drop it.

### `PostHogCompression`

```swift
@objc(PostHogCompression) enum PostHogCompression
```

How the SDK compresses request bodies before sending them to the PostHog API.

#### `PostHogCompression.PostHogCompression.gzip`

```swift
case gzip
```

Gzip request bodies. If gzipping fails on device, the body is sent uncompressed.

#### `PostHogCompression.PostHogCompression.none`

```swift
case none
```

Send request bodies uncompressed, with no `Content-Encoding` header.

### `PostHogDisplaySurveyRatingType`

```swift
@objc enum PostHogDisplaySurveyRatingType
```

Type of rating display for survey rating questions

#### `PostHogDisplaySurveyRatingType.PostHogDisplaySurveyRatingType.emoji`

```swift
case emoji
```

Display emoji rating options

#### `PostHogDisplaySurveyRatingType.PostHogDisplaySurveyRatingType.number`

```swift
case number
```

Display numeric rating options

### `PostHogDisplaySurveyTextContentType`

```swift
@objc enum PostHogDisplaySurveyTextContentType
```

Content type for text-based survey elements

#### `PostHogDisplaySurveyTextContentType.PostHogDisplaySurveyTextContentType.html`

```swift
case html
```

Content should be rendered as HTML

#### `PostHogDisplaySurveyTextContentType.PostHogDisplaySurveyTextContentType.text`

```swift
case text
```

Content should be rendered as plain text

### `PostHogLogLevel`

```swift
@objc enum PostHogLogLevel
```

The severity level of a console log entry.

#### Overview

Used to categorize logs by their severity in session replay.

#### `PostHogLogLevel.PostHogLogLevel.error`

```swift
case error
```

Error messages indicating failures or critical issues

#### `PostHogLogLevel.PostHogLogLevel.info`

```swift
case info
```

Informational messages, debugging output, and general logs

#### `PostHogLogLevel.PostHogLogLevel.warn`

```swift
case warn
```

Warning messages indicating potential issues or deprecation notices

### `PostHogLogSeverity`

```swift
@objc enum PostHogLogSeverity
```

Severity level for a captured log record sent to PostHog’s logs ingestion.

#### Overview

Cases are declared in severity order so `>=` comparisons on the raw value give the expected result from both Swift and ObjC. ObjC consumers can safely write `if (severity >= PostHogLogSeverityWarn) { ... }` when `severity` is a `PostHogLogSeverity` value.

Maps to OpenTelemetry severity numbers (`TRACE=1`, `DEBUG=5`, `INFO=9`, `WARN=13`, `ERROR=17`, `FATAL=21`) for the OTLP wire format.

#### `PostHogLogSeverity.PostHogLogSeverity.debug`

```swift
case debug
```

Diagnostic information useful while debugging.

#### `PostHogLogSeverity.PostHogLogSeverity.error`

```swift
case error
```

Error messages indicating failures or critical issues.

#### `PostHogLogSeverity.PostHogLogSeverity.fatal`

```swift
case fatal
```

An unrecoverable failure; the app likely cannot continue.

#### `PostHogLogSeverity.PostHogLogSeverity.info`

```swift
case info
```

Informational messages and general logs.

#### `PostHogLogSeverity.PostHogLogSeverity.trace`

```swift
case trace
```

Finest-grained tracing detail.

#### `PostHogLogSeverity.PostHogLogSeverity.warn`

```swift
case warn
```

Warning messages indicating potential issues or deprecation notices.

### `PostHogPersonProfiles`

```swift
@objc(PostHogPersonProfiles) enum PostHogPersonProfiles
```

Determines the behavior for processing user profiles.

#### Overview

- `never`: We won’t process persons for any event. This means that anonymous users will not be merged once they sign up or login, so you lose the ability to create funnels that track users from anonymous to identified. All events (including `$identify`) will be sent with `$process_person_profile: False`.

- `always`: We will process persons data for all events.

- `identifiedOnly`: (default): we will only process persons when you call `identify`, `alias`, and `group`, Anonymous users won’t get person profiles.

#### `PostHogPersonProfiles.PostHogPersonProfiles.always`

```swift
case always
```

Always process person profiles for all events.

#### `PostHogPersonProfiles.PostHogPersonProfiles.identifiedOnly`

```swift
case identifiedOnly
```

Process person profiles only after `identify`, `alias`, or `group` creates one.

#### `PostHogPersonProfiles.PostHogPersonProfiles.never`

```swift
case never
```

Never process person profiles. All events are sent with `$process_person_profile: false`.

### `PostHogSurveyResponseType`

```swift
@objc enum PostHogSurveyResponseType
```

Type of response submitted for a survey question.

#### `PostHogSurveyResponseType.PostHogSurveyResponseType.link`

```swift
case link
```

Response for a link question.

#### `PostHogSurveyResponseType.PostHogSurveyResponseType.multipleChoice`

```swift
case multipleChoice
```

Response for a multiple-choice question.

#### `PostHogSurveyResponseType.PostHogSurveyResponseType.openEnded`

```swift
case openEnded
```

Response for an open-ended text question.

#### `PostHogSurveyResponseType.PostHogSurveyResponseType.rating`

```swift
case rating
```

Response for a rating question.

#### `PostHogSurveyResponseType.PostHogSurveyResponseType.singleChoice`

```swift
case singleChoice
```

Response for a single-choice question.
