---
"posthog-ios": patch
---

Send a session replay frame with the session it was captured in, or drop it. On a busy device a frame could be sent late under a newer session, or after recording stopped, and that session could miss its first full snapshot.
