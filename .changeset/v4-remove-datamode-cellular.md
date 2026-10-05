---
'posthog-ios': major
---

**Breaking:** remove `PostHogDataMode.cellular`. It always behaved the same as `.any`, so use `.any` instead (`PostHogDataModeAny` in Objective-C). Flushing behavior is unchanged. `.wifi` and `.any` keep their raw values 0 and 2; `PostHogDataMode(rawValue: 1)` now returns `nil`.
