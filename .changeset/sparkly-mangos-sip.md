---
"posthog-ios": minor
---

Support survey partial response collection. When enabled, submit cumulative answers after each question with a stable submission ID and completion status, matching posthog-js.

Persist unfinished surveys across app restarts and restore the submission ID, saved answers, and next question. Completion, dismissal, SDK reset, and incompatible survey updates clear progress. Custom survey delegates opt in by returning `true` from `supportsSurveyResume` and must then honor `initialQuestionIndex`. Other delegates start fresh.

Serialize progress updates with identity reset and reject callbacks from earlier survey attempts. Resumed completion and dismissal preserve the seen-survey history.

Coordinate app-group survey persistence across processes with a durable reset epoch. Old writers and callbacks cannot restore progress after another SDK resets, including when the anonymous ID is reused. Progress records without an epoch are discarded.

Preserve unfinished progress when remote configuration is unavailable, and clean up the configured survey delegate when closing the SDK.
