---
"posthog-ios": patch
---

fix: duplicate symbol linker errors when posthog-ios is used alongside other dependencies that also include libwebp, such as SDWebImageWebPCoder or KingfisherWebP
