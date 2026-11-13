---
"posthog-ios": patch
---

Fix `Application Opened` sometimes missing `$session_id` after the app spent more than 30 minutes in the background: lifecycle subscribers now run in subscription order, so the session manager starts the new session before the event is captured.
