---
"posthog-ios": patch
---

Session replay: skip native event-trigger gating when running under React Native (`postHogSdkName == "posthog-react-native"`). React Native evaluates `sessionRecording.eventTriggers` in its JS layer and drives recording via explicit `startSessionRecording` calls; the native gate could never be satisfied because JS-captured events never reach the native capture pipeline, so event-triggered replay never recorded on RN. The linked-flag and sampling gates are unchanged, and non-RN behavior is unaffected.
