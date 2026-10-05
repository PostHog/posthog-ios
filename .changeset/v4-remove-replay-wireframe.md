---
'posthog-ios': major
---

**Breaking:** remove wireframe session replay capture. Session replay now always records masked screenshots.

- Apps that didn't set `screenshotMode` now upload screenshots instead of wireframes, which uses more bandwidth and CPU per captured frame.
- Masking covers text, inputs, images and web views. Custom-drawn content (custom `draw(_:)` views, maps, video, charts) is now visible in recordings: wrap anything sensitive in `postHogMask()` or tag it `ph-no-capture`.
- Apps whose window root is a SwiftUI view, which previously recorded nothing, now record sessions.
- `PostHogSessionReplayConfig.screenshotMode` is deprecated and has no effect: delete the assignment. Setting it to `false` no longer prevents screenshots; use the masking options instead.
- `screenshotModeBackgroundCapture` now applies without setting `screenshotMode`.
- The replay screen name now names the visible screen (SwiftUI screens report their view name), and is also sent when `screenshotMode` was enabled.
