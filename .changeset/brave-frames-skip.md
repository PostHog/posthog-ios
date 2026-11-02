---
"posthog-ios": patch
---

Skip a session replay screenshot when `drawHierarchy` reports it could not render the window, instead of uploading a blank frame.
