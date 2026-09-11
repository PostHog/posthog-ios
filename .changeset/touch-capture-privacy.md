---
"posthog-ios": minor
---

Add `sessionReplayConfig.captureTouches` (default `true`) and `PostHogSDK.setCaptureTouches(_:)` to disable recording touch coordinates at runtime without stopping screenshots. Disabled capture skips touch collection and pending touch work on the replay queue, allowing wrapper SDKs to protect sensitive screens such as PIN keypads independently of screenshot masking.
