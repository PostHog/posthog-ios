---
'posthog-ios': patch
---

Fix `$screen_width` and `$screen_height` going stale when the app window resizes (foldables, Stage Manager, iPad split view), and report the window's actual size on rotation in orientation-locked apps.
