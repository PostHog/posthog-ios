---
"posthog-ios": patch
---

Fix `sessionReplay = false` so remote config loads, event triggers and session changes no longer restart a recording the app stopped with `stopSessionRecording()`; a manual `startSessionRecording()` keeps recording into new sessions until the app stops it, matching Android
