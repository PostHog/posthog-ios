---
"posthog-ios": patch
---

Fix automatic screen names for custom view controller containers with a single visible child, excluding offscreen, empty, and fully clipped child views. Use titles for plain UIViewController screens instead of reporting "UI".
