---
"posthog-ios": patch
---

`upload-symbols.sh` supports `POSTHOG_DOTENV_FILE=<path>` to pass `--dotenv-file` to `posthog-cli`, so the dSYM upload can read `POSTHOG_CLI_*` credentials from a gitignored dotenv file instead of requiring them in the build environment (requires posthog-cli >= 0.7.18)
