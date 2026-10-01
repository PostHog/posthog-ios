---
"posthog-ios": patch
---

Keep nested dates and URLs when sanitizing event properties. A `Date` or `URL` inside a dictionary or array is converted the same way as a top-level value, and the surrounding fields are no longer dropped with it.
