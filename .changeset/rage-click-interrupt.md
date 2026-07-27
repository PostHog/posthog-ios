---
"posthog-ios": patch
---

Fix rage click detection dismissing presented UI (e.g. popovers and sheets) on the opening tap. The hit-test fallback used to recover a tapped view now runs as a stateless query (`hitTest` with `nil`) instead of re-entering UIKit's hit-testing/gesture machinery with the in-flight event, which corrupted internal touch/gesture state.
