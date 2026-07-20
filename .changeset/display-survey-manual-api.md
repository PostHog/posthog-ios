---
"posthog-ios": minor
---

Add `PostHogSDK.shared.displaySurvey(surveyId)` to display a survey on demand, bypassing display conditions (targeting flags, event triggers, and seen/wait-period checks). This is the mobile counterpart of the web SDK's `posthog.displaySurvey()` and also enables API-type surveys, which are never auto-displayed.
