---
"posthog-ios": patch
---

Make push subscription delivery more reliable: a queued logout DELETE is dropped when the same identity re-registers, so it can no longer cancel the fresh subscription.
