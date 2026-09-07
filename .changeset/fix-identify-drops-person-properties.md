---
"posthog-ios": patch
---

Keep the person properties passed to `identify()` when the SDK is already identified with a different distinct id. The properties are now applied to the current person instead of being dropped, which matches posthog-js. The SDK also warns once, even with debug logging off, that the distinct id did not change and that `reset()` is required to switch users, so the behaviour is no longer silent.
