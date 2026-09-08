---
"posthog-ios": patch
---

Stop session replay's `UIView.layoutSublayers(of:)` hook from running UIKit layout on a background thread, which crashed the host app in the Auto Layout engine. Add `captureViewLayoutChanges` to `PostHogConfig` to remove the hook, which session replay and surveys both honour.
