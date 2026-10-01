---
'posthog-ios': patch
---

Remove the `RCTFatalException` default from `errorTrackingConfig.ignoredExceptionTypes` and correct its documentation. The default never matched the exception React Native raises for a fatal JS error, which is named `"RCTFatalException: <message>"`, so it filtered nothing. The option now defaults to `[]`. Deduplicating React Native crashes is done by the PostHog React Native plugin, not by this option. If your app relied on filtering an exception named exactly `RCTFatalException`, add it back with `config.errorTrackingConfig.ignoredExceptionTypes = ["RCTFatalException"]`.
