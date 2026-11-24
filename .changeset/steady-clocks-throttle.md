---
"posthog-ios": patch
---

Fix a main-thread crash with a call to address 0x0 in `PostHogThrottledMulticastCallback.invoke(_:)`, which runs on every main run-loop cycle when session replay or surveys are on. The throttle now reads a monotonic clock that each instance owns, and it does not compare `Date` values or call a global, mutable clock closure.
