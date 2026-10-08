---
"posthog-ios": patch
---

Fix `$exception` event metadata: link chained errors with `exception_id`/`parent_id`, cap the chain at 50 entries, add `$exception_source` to crash and out-of-memory reports, and stop `captureException` properties from overriding `$exception_list` and `$debug_images`
