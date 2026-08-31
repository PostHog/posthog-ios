---
"posthog-ios": minor
---

Session replay: honor a `ph-no-mask` token on `accessibilityIdentifier` to exclude a view (and its subviews) from masking. This gives platforms that cannot reach the `.postHogNoMask()` modifier, such as React Native (where `testID` maps to `accessibilityIdentifier`), a way to selectively unmask known-safe views while keeping `maskAllTextInputs` on. The token is deliberately not honored on `accessibilityLabel`, which can carry localized, server-provided, or user-derived content: unmasking is only reachable through the developer-controlled identifier channel.
