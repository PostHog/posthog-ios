---
'posthog-ios': major
---

**Breaking:** mark callbacks the SDK can call off the main thread `@Sendable` — `reloadFeatureFlags(_:)`, the `BeforeSendBlock` and `PostHogBeforeSendLogBlock` used by `setBeforeSend(_:)` on `PostHogConfig` and `PostHogLogsConfig`, `PostHogConfig.getAnonymousId`, `PostHogConfig.pushIdentityProvider` and its `completion`, and `sessionReplayConfig.captureLogsConfig.logSanitizer` — and make `PostHogFeatureFlagsLoaded` `Sendable`. This fixes a crash in Swift 6 apps when a `reloadFeatureFlags(_:)` callback is written in main-actor code.

To update main-actor state from `reloadFeatureFlags(_:)` or `pushIdentityProvider`, hop with `Task { @MainActor in ... }`. The other callbacks return a value immediately, so they must not read main-actor state. Declare closures you store in your own variables as `@Sendable` to avoid new Swift 5 warnings. Use the `BeforeSendBlock` and `PostHogBeforeSendLogBlock` typealiases for any `setBeforeSend(_:)` arrays you build or pass around, including your own helpers: in Swift 5 mode, converting an array between the old function type and these types compiles but crashes at runtime, in either direction.
