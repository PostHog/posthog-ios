---
"posthog-ios": patch
---

Remove the empty `NSPrivacyAccessedAPITypes` key from the bundled crash reporter's privacy manifest, since Apple treats an empty array there as invalid and the crash reporter uses no required-reason APIs
