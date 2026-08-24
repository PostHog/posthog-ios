---
"posthog-ios": patch
---

Upload symbols under the app version reported by Info.plist, including custom build settings. Wait for the current dSYM and fail after a configurable timeout instead of uploading invalid symbols.
