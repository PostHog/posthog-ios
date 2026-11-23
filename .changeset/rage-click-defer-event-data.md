---
"posthog-ios": patch
---

Defer view-hierarchy extraction in `PostHogRageClickIntegration` until a rage click is actually detected, and replace `String(describing:)` / `String(reflecting:)` metatype lookups on autocapture and touch hot paths with `_typeName(_:qualified:)` and `NSStringFromClass(_:)` to avoid main-thread `swift_conformsToProtocol` scans.
