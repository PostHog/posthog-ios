---
"posthog-ios": patch
---

Fix layout observation lifecycle races during concurrent subscriptions and preserve safe forwarding for in-flight layout calls when recording stops. Recover layout observation on subscription changes when another swizzler removes or bypasses the PostHog hook.
