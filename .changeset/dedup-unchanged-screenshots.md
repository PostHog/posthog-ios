---
"posthog-ios": patch
---

Session replay (screenshot mode): skip re-sending unchanged screenshots. Static screens no longer upload an identical full screenshot every tick, cutting replay bandwidth and storage. Wireframe mode is unaffected.
