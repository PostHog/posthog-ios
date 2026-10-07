---
'posthog-ios': minor
---

Add `SessionReplay` and `CrashReporting` Swift package traits (on by default) so SwiftPM apps can leave out session replay with the vendored libwebp, and the vendored PLCrashReporter, with `traits: []`.
