---
"posthog-ios": patch
---

Add a `$feature_flag_has_experiment` boolean property to `$feature_flag_called` events, sourced from the flag's `metadata.has_experiment` in the flags response. The property is only sent when the server explicitly reports it and omitted when unknown (e.g. legacy responses without flag details).
