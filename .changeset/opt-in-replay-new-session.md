---
"posthog-ios": patch
---

Start session replay in a new session when `optIn()` is called, and keep it stopped if the app had called `stopSessionRecording()` before `optOut()`
