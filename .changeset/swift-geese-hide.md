---
"posthog-ios": patch
---

Session replay no longer starts the console log and network plugins while the recorder is off, for example when a session is sampled out or waiting for an event trigger. Stopping replay, opting out, or closing the SDK now stops any plugins left running.
