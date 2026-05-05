---
"posthog-ios": minor
---

Add a logs feature for shipping structured log records to PostHog from iOS, macOS, tvOS, watchOS, and visionOS apps:

```swift
PostHog.shared.captureLog("hello", level: .info, attributes: ["k": "v"])
PostHog.shared.logger.info("ready")
PostHog.shared.flushLogs()
```

Configure via `config.logs.*`: `flushIntervalSeconds`, `maxBufferSize`, `maxBatchSize`, `serviceName`, `serviceVersion`, `environment`, `resourceAttributes`, `rateCapMaxLogs`, `rateCapWindowSeconds`, `beforeSend`. Records are persisted to disk (durable across app restarts), batched, and sent to `/i/v1/logs` in OTLP/HTTP JSON. The queue handles reachability (where available), exponential-backoff retry, HTTP 413 adaptive batch sizing, a `maxRetries` queue-wide drop safety net, a tumbling-window rate cap, and a `beforeSend` filter — all crash-safe and thread-safe from any caller. Console autocapture is intentionally not included; manual capture only.
