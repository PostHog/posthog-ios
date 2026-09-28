---
'posthog-ios': patch
---

Add fewer `$sdk_debug_*` session replay properties to captured events: only the keys the replay capture diagnostics read, only on SDK events (names starting with `$`, excluding `$feature_flag_called`), and at most once every 30 seconds. Remove `$sdk_debug_current_session_duration` and `$sdk_debug_replay_throttle_delay_ms`; `$sdk_debug_pending_queue_size` stays on every event.
