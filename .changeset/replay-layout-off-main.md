---
"posthog-ios": patch
---

Stop session replay's `UIView.layoutSublayers(of:)` hook from running UIKit layout on a background thread, which crashed the host app in the Auto Layout engine. Add `sessionReplayConfig.captureViewLayoutChanges` to stop session replay using the hook while keeping the rest of session replay. Surveys subscribe to the same hook and are enabled by default, so set `surveys` to `false` as well to remove it entirely.
