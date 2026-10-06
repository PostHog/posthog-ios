# PostHog iOS SDK

## Start here
- Read [CONTRIBUTING.md](CONTRIBUTING.md) for development commands/prerequisites, [AI_POLICY.md](AI_POLICY.md) and the [PR template](.github/PULL_REQUEST_TEMPLATE.md) for contribution requirements. For releasable changes, follow [RELEASING.md](RELEASING.md), including maintainer approval and emergency-only manual publishing.
- SDK entry point: [PostHog/PostHogSDK.swift](PostHog/PostHogSDK.swift); tests: `PostHogTests/`; replay/privacy: `PostHog/Replay/` and `PostHog/Resources/`.

## Repository invariants
- Maintain Swift 5 SDK language mode. The package needs swift-tools-version 6.2 (Xcode 26+); prefer Swift Testing for new tests. Use `PostHogTests/TestUtils/MockPostHogServer.swift` for HTTP stubbing.
- Preserve deployment minima: iOS 15, tvOS 15, macOS 11, watchOS 10, visionOS 1. Keep platform guards and graceful degradation, especially for session replay. Availability annotations/checks do not require adding platform support or raising targets. Intentional support changes require checking `Package.swift` plus CocoaPods/Xcode packaging/build configuration.
- Public APIs must remain thread-safe and callable from any thread. Preserve offline operation and queue-based event batching; never assume connectivity. `PostHogSDK.shared` is the default singleton; independent instances use `PostHogSDK.with(_:)` with `PostHogConfig`.
- Preserve replay masking/privacy behavior and privacy-safe error logging; do not expose sensitive user data.
- Prefer no new dependencies. libwebp is embedded; PHPLCrashReporter is vendored, prefixed PLCrashReporter for native crash reporting on iOS/macOS/tvOS, excluded on watchOS/visionOS.

## Validation selector
- Use `make` wrappers, not direct `swift`/`xcodebuild`. Iterate with focused tests; before submitting SDK changes, run contributor checks: `make lint`, `make test`, `make buildSdk`.
- Add iOS simulator coverage for iOS-only behavior: macOS SPM tests compile it out. Select survey UI, presentation/privacy masking, golden-image and example/package checks by affected behavior; see [validation and prerequisites](CONTRIBUTING.md#select-validation-by-affected-behavior).
- Snapshot pins belong to Makefile (`MASK_SNAPSHOT_XCODE`, `MASK_SNAPSHOT_OS`); regenerate only intentionally and review image/API snapshot diffs. Keep runtime/zero-test checks and irreversible-swizzle retry safeguards described in the contributor guide.
- Markdown-only edits need documentation/link checks and `git diff --check`, not SDK validation. Format only when needed and authorized, review the diff, and report missing prerequisites rather than silently installing tools (lint/format wrappers can install them).

## Public API and specs
- Follow [Public API changes](CONTRIBUTING.md#public-api-changes). When reviewing or fixing someone else's PR, don't ask for or open an issue. Note an external contributor's public API change when it has neither an agreed issue nor an API-defining published spec.
- The author is a PostHog maintainer when the PR's `author_association` is `MEMBER` or `OWNER` (`gh api repos/PostHog/posthog-ios/pulls/<number> --jq .author_association`) or, before a PR exists, when `gh api orgs/PostHog/members/$(gh api user --jq .login)` succeeds. If the check fails or can't run, treat the author as an external contributor.
- A published [sdk-spec](https://github.com/PostHog/sdk-specs) that defines the API counts as the agreement, so no issue is needed. For new implementation by an external contributor with no agreed issue and no spec, stop before implementing and draft the issue body for the user to post. Open it only if they ask.
- Before implementing or reviewing SDK behavior, check [PostHog/sdk-specs](https://github.com/PostHog/sdk-specs) for a covering spec (its README lists every capability). Use it as the cross-SDK contract for changed behavior, and call out any divergence in that behavior in the PR description. Don't fix or flag spec/code discrepancies the PR doesn't touch. If none exists, carry on.
- Preserve backwards compatibility; prefer optional parameters with sensible defaults over overloads. Document all public methods. Deprecations use `@available(*, deprecated, message:)` with migration guidance.
