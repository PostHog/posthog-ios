---
'posthog-ios': major
---

**Breaking:** remove `version` and `build` from `Application Installed`, `Application Updated` and `Application Opened` events. Use `$app_version` and `$app_build` in insights and filters instead.
