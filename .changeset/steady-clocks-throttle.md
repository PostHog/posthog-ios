---
"posthog-ios": patch
---

Fix a main-thread null-call (`0x0`) crash on iOS 27.2 builds when apps compiled with Xcode 27.2 hit `Date.>=` in `PostHogThrottledMulticastCallback.invoke(_:)` (and the sibling `Date.<=` check in `PostHogProcessContextStore`). `PostHogThrottledMulticastCallback` now uses a monotonic `TimeInterval` clock and `PostHogProcessContextStore` compares `timeIntervalSinceReferenceDate`, avoiding Xcode 27.2's `@backDeployed(before: iOS 27.2)` `Date` operators.
