---
"posthog-ios": patch
---

A `beforeSend` hook that calls `reset()` or `identify()` no longer gives the event's `userProperties` to the next user's feature flag evaluation.
