---
"posthog-ios": patch
---

Stop emitting `$feature_flag_called` for survey flags whose keys start with `survey-targeting-`, matching the browser SDK while preserving usage tracking for ordinary linked flags.
