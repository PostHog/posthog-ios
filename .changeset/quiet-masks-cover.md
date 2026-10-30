---
'posthog-ios': patch
---

Fix `screenshotMode` session replay leaving masked content visible where it is drawn outside its view (unclipped images, layer shadows, button titles) and image attachments in text unmasked when `maskAllImages` is on.
