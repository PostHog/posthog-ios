---
'posthog-ios': minor
---

Add `captureAi(...)` to send AI events such as `$ai_generation` to PostHog's AI endpoint (`/i/v1/ai/events`), which accepts events up to 8 MiB. It returns the event UUID.

Analytics batches are now also capped at 5 MiB per request, so a batch of large events stays under capture V1's request limit; an event larger than that is sent on its own.
