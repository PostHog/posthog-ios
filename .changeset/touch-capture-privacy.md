---
"posthog-ios": minor
---

Add `sessionReplayConfig.captureTouches` (default `true`) to disable recording touch coordinates during SDK initialization without disabling screenshots. This protects sensitive screens such as PIN keypads independently of screenshot masking. Runtime changes are not supported.
