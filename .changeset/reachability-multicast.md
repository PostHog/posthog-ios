---
"posthog-ios": patch
---

Fix events queue not responding to network reachability changes. The replay queue's subscription was silently overwriting the events queue's `whenReachable` / `whenUnreachable` callbacks since v3.0, so `dataMode = .wifi` was ignored, auto-flush on WiFi reconnect did not fire, and the offline pause was reactive after a wasted request. `Reachability` now exposes `onReachable` / `onUnreachable` multicast hooks; the legacy single-callback fields are deprecated.
