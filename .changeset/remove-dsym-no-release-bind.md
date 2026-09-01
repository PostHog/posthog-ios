---
'posthog-ios': minor
---

Remove `POSTHOG_NO_RELEASE_BIND` from the dSYM upload build phase. The script uploads symbol sets bound to the release it creates, which is what it did before the variable existed.

Event mode only helps when two releases ship a byte-identical binary, because the symbol id is the Mach-O `LC_UUID`. It also cost release attribution for embedded targets: the upload covers every extension dSYM but creates one release, so an extension crash resolved no release once the binding was gone. The variable was experimental and undocumented, so it goes out directly.
