---
"posthog-ios": patch
---

Fix error tracking integration not uninstalling when remote config disables autocapture

`stop()` is a no-op for crash reporters (by design — once registered, a crash handler cannot be deregistered). When remote config arrived with `autocaptureExceptions: false` after the integration was already installed, calling `stop()` left the integration in `installedIntegrations`, so `getErrorTrackingIntegration()` continued returning it.

Added `removeIntegration(_:)` to `PostHogSDK` which calls `uninstall()` and removes the integration from `installedIntegrations`. The `onRemoteConfigLoaded` callback now calls `postHog.removeIntegration(self)` instead of `self.stop()`.
