---
"posthog-ios": patch
---

`upload-symbols.sh` supports `POSTHOG_SKIP_ON_CONFLICT=1` to pass `--skip-on-conflict` to `posthog-cli dsym upload`, so dSYM content conflicts skip the upload instead of failing the build (requires posthog-cli >= 0.7.12)
