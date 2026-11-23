---
"posthog-ios": patch
---

Mask the text of a `CATextLayer` under a `postHogMask()` extent with `captureMethod = .gpu`. Its glyphs were uploaded readable.
