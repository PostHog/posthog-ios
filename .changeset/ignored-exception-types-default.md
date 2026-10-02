---
'posthog-ios': patch
---

Remove the `RCTFatalException` default from `errorTrackingConfig.ignoredExceptionTypes` and correct its documentation. The default never matched the exception React Native raises for a fatal JS error, which is named `"RCTFatalException: <message>"`, so it filtered nothing. The option now defaults to `[]`. The PostHog React Native plugin removes these duplicates where it can (old architecture, and new architecture on React Native 0.83.5+ / 0.85+). On earlier new-architecture versions a native `SIGABRT` duplicate can still appear. If your app relied on filtering an exception named exactly `RCTFatalException`, add it back with `config.errorTrackingConfig.ignoredExceptionTypes = ["RCTFatalException"]`.
