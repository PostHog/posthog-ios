---
'posthog-ios': minor
---

Deprecate APIs that PostHog 4.0 hides or removes, and announce iOS 15 as the minimum iOS version in 4.0.

Becoming SDK-internal in 4.0 (wrapper SDKs can keep using them by importing PostHog with `@_spi(PostHogInternal)`):

- `PostHogSessionManager.shared` and `setSessionId(_:)`: use `PostHogSDK.getSessionId()`, `startSession()` and `endSession()`.
- `dateToMillis(_:)` and `imageToBase64(_:_:)`

Removed from the public API in 4.0:

- `UIColor.hexDescription(_:)`

These also change in 4.0 but show no deprecation warning in 3.x, because the SDK uses them internally:

- Becoming SDK-internal: `postHogSdkName`, `postHogVersion`, `PostHogConfig.storageManager` and `PostHogConfig.snapshotEndpoint`.
- Removed from the public API: `toISO8601String(_:)`, `toISO8601Date(_:)`, `sanitizeDictionary(_:)`, `deleteSafely(_:)`, `postHogiOSSdkName`, `UIColor.init(hex:)`, `Gzip`, `GzipError`, `CompressionLevel` and `ReachabilityError`.

PostHog 4.0 raises the minimum iOS deployment target from 13.0 to 15.0. The macOS, tvOS, watchOS and visionOS minimums are unchanged.
