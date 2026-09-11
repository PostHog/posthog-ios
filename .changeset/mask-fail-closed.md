---
"posthog-ios": patch
---

- Drop a session replay screenshot when its masked image cannot be rendered, instead of sending the unmasked screenshot.
- Collect masks inside a zero-size parent view that does not clip, because it still draws its subviews. React Native's default `overflow: visible` produces such a wrapper.
- Collect masks in a view that fades out or fades in, using the opacity the screenshot renders instead of the model `alpha`.
