---
'posthog-ios': minor
---

Upload dSYM symbol sets release-independent by default. The release is still created, and the server resolves each crash's release from the `$app_version` / `$app_namespace` / `$app_build` the SDK sends on every event, so two releases that ship the same dSYM no longer both report whichever release uploaded it first. Set `POSTHOG_NO_RELEASE_BIND=0` in the upload build phase to keep binding the symbol sets to the created release. The default needs posthog-cli >= 0.10.0, which the script checks before uploading anything.
