---
"posthog-ios": patch
---

Remember the app version and build when lifecycle capture is disabled, so enabling it on a later launch does not report a false Application Installed event or stale previous version. Also save version name changes when the build number stays the same, so the next Application Updated event reports the latest previous version.
