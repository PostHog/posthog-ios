---
'posthog-ios': minor
---

Change `capturePushNotificationOpened` to skip a repeat open of a PostHog-sent notification (same `invocation_id` and `action_id`) captured in the last 5 minutes, so an automatic capture plus a manual call for one tap counts once.
