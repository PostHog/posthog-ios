---
"posthog-ios": patch
---

Send a session replay frame or touch with the session it was captured in, or drop it. On a busy device a frame or touch could be sent late under a newer session, or after recording stopped, and that session could miss its first full snapshot. A new session's first buffered snapshots are also no longer lost when the previous session's buffer is cleared.
