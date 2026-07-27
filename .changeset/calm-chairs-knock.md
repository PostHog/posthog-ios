---
"posthog-ios": patch
---

Fix error tracking autocapture never installing on a first launch that has no cached remote config. The crash reporter now installs by default before the first `/config` response arrives, so crashes on the very first launch are captured. If the response then reports `autocaptureExceptions: false`, the integration is uninstalled and removed.
