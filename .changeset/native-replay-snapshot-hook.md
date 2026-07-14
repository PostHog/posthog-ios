---
"posthog-ios": minor
---

Add `PostHogSDK.captureSessionReplaySnapshot(afterScreenUpdates:)`, an SPI session-replay hook (`@_spi(PostHogInternal)`) that lets first-party PostHog wrapper SDKs (e.g. posthog-flutter) capture the current native window on their own cadence — used to record native screens that cover an out-of-engine UI. Not a public API: it requires an `@_spi(PostHogInternal) import` and carries no stability guarantees.
