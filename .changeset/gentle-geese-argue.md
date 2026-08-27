---
"posthog-ios": patch
---

Fix session replay masks drifting away from the content they cover while a screen scrolls or animates. During fast scrolling, frames are captured with a renderer that keeps masks aligned but draws blur, video and Metal content flat — use `postHogMask()` for anything that must never appear in a recording.
