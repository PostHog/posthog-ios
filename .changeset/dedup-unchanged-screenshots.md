---
"posthog-ios": patch
---

Session replay (screenshot mode): skip re-sending an unchanged screenshot. When a screen is static, the throttle-driven capture would previously upload an identical full screenshot every tick; it now compares a hash of the encoded image and drops the duplicate (the player already holds the last frame), cutting replay bandwidth and storage for static screens. Wireframe mode is unaffected — it is already change-driven.
