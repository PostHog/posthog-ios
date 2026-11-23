---
"posthog-ios": patch
---

Stop the main thread waiting for `setup()` when `/config` or `/flags` answers while integrations are still being installed
