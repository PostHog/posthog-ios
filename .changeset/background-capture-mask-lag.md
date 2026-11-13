---
'posthog-ios': patch
---

With `screenshotModeBackgroundCapture` on, session replay masks drifting content over the position its pixels can trail to, and skips frames captured while the screen scrolls or animates, or while a masked cell is recycled, instead of uploading them with misaligned masks.
