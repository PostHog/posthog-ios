---
"posthog-ios": patch
---

Fix an app hang where the main thread waited for `setup()` to finish when it ran off the main thread (as in React Native) and remote config or feature flags loaded meanwhile, and stop session replay looking up two iOS 26-only SwiftUI class names on earlier iOS versions
