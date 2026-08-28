---
"posthog-ios": patch
---

Fix session replay masks drifting away from the content they cover while a screen scrolls or animates. During fast scrolling, frames are captured with a renderer that keeps masks aligned but draws blur, video and Metal content flat, and that also ignores `layer.mask`, `maskView` and CoreAnimation `filters` — content hidden by those alone is drawn in full in those frames. Use `postHogMask()` for anything that must never appear in a recording.
