---
'posthog-ios': patch
---

Stop session replay when the project is over its mobile session replay quota. The SDK now treats `quotaLimited: ["mobile_recordings"]` in remote config the same as `sessionRecording: false`.
