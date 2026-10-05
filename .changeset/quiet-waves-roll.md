---
"posthog-ios": minor
---

Add the experimental `screenshotModeGPUCapture` session replay option, which renders screenshots on the GPU to cut the main-thread cost of each capture, and the experimental `screenshotScale` option, the pixels per point of every screenshot (default 1.0). Masked and unmasked screenshots now ship at the same size, so unmasked frames no longer upload at the screen's native resolution.
