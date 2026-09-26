---
'posthog-ios': minor
---

Report out-of-memory terminations as `$exception` events on iOS 27 and later via MetricKit, when error tracking autocapture is enabled. Apps built with Xcode 26 or earlier don't include it.
