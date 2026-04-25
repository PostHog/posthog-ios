---
"posthog-ios": patch
---

fix: parse `build` as Int when possible on `Application Opened` events, matching `Application Installed` / `Application Updated`. Extracts the shared `CFBundleVersion` parsing into a reusable helper so all four `build` / `$app_build` / `previous_build` call sites stay consistent.
