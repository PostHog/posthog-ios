---
"posthog-ios": minor
---

Fix `captureException` stack traces starting in PostHog's own code instead of the line that called it when the SDK is statically linked into the app, such as with Swift Package Manager. Errors sent with `captureException` from these apps are grouped into new issues after upgrading; crashes and events with a custom `$exception_fingerprint` are not affected
