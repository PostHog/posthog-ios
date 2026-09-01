---
"posthog-ios": patch
---

Surveys: show the selected face on emoji rating questions. The selected face took a color that contrasts against `ratingButtonActiveColor`, but the face is tinted rather than drawn on a filled button, so nothing painted that color behind it. PostHog pairs `ratingButtonActiveColor` with an opposing background, so the face blended into the card and disappeared on tap. This affected the default appearance and every built-in theme. The face now takes `ratingButtonActiveColor` directly, which matches the Android SDK.
