---
'posthog-ios': major
---

**Breaking:** remove the experimental `PostHogSessionReplayConfig.screenshotModeBackgroundCapture` option. Delete the assignment. Screenshots are now always captured on the main thread, where rendering is fast enough that the off-main workaround is no longer needed.
