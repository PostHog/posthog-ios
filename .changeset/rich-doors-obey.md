---
"posthog-ios": patch
---

Drop the `$sdk_debug_replay_*` and `$sdk_debug_session_start` keys from events while session replay is off locally or remotely; `$recording_status` stays
