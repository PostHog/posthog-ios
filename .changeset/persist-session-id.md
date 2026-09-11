---
'posthog-ios': patch
---

Persist the session id and its timestamps, so a session survives a process launch. An app that was killed while suspended now resumes the same session when the user comes back inside the 30 minute idle window, instead of starting a new one. `startSession()` also keeps a live session instead of always rotating, so an extra `setup()` or a background launch no longer splits the session.
