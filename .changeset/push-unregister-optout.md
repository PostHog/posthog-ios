---
"posthog-ios": patch
---

Fix: opting out no longer strands an in-flight push unregister. A `DELETE /push_subscriptions` is data removal, so it now goes out even after `optOut()` instead of leaving the server-side subscription active for the whole opted-out period (#746).
