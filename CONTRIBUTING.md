# Contributing

If you would like to contribute code to `posthog-ios` you can do so through GitHub by forking the repository and opening a pull request against `main`.

## Development guide

Use the repository's `make` wrappers rather than invoking `swift` or `xcodebuild` directly; [Makefile](Makefile) owns the commands and options.

For initial setup, install Xcode 26 or later and, if needed, use `make bootstrap` to install CocoaPods, xcpretty, SwiftLint, SwiftFormat and Periphery. Agents should report missing prerequisites rather than install tools without authorization. The package uses swift-tools-version 6.2 and compiles in Swift 5 language mode; use current stable Xcode as CI does.

Iterate with focused checks, then run the core CI-aligned checks before submitting **SDK changes**:

```bash
make lint
make test
make buildSdk
```

- `make lint` runs the formatting and lint checks used in CI.
- `make test` runs the Swift Package Manager suite plus build-tool/script tests. On macOS it excludes iOS-only code; use simulator coverage for that behavior.
- `make buildSdk` verifies the SDK builds across supported platforms.

If you prefer to work in Xcode, open `PostHog.xcodeproj`.

When submitting code, please make every effort to follow existing conventions and style in order to keep the code as readable as possible. Please also consider adding unit tests covering your change, as this makes your change much more likely to be accepted.

### Select validation by affected behavior

Markdown-only changes need documentation/link checks and `git diff --check`, not SDK builds, tests or formatting. For SDK changes, the core checks above remain required; add the following coverage where relevant and report unavailable prerequisites.

| Change / purpose | Make wrapper |
| --- | --- |
| Focused SPM suite, class or method during iteration | `make test filter=PostHogPropertiesSerializationTests` |
| iOS-only behavior (including replay/autocapture) | `make testOniOSSimulator` |
| macOS test target in Xcode | `make testOnMacSimulator` |
| Mounted survey interaction UI | `make testSurveyUI` |
| Replay presentation/privacy masking in an app host | `make testPresentationMasks` |
| Masking golden-image verification | `make maskSnapshots` |
| SDK across supported platforms, including Mac Catalyst | `make buildSdk` |
| Code gated by the `SessionReplay`, `CrashReporting` or `Surveys` package traits | `make buildSdkSpmNoTraits`, `make testNoTraits`, `make buildTestsSpmTraitsIOS` |
| Example/platform integrations | `make buildExamplesPlatforms` |
| CocoaPods integration modes | `make buildExamplePodsStaticLib`, `make buildExamplePodsStaticFramework`, `make buildExamplePodsDynamicFramework` |
| XCFramework integration | `make buildExampleXCFramework` |

Use relevant example/package checks for integration or packaging changes, and smoke test changed behavior in an example where applicable. `make buildExamples` runs all example builds; `make build` combines that with `make buildSdk`. These broad targets include CocoaPods installation and XCFramework generation, so they are not the default iteration loop. For package/support changes, also consult the package lint and minimum-toolchain lanes in [build CI](.github/workflows/build.yml) and [example CI](.github/workflows/build-examples.yml).

### Simulator, UI and masking prerequisites

iOS simulator/UI checks require Xcode with the relevant installed runtime, xcpretty and an available iPhone simulator. `make testOniOSSimulator` selects the first available iPhone and only retries failed/crashed XCTest cases in fresh processes; do not bypass its safeguards by retrying Swift Testing suites that install irreversible swizzles.

- `make testSurveyUI` defaults to the first available iPhone. Override `SURVEY_UI_DESTINATION` for a specific installed simulator; `SURVEY_UI_XCODEBUILD_ARGS` accepts focused selectors such as `-only-testing:PostHogSurveyUITests/SurveyAutoSubmitUITests`.
- `make testPresentationMasks` uses an app host for UIKit presentation checks. Use `PRESENTATION_TEST_DESTINATION` to override the destination; the remaining suite stays hostless because it relies on test-bundle identity and app-group entitlements.
- `make maskSnapshots` requires the selected Xcode and iOS runtime pinned by `MASK_SNAPSHOT_XCODE` and `MASK_SNAPSHOT_OS` in the Makefile, plus an available iPhone on that runtime. Goldens are byte-sensitive to the compiler/SDK; do not replace these pins with latest-stable or bypass runtime checks.
- Regenerate with `make recordMaskSnapshots` only after intentional masking or pinned-environment changes, with the same prerequisites. Coordinate toolchain/runtime pin changes with CI and review the resulting image diff before submitting; do not re-record merely to hide a regression.
- Keep the wrappers' raw-log/test-execution assertions: a green xcpretty summary can conceal a zero-test run or broken selector/compile gate.

### Test and style conventions

Write tests with Swift Testing. For network mocking, use [MockPostHogServer](PostHogTests/TestUtils/MockPostHogServer.swift), backed by OHHTTPStubs.

[SwiftFormat](.swiftformat) and [SwiftLint](.swiftlint.yml) own style rules; the Makefile passes `--swiftversion 5.3` to SwiftFormat. `make lint` checks without fixing. When needed and authorized, `make format` runs both auto-fix tools, or use `make swiftLint` / `make swiftFormat` individually; review their resulting diff. These wrappers (including lint) can install missing formatters, so check tool availability before invoking them. `make api` scans for unused code with Periphery; it is not the public API snapshot check.

## Public API changes

Public API is hard to change once it ships, so agree on it before writing the implementation. Our [SDK guidelines](https://posthog.com/handbook/engineering/sdks/guidelines) explain how we design it.

This section is for external contributors. PostHog maintainers (members of the PostHog GitHub org) agree on API shape in the PR itself, so they don't need a separate issue.

- **Before you start:** if you need something the SDK doesn't support and it would add or change a public option, method, or type, open an issue describing your use case. Wait for a maintainer to agree on the API shape there before you implement it. Context is more useful to us than code at this stage.
- **Already specified?** If a published [sdk-spec](https://github.com/PostHog/sdk-specs) defines the API, that's the agreement, so you don't need an issue.
- **Already have a PR open?** Don't stop or rewrite it. Call out the public API change at the top of the PR description, and link or open an issue so we can discuss the shape there.
- Check first whether an existing option or hook, such as `beforeSend`, already covers the use case. We avoid offering two ways to do the same thing.
- If a reviewer suggests a different API on your PR, confirm it with them before re-implementing. Treat it as a question, not an instruction.

When reviewing or fixing someone else's PR, don't ask for or open an issue. Note an external contributor's public API change when it has neither an agreed issue nor an API-defining published spec; the pre-implementation issue policy above is not a gate on that review work.

`make apiCheck` checks [api/posthog-ios.public-api.txt](api/posthog-ios.public-api.txt), as CI does. `make apiUpdate` regenerates it only after intentional public API changes; review the snapshot diff. Both commands build the SDK and extract its public symbol graph, requiring Xcode with the iOS SDK, xcpretty and Python 3. A diff in that file means your change touches public API.

Above all, thank you for contributing!
