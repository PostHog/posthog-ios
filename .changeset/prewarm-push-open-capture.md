---
'posthog-ios': minor
---

Add `PostHogSDK.prewarmPushNotificationOpenCapture()` so a notification tap delivered before `setup()` is still captured as `$push_notification_opened`.
