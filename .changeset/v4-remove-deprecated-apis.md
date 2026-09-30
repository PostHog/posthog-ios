---
'posthog-ios': major
---

**Breaking:** remove deprecated APIs.

- `PostHogConfig.apiKey`, `PostHogConfig(apiKey:)` and `PostHogConfig(apiKey:host:)`: use `projectToken`, `PostHogConfig(projectToken:)` and `PostHogConfig(projectToken:host:)`.
- `PostHogConfig.propertiesSanitizer` and the `PostHogPropertiesSanitizer` protocol: use `PostHogConfig.setBeforeSend(_:)`.
- `PostHogConfig.evaluationEnvironments`: use `evaluationContexts`.
- `PostHogConfig.remoteConfig`: delete the assignment. Remote config is always loaded.
- `PostHogSDK.getFeatureFlagPayload(_:)`: use `getFeatureFlagResult(_:)?.payload`. Pass `sendFeatureFlagEvent: false` to keep the old behavior of not capturing `$feature_flag_called`.
- `PostHogSessionReplayConfig.debouncerDelay`: use `throttleDelay`.
- `PostHogSessionReplayConfig.maskPhotoLibraryImages`: delete the assignment. It had no effect.
