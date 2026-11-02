---
"posthog-ios": patch
---

Clear the session replay screenshot bitmap before drawing, so a failed or partial render can no longer upload leftover memory in a snapshot.
