---
"posthog-ios": patch
---

Add a `$feature_flag_has_experiment` boolean property to `$feature_flag_called` events, sourced from the flag's `metadata.has_experiment` in the flags response (false when the server does not report it).
