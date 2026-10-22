---
"posthog-ios": patch
---

Stop exception autocapture from starting while the SDK is opted out, when a remote config that enables it arrives after `optOut()`. A later `optIn()` also no longer skips installing the other integrations.
