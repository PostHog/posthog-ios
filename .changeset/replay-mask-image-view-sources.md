---
"posthog-ios": patch
---

Mask a `UIImageView` in session replay when any of its `image`, `highlightedImage`, `animationImages` or `highlightedAnimationImages` is not an SF Symbol or asset-catalog image. Before, only `image` was checked, so an animating or highlighted image view could be recorded unmasked even with `maskAllImages` on.
