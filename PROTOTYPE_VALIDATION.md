# Autocapture text privacy prototype

Branch: `feat/autocapture-text-privacy`. Based on `143d8337e`. Draft prototype, not release-ready.

## Behavior and proposed API

Internal `PostHogConfig.captureElementText` defaults to `true`, preserving the existing behavior. Set it to `false` before SDK setup to omit control/ancestor text and selected values from autocapture. Explicit labels, class/hierarchy, interaction type and coordinates remain. No-text mode skips `ph_autocaptureText` and control-value reads, and serialization also gates already-built event data. Accessibility labels are still read to honor exclusion markers such as `ph-no-capture`. Independently enabled rage-click capture also honors this setting.

Manual events and replay are unchanged. This is not a general personal-data scrubber: explicit labels, screen names and manual/super properties remain the application's responsibility. Public API promotion is intentionally left for issue-level agreement; the Debug demo uses a testable import.

## Simulator verification

Tested after the SwiftUI prototype and before the dead-click prototype on iPhone 17 Pro / iOS 26.5, using Xcode 27 and AXe HID input.

The same synthetic UIKit form was exercised in default and no-text launches:

- Default preserved `SYNTHETIC_BUTTON`, edited ordinary text-field contents, text-view contents, and the selected segment title in autocapture chains.
- No-text omitted all those sentinels and `text=` attributes while preserving stable identifiers and event types.
- Manual `prototype_manual` events retained `text: SYNTHETIC_MANUAL` in both modes.
- Excluded controls produced no events. Opt-out/close suppressed capture; opt-in restored it.
- SDK logs showed successful US Cloud batch responses in both modes. This proves endpoint acceptance, not an independent storage query.

Cloud run tags: `privacy-default-sim-validation` and `privacy-no-text-sim-validation`. Incidental keyboard/scroll events can make total event counts differ; assertions compare the relevant target payloads rather than requiring equal totals.

## Automated checks

- `make test`: passed (844 Swift Testing tests; existing XCTest tests also passed).
- Focused simulator tests: seven new test functions (ten cases including parameterization), plus 17 rage-click integration tests and 13 existing autocapture XCTest cases passed. Tests include inputs, selections, numeric/toggle values, ancestor text, no `ph_autocaptureText` invocation, exclusions, manual properties and consent/close lifecycle. The rage-click-only regression failed before the fix on both getter reads and serialized text in no-text mode, then passed in both modes.
- Debug simulator example build: passed.
- `make format`, `make lint`, `git diff --check`: passed.
- Xcode 27 build follow-up: `XCODE_XCCONFIG_FILE=/tmp/posthog-prototype-tools/compat.xcconfig make build` successfully built the SDK for iOS, macOS (SPM and Xcode), Mac Catalyst, tvOS, watchOS and visionOS, all eight platform-example destinations, and both external-framework archives. The aggregate command then stopped at the external XCFramework client: its package dependency expects the checkout directory identity `posthog-ios`, but this worktree is named `posthog-ios-autocapture-text-privacy`. CocoaPods targets were not reached.
- Temporary build-only settings: iOS/tvOS 15, macOS 12, watchOS 9, exclude watchOS `armv7k`, disable signing. Repository deployment targets are unchanged. These builds do not validate the original minimum OS versions and are not release artifacts.

## Running the demo

Build `PostHogExample` in Debug. Launch with `POSTHOG_PROTOTYPE=1`, `POSTHOG_API_KEY`, `POSTHOG_HOST=https://us.i.posthog.com`, and optional `POSTHOG_PROTOTYPE_RUN`. Omit `POSTHOG_CAPTURE_ELEMENT_TEXT` to verify the default, or set it to `0` for no-text mode. Relaunch between modes.

The Debug-only iOS demo writes pre-enqueue event evidence to Documents `prototype-events.jsonl` and upload diagnostics to `prototype-sdk.log`; both reset on launch. Credentials are supplied at runtime, not stored in source. Normal example behavior is unchanged without the prototype switch.

Evidence: `/Users/marandaneto/Github/_prototype-evidence/posthog-ios-autocapture-1ff5e432/`, including `privacy-default-final-events.jsonl`, `privacy-no-text-final-events.jsonl`, both delivery logs, `privacy-no-text.png`, and `posthog-prototype-privacy-test.log`.
