---
"posthog-ios": patch
---

Split session replay uploads at session or distinct ID changes so queued snapshots retain their session and identity attribution. Send the boundary-separated groups within a flush's batch limit sequentially without waiting for another flush trigger.
