---
"posthog-ios": patch
---

Fix missing cold `Application Opened` event when `setup()` runs before UIKit creates the shared app, for example in a SwiftUI `App.init`.
