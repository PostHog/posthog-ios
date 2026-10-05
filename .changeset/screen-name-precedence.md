---
'posthog-ios': patch
---

`screen(_:properties:)` records the screen title as `$screen_name` again when `properties` also contains `$screen_name`, as it did before 3.59.0.
