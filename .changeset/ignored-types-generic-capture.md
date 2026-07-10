---
"posthog-ios": patch
---

Fix `errorTrackingConfig.ignoredExceptionTypes` not being applied to `$exception` events sent through the generic `capture()` API (e.g. hybrid SDK bridges forwarding pre-serialized exceptions); previously only `captureException` and crash-report autocapture honored it.
