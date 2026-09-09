---
'posthog-ios': patch
---

Log a debug warning when `capturePushNotificationOpened` is enabled and no `UNUserNotificationCenter` delegate is set, which is the case where no notification tap can ever be captured.
