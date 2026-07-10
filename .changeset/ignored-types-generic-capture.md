---
"posthog-ios": patch
---

fix: enforce `errorTrackingConfig.ignoredExceptionTypes` on the generic capture path

`$exception` events sent through the generic `capture(...)` overloads (e.g. hybrid
SDK bridges forwarding a pre-serialized `$exception_list`) bypassed the filter, which
only ran in `captureException` and the crash-report path. The check now lives in
`captureInternal`, the chokepoint every `$exception` path funnels through.
