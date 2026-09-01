---
"posthog-ios": patch
---

Surveys: show the selected face on emoji rating questions. The selected face took a color that contrasts against `ratingButtonActiveColor`, but the face is tinted rather than drawn on a filled button, so nothing painted that color behind it. A dark `ratingButtonActiveColor` turned the selected face white on a white survey card, and it disappeared on tap. The face now takes `ratingButtonActiveColor` directly, which matches the Android SDK.
