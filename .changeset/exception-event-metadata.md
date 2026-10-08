---
"posthog-ios": patch
---

Fix `$exception` event metadata: link chained errors with `exception_id`/`parent_id`, cap the chain at 50 entries, add `$exception_source` to crash and out-of-memory reports, and stop `captureException` properties from overriding `$exception_list`, `$exception_level`, `$exception_source` and `$debug_images`
