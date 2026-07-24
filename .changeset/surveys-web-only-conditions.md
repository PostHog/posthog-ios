---
"posthog-ios": patch
---

Fix surveys scoped to web via a CSS selector or URL display condition leaking onto native iOS. Surveys carrying `conditions.selector` or `conditions.url` are now treated as non-matching on native platforms, since those conditions can only be evaluated in a web context.
