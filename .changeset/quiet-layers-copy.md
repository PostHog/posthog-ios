---
"posthog-ios": patch
---

Fix a crash in screenshot session replay when the app uses a Swift `CALayer` subclass that doesn't implement `init(layer:)`. While the app shows a custom `CALayer` subclass, replay may skip frames during fast scrolling, and masks the whole screen while a masked view's custom-layer ancestor animates.
