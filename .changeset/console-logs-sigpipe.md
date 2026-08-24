---
"posthog-ios": patch
---

Fix a fatal SIGPIPE when session replay console log capture is torn down, for example when the app backgrounds with `sessionReplayConfig.captureLogs` enabled. Teardown closed the descriptors the pipe readers were still writing to, which could kill the process.
