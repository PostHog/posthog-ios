---
'posthog-ios': major
---

**Breaking:** remove `PostHogDataMode.cellular`. It always behaved the same as `.any`, so use `.any` instead. Flushing behavior is unchanged.
