---
'posthog-ios': major
---

**Breaking:** mark callbacks the SDK can call off the main thread `@Sendable` — `reloadFeatureFlags(_:)`, the `BeforeSendBlock` and `PostHogBeforeSendLogBlock` used by `setBeforeSend(_:)` on `PostHogConfig` and `PostHogLogsConfig`, `getAnonymousId`, `pushIdentityProvider` and its `completion`, and `logSanitizer` — and make `PostHogFeatureFlagsLoaded` `Sendable`. This fixes a crash in Swift 6 apps when a `reloadFeatureFlags(_:)` callback is written in main-actor code.

To update main-actor state from `reloadFeatureFlags(_:)` or `pushIdentityProvider`, hop with `Task { @MainActor in ... }`. The other callbacks return a value immediately, so they must not read main-actor state. Declare closures you store in your own variables as `@Sendable` to avoid new Swift 5 warnings, and type pre-built `setBeforeSend(_:)` arrays as `[BeforeSendBlock]` or `[PostHogBeforeSendLogBlock]`: an array typed with the old function type crashes at runtime in Swift 5 mode.
