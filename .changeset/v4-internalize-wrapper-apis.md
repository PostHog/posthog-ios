---
'posthog-ios': major
---

**Breaking:** hide SDK internals that were public only for PostHog's own wrapper SDKs.

Moved behind `@_spi(PostHogInternal)`. These are for PostHog's wrapper SDKs and carry no stability guarantees:

- `postHogSdkName` and `postHogVersion`
- `PostHogSessionManager`: use `PostHogSDK.getSessionId()`, `startSession()` and `endSession()`.
- `PostHogStorageManager` and `PostHogConfig.storageManager`: use the `PostHogSDK` identity methods such as `identify`, `getDistinctId()` and `reset()`.
- `PostHogConfig.snapshotEndpoint`
- `dateToMillis(_:)`: use `Int64(date.timeIntervalSince1970 * 1000)`.
- `imageToBase64(_:_:)`: no public replacement. It returned a WebP `data:` URI, or JPEG when WebP encoding failed.

No longer public:

- `toISO8601String(_:)`, `toISO8601Date(_:)`, `sanitizeDictionary(_:)`, `deleteSafely(_:)` and `postHogiOSSdkName`
- `Gzip`, `GzipError` and `CompressionLevel`
- `ReachabilityError`
- `UIColor.init(hex:)` and `UIColor.hexDescription(_:)`

`PostHogSessionManager.shared`, `PostHogSessionManager.setSessionId(_:)` and `PostHogConfig.snapshotEndpoint` are no longer exposed to Objective-C.
