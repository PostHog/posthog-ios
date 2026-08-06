---
"posthog-ios": minor
---

Surveys can now display an optional intro screen before the first question, configured via the new `displayIntroScreen`, `introScreenHeader`, `introScreenDescription`, `introScreenDescriptionContentType`, and `introScreenButtonText` appearance fields (mirroring the existing thank-you message fields, including translations). Advancing past the intro records no response and sends no survey event; dismissing the survey from the intro still sends the normal `survey dismissed` event. The new fields are also exposed on `PostHogDisplaySurveyAppearance` for custom survey delegates. Additionally fixes the thank-you message description never rendering in the built-in survey UI.
