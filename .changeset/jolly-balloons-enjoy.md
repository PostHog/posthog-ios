---
"posthog-ios": patch
---

Restart session replay on `optIn()` in a new session whenever the app wanted it on at `optOut()`: `sessionReplay` is enabled or the app called `startSessionRecording()`, and it didn't call `stopSessionRecording()` since. This includes a recording started with `sessionReplay` disabled and one held by an event trigger or sampling, which are checked again for the new session. Also keep integrations in step with consent when `optIn()` and `optOut()` run concurrently
