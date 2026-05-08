---
"posthog-ios": minor
---

Add a logs feature for shipping structured log records from iOS, macOS, tvOS, watchOS, and visionOS apps:

```swift
PostHogSDK.shared.captureLog("hello", level: .info, attributes: ["k": "v"])
PostHogSDK.shared.logger?.info("ready")
PostHogSDK.shared.flush()
```

Configure batching, rate limiting, service metadata, and a `beforeSend` filter via `config.logs`. Records are persisted to disk and survive app restarts. Manual capture only — console autocapture is not included.
