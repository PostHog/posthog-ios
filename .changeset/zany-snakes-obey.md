---
"posthog-ios": patch
---

Update the user's identity and reload feature flags when `identify()` is called while opted out, matching the other PostHog SDKs. No events are captured while opted out.
