---
"posthog-ios": minor
---

Add `POSTHOG_FORCE` to `upload-symbols.sh`. Set it to `1` so the dSYM upload passes `--force` to posthog-cli (>= 0.7.12) and overwrites a symbol set that already exists with different content, instead of failing the build. It cannot be combined with `POSTHOG_SKIP_ON_CONFLICT`, which posthog-cli rejects.
