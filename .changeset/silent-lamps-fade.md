---
'posthog-ios': patch
---

Fix session replay recording touches inside views masked with `ph-no-capture` or `postHogMask()`. These touches are now dropped. Touches on views masked only by `maskAllTextInputs` or `maskAllImages` are still recorded.
