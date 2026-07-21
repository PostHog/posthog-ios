---
"posthog-ios": minor
---

Send minimal `$feature_flag_called` events when the server opts the project in (top-level `minimalFlagCalledEvents` in the flags response) and the evaluated flag has no experiment. Minimal events keep only a strict allowlist of flag-evaluation and linkage properties plus `$os_name`, `$os_version`, and `$app_version` for OS- and version-segmented insights; the rest of the device/OS context envelope, super properties, `$active_feature_flags`, and the `$feature/<key>` enumeration are stripped. Experiment-linked flags, ungated projects, and any response missing the signals keep sending the full event.
