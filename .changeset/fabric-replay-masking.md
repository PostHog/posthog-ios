---
'posthog-ios': patch
---

Mask React Native New Architecture (Fabric) text and image component views (RCTParagraphComponentView, RCTImageComponentView) and react-native-svg root views (RNSVGSvgView) during session replay, matching the existing legacy RCTTextView/RCTImageView handling.
