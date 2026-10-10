---
'posthog-ios': minor
---

Add `captureAi(...)` to send AI events such as `$ai_generation` to PostHog's AI endpoint (`/i/v1/ai/events`), which accepts events up to 8 MiB.
