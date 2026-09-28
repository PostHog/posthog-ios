---
'posthog-ios': patch
---

Fix survey sheets being sized against the device's main screen instead of the app's window, which could show a sheet at half height or too tall to fit on foldables and in resizable iPad windows.
