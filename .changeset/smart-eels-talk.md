---
'posthog-ios': patch
---

Keep `$recording_status`, the replay trigger statuses and the replay buffer length on every captured event. Add the remaining `$sdk_debug_*` session replay properties and `$sdk_debug_session_start` only to SDK events (names starting with `$`, excluding `$feature_flag_called` and `$snapshot`), at most once every 30 seconds. Remove `$sdk_debug_current_session_duration` and `$sdk_debug_replay_throttle_delay_ms`.
