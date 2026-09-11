---
"posthog-ios": patch
---

- Preserve inherited session replay masking across siblings inside full-window `ph-no-capture` views.
- Keep collecting masks inside clipping views whose model frame reaches zero while their presentation bounds remain visible during an animation.
