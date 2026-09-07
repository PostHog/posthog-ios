---
"posthog-ios": patch
---

Keep the person properties passed to `identify()` when the SDK is already identified with a different distinct id. The properties are now applied to the current person instead of being dropped, which matches posthog-js. Dropped properties and ignored duplicate calls are also reported with a warning that names the property keys, so the loss is no longer silent.
