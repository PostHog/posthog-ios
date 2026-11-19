---
"posthog-ios": patch
---

Reduce the main-thread cost of the screenshot-mode session replay mask walk by checking each view class for Compose Multiplatform once instead of on every capture.
