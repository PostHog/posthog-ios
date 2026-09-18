---
"posthog-ios": minor
---

fix(push): unregister the device push subscription on `optOut()`

`optOut()` stopped the SDK from sending new registrations but left the subscription stored on the person, so Workflows kept sending push notifications to a device whose user had opted out. Opting out unregisters the device (a durable DELETE that retries on `flush()`/next launch) and keeps the device token locally, so `optIn()` resubscribes without the app re-registering the token.

Known edge case: a registration whose success response was lost is treated as never delivered, so an opt-out keeps an older pending unregister instead of replacing it. A per-identity queue of pending unregisters is the follow-up that closes it.
