---
"posthog-ios": patch
---

fix(surveys): a single malformed survey no longer disables every survey on iOS. Surveys are now decoded per-element (a bad entry is logged and skipped instead of dropping the whole list), and rating questions tolerate missing `lowerBoundLabel`/`upperBoundLabel` to match Web/Android behavior. Empty bound labels are also no longer rendered as blank caption rows under the rating control. Fixes #611.