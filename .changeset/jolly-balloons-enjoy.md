---
"posthog-ios": patch
---

Restart session replay on `optIn()` when the app had started recording with `startSessionRecording()` and `sessionReplay` disabled in config, and keep integrations in step with consent when `optIn()` and `optOut()` run concurrently
