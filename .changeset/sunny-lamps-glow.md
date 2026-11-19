---
"posthog-ios": patch
---

Reduce main-thread time per GPU session replay capture by measuring a masked view's rect only when the capture paints that rect, instead of for every masked view during the mask walk.
