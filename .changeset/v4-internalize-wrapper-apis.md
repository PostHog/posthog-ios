---
'posthog-ios': major
---

**Breaking:** hide SDK internals that were public only for PostHog's own wrapper SDKs.

Moved behind `@_spi(PostHogInternal)`. These are for PostHog's wrapper SDKs and carry no stability guarantees:

- `postHogSdkName` and `postHogVersion`
- `PostHogSessionManager`: use `PostHogSDK.getSessionId()`, `startSession()` and `endSession()`.
- `PostHogStorageManager` and `PostHogConfig.storageManager`: use the `PostHogSDK` identity methods such as `identify`, `getDistinctId()` and `reset()`.
- `PostHogConfig.snapshotEndpoint`
- `dateToMillis(_:)` and `imageToBase64(_:_:)`

No longer public:

- `toISO8601String(_:)`, `toISO8601Date(_:)`, `sanitizeDictionary(_:)`, `deleteSafely(_:)` and `postHogiOSSdkName`
- `Gzip`, `GzipError` and `CompressionLevel`
- `ReachabilityError`
- `UIColor.init(hex:)` and `UIColor.hexDescription(_:)`
