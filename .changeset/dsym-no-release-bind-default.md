---
'posthog-ios': minor
---

Upload dSYM symbol sets release-independent by default. The release is still created, and the server resolves each crash's release from the `$app_version` / `$app_namespace` / `$app_build` the SDK sends on every event. Two releases that ship the same dSYM no longer both report whichever release uploaded it first. Set `POSTHOG_NO_RELEASE_BIND=0` in the upload build phase to keep binding the symbol sets to the created release. The default needs posthog-cli 0.10.0 or newer, which the script checks before it uploads anything.

A zero-padded `CFBundleVersion` such as `001` now creates the release under `1`. The SDK reports `$app_build` as a number, so the padded form matched no event and those crashes reported no release. A build that is not all digits, such as `1.2.3`, stays as written.
