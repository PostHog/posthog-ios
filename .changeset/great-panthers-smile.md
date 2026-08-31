---
"PostHog": patch
---

Session replay: honor a `ph-no-mask` token on `accessibilityIdentifier` or `accessibilityLabel` to exclude a view (and its subviews) from masking, mirroring the existing `ph-no-capture` token. This gives platforms that cannot reach the `.postHogNoMask()` modifier, such as React Native (where `testID` maps to `accessibilityIdentifier`), a way to selectively unmask known-safe views while keeping `maskAllTextInputs` on. On React Native every `Text` currently masks under `maskAllTextInputs`, so recordings are unreadable wireframes with no opt-out; with this token, apps can keep the conservative default and unmask navigation chrome explicitly.
