---
"posthog-ios": minor
---

Add a `bootstrap` option to `PostHogConfig` for pre-seeding identity and feature flags before the first `/flags` response. Set `config.bootstrap = PostHogBootstrapConfig(...)` before `setup()` so early events carry a caller-controlled distinct ID and flag reads return your values during cold start. Mirrors the `bootstrap` option in posthog-js.
