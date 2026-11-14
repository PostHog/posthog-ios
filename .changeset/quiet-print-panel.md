---
"posthog-ios": patch
---

Fix a crash when the iPad print panel appears with screen views, autocapture, rage clicks or session replay on. The print panel claims to be a `UISplitViewController` but does not implement its API, so screen lookup now only reads real split views as one
