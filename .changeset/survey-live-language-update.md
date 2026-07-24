---
"posthog-ios": minor
---

Surveys now re-translate in place while displayed. When the user's `language` person property changes (via `identify`/`setPersonProperties`) and a matching translation exists, the on-screen survey updates to the new language without restarting, preserving the current question and progress. Custom survey delegates can adopt the new optional `updateSurvey(_:)` to support live updates.
