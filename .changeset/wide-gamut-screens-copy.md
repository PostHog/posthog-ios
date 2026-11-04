---
"posthog-ios": patch
---

Draw session replay screenshots in the screen's own color space, so a capture on a wide-gamut screen no longer converts every pixel on the main thread. The screenshot is converted to sRGB off the main thread, when it is resized, masked, or encoded.
