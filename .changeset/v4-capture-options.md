---
'posthog-ios': minor
---

Add per-event capture options with `capture(..., timestamp:options:)` and `PostHogEvent.options`, which `beforeSend` can read and change. `screen`, `identify`, `setPersonProperties`, `alias`, `group` and `captureException` take the same `options` argument.
