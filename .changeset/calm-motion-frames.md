---
"posthog-ios": patch
---

Reduce main-thread hangs in screenshot-mode session replay during fast scrolls and animations. The motion renderer now draws at upload resolution instead of native screen resolution. After each motion render, the SDK skips motion frames for 19 times that render's duration, so the motion renderer uses at most about 5% of the main thread. Settled frames still capture as before.
