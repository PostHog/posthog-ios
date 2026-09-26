# Test audit checkpoint

## Status and scope

**Partial repair campaign, not an all-green or all-fixed signoff.** Tests, support code, Xcode discovery, and the CI result gate were audited. Concrete fixes are implemented below; remaining repair candidates and unverified declarations are retained explicitly. No tests were deleted, no golden snapshots were regenerated, and no production SDK files were changed.

- Worktree: `/Users/marandaneto/Github/posthog-ios-test-audit`
- Branch: `test/audit-all-tests`
- Baseline: `c99f607d81549d5034a9ccd093ccb07fea21f642`
- This report records the audit checkpoint before PR preparation.
- Original checkout and its pre-existing changes were left alone.

The three read-only reviewer artifacts contain the declaration-level R/F/C/D/U ledgers, original observations, and proposed mutations: [core](core.md), [replay](replay.md), [surveys/utilities](surveys-utils.md). They describe the baseline, **not approval of the final patch**. The disposition overlay below supersedes their repair status. U/U-body declarations still need verification; they are not silently promoted to R. No C/D action was taken.

Canonical specs were inspected under `PostHog/sdk-specs/openspec/specs`. Existing retry, logs recovery, mask-precedence, and screen-property policy disagreements were not reconciled by changing production behavior or weakening tests. Push behavior lacks a canonical spec in the inspected inventory.

## Coverage before and after

SDK-only executable-line coverage; include only files under this worktree's `PostHog/`, excluding tests, dependencies, and vendor sources. Compare platforms separately.

| Platform | Before | After | Change |
|---|---:|---:|---:|
| macOS | 13,756 / 15,403 = 89.3073% | 13,748 / 15,403 = 89.2553% | -8 lines, -0.0520 percentage points |
| iOS | 20,214 / 26,194 = 77.1703% | 20,492 / 26,194 = 78.2317% | +278 lines, +1.0613 percentage points |

The denominator is unchanged: 88 macOS SDK files and 147 iOS SDK files. Nine previously unrouted test files now run on iOS. Coverage is observed execution, not evidence that assertions detect regressions. Both baseline suites had failures; the final iOS run also has the unresolved failures below. These numbers must not be described as coverage of fully passing suites.

macOS file-level changes: survey matching -11 covered lines, storage -1, push subscription handler -1, config +5. The audit did not optimize for percentage or add incidental execution merely to increase it.

## Final validation

| Check | Result |
|---|---|
| macOS coverage run | PASS: 173 XCTest + 895 Swift Testing tests (145 suites) |
| iOS coverage run, Xcode 26.6.0 / iOS 26.5 simulator | FAIL: 197 XCTest pass; 1,248 Swift Testing tests (177 suites) finish with three issues in two existing SwiftUI tests |
| Survey mounted UI route | PASS: 7 tests |
| `make format`, `make lint`, `git diff --check` | PASS |
| Upload-symbols shell tests | PASS as prerequisite of macOS coverage run |
| `make testIOSResultParser` | PASS, including crashes, parameterized failures, misleading passing subtotals/retries, and missing logs |
| `make build` | SDK platform builds and platform examples pass; fails later in external SDK client package resolution because local package identity is `posthog-ios-test-audit`, while the fixture requires `posthog-ios`; CocoaPods routes after that point were not reached |
| Mask snapshot runtime gate | BLOCKED: pinned iOS 26.2 runtime is absent; no snapshots regenerated |
| Presentation-mask hosted route, downgrade compatibility, compliance adapter, thread sanitizer | NOT RUN |

The default Xcode/iOS 27 SDK failed the baseline build. Both iOS coverage measurements used `/Applications/Xcode-26.6.0.app/Contents/Developer` and simulator `77D41C2C-541C-4DB7-BABF-92FDDCFCA0DD` instead.

### Remaining iOS failures

`SwiftUITapAutocaptureTests.accessibilityTraitsDetermineLogicalButtonRole(isButton:)` fails for both arguments; `structuralFallbackIsNotAnAriaLabel()` fails once. Their resolver returns nil. Diagnostic runs observed an empty hosting-view accessibility tree (`accessibilityElementCount() == 0`, `accessibilityElements == []`). They passed in the initial baseline run but fail in later isolated runs, after restarting the simulator, and after executing hosted UI tests. Root cause is **not established**; this is not proven to be an SDK regression or solely an environment problem.

Bounded main-actor readiness waits, visible content, and key-window experiments did not repair the issue. All experimental changes to `SwiftUITapAutocaptureTests.swift` were reverted. Assertions were not skipped or weakened. Some diagnostic invocations completed test execution but hung during Xcode finalization and were terminated at the command timeout. Only the completed `after-ios.xcresult` supplies the after coverage measurement; partial-run success banners were not accepted.

### Baseline failures repaired

- Device bucketing: isolated per-token storage, stopped stubs/SDKs, disabled unintended fetch/timer activity, and selected the request for the intended project token. Final macOS and iOS suites pass this test.
- Queue retry clock: observed completion of response processing before advancing the injected clock. Final XCTest suites pass.
- Rage-click privacy: an earlier SDK integration test omitted `close()` and retained singleton ownership. Added teardown; the final full iOS privacy cases pass without resetting production singleton state to hide the leak.

## Implemented disposition overlay

### Core report

- **A1/A2:** fail closed on every nonzero Xcode exit; shell regression tests integrated into `make test`; add all nine missing test files to Xcode membership. The flag-reload time-limit trait remains on the SPM route; the iOS 13-targeted Xcode route cannot compile that iOS 16-only trait.
- **A3 (partial):** request arrays and reset operations use a recursive lock and return snapshots. This does not establish race safety for all mutable handler/configuration/expectation state.
- **A4:** device-bucketing and identity fixtures close their SDKs, stop server stubs, and clean per-token storage.
- **A5/A6:** require observed endpoint requests; assert scheme, host, port, path, and flags query. Header privacy requires actual rewritten/redirected requests and confirms the original authorization header existed.
- **A7–A11:** exercise identity transition before flush, inspect persisted/FIFO payloads, preserve duplicate evidence, bound poison draining, and round-trip distinct observed/event timestamps.
- **A12:** use a genuine self-referencing NSError fixture and assert one serialized exception; the original fixture was acyclic.
- **A15:** require nonnil flag results and nonempty flag collections, check group clearing in the outbound request, require the reset person-property container.
- **A16:** require the configuration callback before checking integration retention.
- **A17:** concurrent queue oracles require exact record count/uniqueness and verify observable delete/reopen behavior.
- **A19 (partial):** correct the disabled-by-default configuration test's name.
- **A20:** parse malformed request bodies safely; stream helper closes/deallocates on every path and stops on EOF/error. New Swift Testing cases cover direct/streamed bodies, negative reads, and zero-byte reads (including stream closure).

### Replay report

- **F1:** decode the actual top-level snapshot array; require the event/properties/session/source before asserting debug-property absence.
- **F2:** require a concrete crash-context notification/status. The seeded lazy-install fixture is buffering, not active; nil no longer passes.
- **F3/F4:** explicitly flush only after both before-send paths have executed; await the second flag reload/lookup before checking deduplication.
- **F5/F6:** remove the runtime opt-out that masked config handling; inspect sanitized properties at `$set`/`$set_once` and require legitimate values survive.
- **F7:** deterministic cached replay eligibility; independently assert start, stop, restart, and consent transitions; close SDKs and clean per-token storage.
- **F8:** test an actual empty trigger array, retaining absent-trigger coverage separately.
- **F9 (partial):** retry-clock tests wait for upload handling. The separate request-arrival-only retention assertions still need a response-processing barrier.
- **F16:** assert latch completion rather than treating timeout return as notification proof.
- **F22:** same fail-closed result-gate repair as core A1.

### Surveys/utilities report

- **A1/A2:** require branching results and enumerate all supported rating buckets; malformed-entry test invokes the production decoder instead of copying it.
- **A3/A4:** establish real async prerequisites and active-window conditions; teardown property-filter SDK/stubs.
- **A5–A7:** execute storage migration and assert data/source/unrelated preservation; use the correct boolean getter; begin with a unique absent directory.
- **A8–A13:** require meaningful stack subjects/exact serialization, concrete display types and collection cardinality, observe prohibited intro callbacks, validate generated UUID/cleanup, and submit the actual question response type.

## Remaining repair work (retained, not fixed)

These are substantive follow-ups, not a claim that every finding was addressed:

- Core **A13/A14/A18**: crash classifier/image nonvacuity and autocapture event identity. **A19** has an additional overstated test name. The remaining shared mock-state races and XCTest failure attribution from Swift Testing helpers need dedicated investigation/TSan.
- Replay **F9–F15**: remaining retry-retention barriers; nonempty-inner-queue flush suppression; real same-filename migration collision; genuinely overlapping migration schedules; observable Retry-After window; delivered-token opted-out unregister control; delivered-marker app-id recovery precondition.
- Replay **F17–F21**: reset sentinel/state oracle, queue-drain completion, negative rage-click observation without expected-success network waiters, bounded/diagnostic synchronization, and plugin declaration names.
- Surveys **A14**: legacy event-test teardown on thrown failure.
- Every U/U-body entry in the linked ledgers remains unverified unless expressly covered above. Policy questions remain open, without production policy changes.

## Mutation evidence

Controlled production mutations made the repaired production-decoder regression and all four rating-branching tests fail. The mutations were restored; `git diff -- PostHog` is empty. Other suggested mutations in the reviewer artifacts are recommendations, **not executed results**. Full passing tests alone are not mutation validation.

## Reproduction and evidence

Use the coverage helper from the worktree root:

```sh
make -f test-audit/coverage.mk auditCoverageMac
DEVELOPER_DIR=/Applications/Xcode-26.6.0.app/Contents/Developer \
  make -f test-audit/coverage.mk auditCoverageIOS \
  AUDIT_SIMULATOR=77D41C2C-541C-4DB7-BABF-92FDDCFCA0DD \
  AUDIT_RESULT=/tmp/unique-audit.xcresult \
  AUDIT_LOG=/tmp/unique-audit-raw.log
```

Use a fresh result-bundle path. Clear/archive old `.profraw` files before macOS measurement; only the two fresh XCTest/Swift Testing profiles were merged for the after report. Export SDK-only summaries with `llvm-profdata`/`llvm-cov` on macOS and `xccov view --report --json` on the iOS result bundle.

Full local evidence is under `/tmp/posthog-ios-test-audit/`:

- `baseline-mac.log`, `baseline-mac.profdata`, `baseline-mac-coverage.json`
- `baseline-ios-stable.xcresult`, `baseline-ios-stable-raw.log`, `baseline-ios-coverage.json`
- `after-mac.log`, `after-mac.profdata`, `after-mac-coverage.json`
- `after-ios.xcresult`, `after-ios-raw.log`, `after-ios-coverage.json`
- `mutation-decoder.log`, `mutation-rating.log`
- `final-format.log`, `final-lint.log`, `final-parser.log`, `final-build.log`, `mask-runtime.log`, `final-survey-ui.log`

Those large raw artifacts are local temporary evidence, not portable repository attachments. Preserve them before cleaning `/tmp` if needed. This README, the three declaration ledgers, and the coverage recipe are retained in the worktree.
