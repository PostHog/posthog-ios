---
'posthog-ios': patch
---

Serialize `Set` and `NSSet` event property values as JSON arrays instead of dropping the property, including when a set is nested inside a dictionary or array
