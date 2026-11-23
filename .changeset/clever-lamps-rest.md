---
"posthog-ios": patch
---

Fix GPU session replay capture showing content drawn over a `ph-no-capture` view, such as the text of a React Native `View` tagged `ph-no-capture`, which is now a solid black block as on the default capture path.
