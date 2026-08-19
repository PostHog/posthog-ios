---
"posthog-ios": patch
---

Skip push token registration when the project has no push integration for the app_id, using the `push.appIds` list published in remote config. A device whose project configures push later re-registers on the next config load rather than staying unreachable.
