---
"posthog-ios": minor
---

Add push notification support for PostHog Workflows. The SDK now registers the device's APNs token (iOS) so Workflows can deliver push notifications, and captures a `$push_notification_opened` event when a notification is tapped. Both are on by default and can be turned off with the new `capturePushNotificationSubscriptions` and `capturePushNotificationOpened` config flags. For setups that don't use swizzling, use `registerPushNotificationToken(_:appId:)` and `capturePushNotificationOpened(response:)` to feed these manually. On `reset()` the token is unregistered for the logged-out user and re-registered under the new anonymous id, and `unregisterPushNotificationToken()` lets you unregister manually.
