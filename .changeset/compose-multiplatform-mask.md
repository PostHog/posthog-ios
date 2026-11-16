---
"posthog-ios": patch
---

Mask Compose Multiplatform views whole in session replay when `maskAllTextInputs` or `maskAllImages` is on, as for web views, since the SDK can't find the text fields, text and images Compose draws inside them
