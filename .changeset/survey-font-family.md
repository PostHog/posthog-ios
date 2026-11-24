---
"posthog-ios": patch
---

Apply the survey's `appearance.fontFamily` in the built-in survey UI. The first family of the CSS font list is used when it's installed on the device, keeping each element's size, weight and Dynamic Type scaling; `inherit`, `system-ui`, empty values and unavailable fonts keep the system font.
