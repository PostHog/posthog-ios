---
'posthog-ios': minor
---

Change properties passed to `capture()` and the other event methods to override registered super properties and SDK context properties such as `$app_version`, `$os_name` and `$lib`, and a group passed in `groups:` to override a group set with `group()`, matching posthog-android and posthog-js. If you relied on the registered or SDK value winning, stop passing the conflicting key per event; `$is_identified`, `$process_person_profile`, `$geoip_disable`, `$recording_status` and `$sdk_debug_*` properties are still set by the SDK.
