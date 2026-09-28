---
'posthog-ios': patch
---

Fix survey sheets sizing against the device's main screen instead of the app's window, which could leave a sheet too tall to fit on foldables, in split view, or in Stage Manager
