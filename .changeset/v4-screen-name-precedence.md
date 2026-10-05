---
'posthog-ios': major
---

**Breaking:** `screen(_:properties:)` now always records the screen title as `$screen_name`, ignoring a `$screen_name` key in `properties`. Pass the name you want recorded as the title.
