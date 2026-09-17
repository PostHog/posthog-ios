# SwiftUI tap autocapture prototype

Branch: `feat/swiftui-tap-autocapture`. Based on `143d8337e`. Draft prototype, not release-ready.

## Behavior

Uses the existing `captureElementInteractions` option and shared application touch publisher. Adds short single-touch SwiftUI taps without a competing recognizer. Explicit `.postHogLabel` markers are resolved geometrically; UIKit control capture stays on its existing route. Legacy SwiftUI tap-recognizer events defer to the new touch route to avoid losing metadata or duplicating events. Drag/long-press classification, masking, cancellation and consent gates are enforced.

The label marker's UIKit cousin lookup now requires matching geometry, preventing a neighboring native control from receiving an unrelated SwiftUI label.

## Simulator verification

Tested sequentially before the other two prototypes on iPhone 17 Pro / iOS 26.5, using Xcode 27 and AXe HID input. No manual `$autocapture` calls simulate feature output.

- SwiftUI button, nested button and `onTapGesture`: one event each with the correct explicit label; corresponding UI counters incremented.
- UIKit control: exactly one event and its own label, not its neighboring SwiftUI label.
- Masked and unresolved no-capture target: UI actions executed without events.
- Long press and scrolling: no new touch events; existing scroll events remain possible.
- Settled sheet presentation/dismissal and navigation/destination buttons: actions and correctly labeled capture worked.
- Opt-out: local button still responds, no new events. Opt-in: one event resumes. Close: no further events.
- SDK logs confirmed successful US Cloud batch responses for the final delivery run. This proves endpoint acceptance, not a separate query of project event storage.

Cloud run tags: `swiftui-sim-validation-05` (full interaction checks), `swiftui-sim-validation-06-delivery` (final upload confirmation). Earlier numbered runs include intermediate debugging results and should not be used as final acceptance evidence.

## Automated checks

- `make test`: passed (844 Swift Testing tests; existing XCTest tests also passed).
- Focused simulator tests via the make wrapper: 16 new Swift Testing tests plus 13 existing autocapture XCTest cases passed. Review regressions cover pointer input, indexed accessibility fallbacks, cousin-label reassignment/cleanup, and releasing just outside a labeled target. Tap completion re-resolves the ending element chain. The iOS 18 accessibility hit-test optimization is compile-time gated for older Xcode SDKs; indexed traversal remains available.
- Debug simulator example build: passed.
- `make format`, `make lint`, `git diff --check`: passed.
- Xcode 27 build follow-up: `XCODE_XCCONFIG_FILE=/tmp/posthog-prototype-tools/compat.xcconfig make build` successfully built the SDK for iOS, macOS (SPM and Xcode), Mac Catalyst, tvOS, watchOS and visionOS, all eight platform-example destinations, and both external-framework archives. The aggregate command then stopped at the external XCFramework client: its package dependency expects the checkout directory identity `posthog-ios`, but this worktree is named `posthog-ios-swiftui-tap-autocapture`. CocoaPods targets were not reached.
- Temporary build-only settings: iOS/tvOS 15, macOS 12, watchOS 9, exclude watchOS `armv7k`, disable signing. Repository deployment targets are unchanged. These builds do not validate the original minimum OS versions and are not release artifacts.

## Running the demo

Build `PostHogExample` in Debug, then launch with `POSTHOG_PROTOTYPE=1`, `POSTHOG_API_KEY`, `POSTHOG_HOST=https://us.i.posthog.com`, and an optional `POSTHOG_PROTOTYPE_RUN`. No token is stored in source. The normal example remains unchanged without that switch. The demo is excluded from non-iOS and Release builds.

Documents contains `prototype-events.jsonl` (pre-enqueue event evidence) and `prototype-sdk.log` (debug output, including upload outcomes), reset on every launch. AXe batch interaction should use `--ax-cache perStep` and wait for sheet/navigation animations to settle.

## Remaining limitations

This is best-effort SwiftUI coverage, not all SwiftUI rendering/accessibility configurations. Unresolved flattened hosting surfaces are deliberately skipped instead of assigning every tap to the whole screen. Explicit `.postHogLabel` markers are the reliable path exercised here; accessibility identifiers and index fallbacks depend on OS/accessibility materialization. Do not treat accessibility-based exclusion as a universal SwiftUI privacy boundary; explicit masking and appropriate labels still need application-level verification. Developer-supplied labels must not contain personal data. Additional OS versions, devices, accessibility modes, lifecycle stress and independent review remain necessary.

Evidence: `/Users/marandaneto/Github/_prototype-evidence/posthog-ios-autocapture-1ff5e432/`, especially `swiftui-final-*-events.jsonl`, `swiftui-delivery.log`, `swiftui.png`, and `posthog-prototype-swiftui-test.log`.
