---
"posthog-ios": minor
---

Add `PostHogConfig.pushIdentityProvider` so apps can attach a backend-minted identity token (`identity_token`) to push subscription register/unregister requests, for projects that enable identity verification on their push integration.
