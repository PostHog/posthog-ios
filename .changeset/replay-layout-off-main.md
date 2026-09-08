---
"posthog-ios": patch
---

Stop session replay's `UIView.layoutSublayers(of:)` hook from running UIKit layout on a background thread, which crashed the host app in the Auto Layout engine. Add `sessionReplayConfig.captureViewLayoutChanges` to remove the hook while keeping the rest of session replay.
