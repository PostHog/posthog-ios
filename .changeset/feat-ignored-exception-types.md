---
'posthog-ios': minor
---

Add `ignoredExceptionTypes` to `PostHogErrorTrackingConfig` so apps embedding both the JS RN SDK and the native iOS SDK can suppress duplicate native captures by exception class name.
