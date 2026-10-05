---
"posthog-ios": minor
---

Add the experimental `screenshotModeGPUCapture` session replay option, which renders screenshots on the GPU to cut the main-thread cost of each capture, and the experimental `screenshotScale` option, a multiplier of the native resolution like posthog-android's. Screenshots now default to one pixel per point, and masked and unmasked screenshots ship at the same size, so unmasked frames no longer upload at the native resolution.
