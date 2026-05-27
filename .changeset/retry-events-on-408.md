---
"posthog-ios": patch
---

Retry event uploads on HTTP 408 (Request Timeout), matching the SDK's existing logs-endpoint behavior.
