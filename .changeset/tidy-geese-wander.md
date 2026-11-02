---
"posthog-ios": patch
---

Fix a crash in screenshot-mode session replay when a masked view sits under an app `CALayer` subclass, and keep cleared labels and replaced images masked until the screen updates.
