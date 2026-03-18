---
"posthog-ios": patch
---

Replace ReadWriteLock with NSLock for consistent thread-safety across the codebase. The ReadWriteLock property wrapper provided false thread-safety for collection types since the lock was released between separate operations. Using explicit NSLock with `.withLock` closures ensures atomic operations and clearer intent.
