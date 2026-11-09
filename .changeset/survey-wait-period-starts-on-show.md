---
'posthog-ios': patch
---

Fix surveys so `seenSurveyWaitPeriodInDays` counts from when a survey was shown rather than when it was closed, and a survey closed before it appears (for example during `surveyPopupDelaySeconds` or after `reset()`) is no longer marked seen or reported as `survey dismissed`.
