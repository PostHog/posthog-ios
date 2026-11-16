---
"posthog-ios": patch
---

Fix `captureException` stack traces starting in PostHog's own code instead of the line that called it when the SDK is statically linked into the app, such as with Swift Package Manager
