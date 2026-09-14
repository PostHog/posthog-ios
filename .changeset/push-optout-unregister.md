---
"posthog-ios": minor
---

fix(push): unregister the device push subscription on `optOut()`

`optOut()` stopped the SDK from sending new registrations but left the subscription stored on the person, so Workflows kept sending push notifications to a device whose user had opted out. Opting out now unregisters the device (a durable DELETE that retries on `flush()`/next launch), and a subscription record found while the app is opted out is removed instead of retried. `optIn()` re-registers when the SDK owns the token; an app that registers tokens itself calls `registerPushNotificationToken(_:)` again after opting back in.
