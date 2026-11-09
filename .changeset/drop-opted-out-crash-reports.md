---
'posthog-ios': patch
---

A crash report written by the native crash reporter after `optOut()` is no longer sent as `$exception` after the next `optIn()`. The native crash handler cannot be removed once installed, so at opt-out the SDK replaces the crash context with an opted-out marker and drops a pending report that carries it. A crash recorded while opted in is still delivered after `optIn()`. Reports written by SDK versions before this change carry no marker and are still sent. Out-of-memory terminations reported through MetricKit on iOS 27 are not covered by this change.
