---
"posthog-ios": patch
---

Draw session replay screenshots in the screen's own color space, so a capture on a wide-gamut screen no longer converts every pixel on the main thread. The conversion now happens off the main thread on the replay queue: a resized or masked screenshot is redrawn in device RGB, and an image that reaches the WebP encoder in a wide gamut, such as a native-resolution screenshot with nothing to mask, is converted to sRGB. The WebP encoder is shared, so wide-gamut images in wireframe mode and from `imageToBase64` are converted to sRGB too, and upload in their true colors instead of having their Display P3 values read as sRGB. The JPEG fallback does not convert.
