---
'posthog-ios': major
---

**Breaking:** remove the migration of the event queue written by SDK 2.x (`posthog.queue.plist`).

Events still queued on disk by a 2.x SDK are deleted instead of sent when the app updates straight from 2.x to 4.0. Distinct ID, anonymous ID, groups and cached feature flags are still carried over. Apps on any 3.x release are not affected.

Queued events are no longer read in the 2.x format: a top-level `$set` and `message_id` are ignored.
