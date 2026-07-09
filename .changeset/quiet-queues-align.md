---
'posthog-ios': patch
---

Fix event-queue peek/pop misalignment that could re-send already-delivered events when a file was skipped, and stop deleting valid queue files that are only temporarily unreadable (e.g. iOS data protection on a locked device).
