---
"posthog-ios": patch
---

Discard session replay screenshots while the system camera picker is open to avoid an iOS CameraUI layer-copy crash. Screenshot capture resumes after the camera is dismissed.
