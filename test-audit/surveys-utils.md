# Surveys, storage, and utilities test audit

## Review

- **Correct:** Every test declaration and parameter table in the 21 scoped root Swift files and `PostHogSurveyUITests/SurveyAutoSubmitUITests.swift` was read. Substantial useful coverage exists for persistence, survey identity isolation, real mounted survey interactions, SwiftUI privacy, and tracing interception.
- **Fixed:** Nothing; this was read-only.
- **Findings:** Concrete repairs below. No deletions proposed.
- **Merge verdict: OK with notes** for this audit artifact—not an attestation that the baseline tests pass.

Baseline: `c99f607d81549d5034a9ccd093ccb07fea21f642`. Both working-tree checks reported no changes. No builds, tests, mutations, commits, or publication were performed.

## Contracts and CI

Canonical specifications were read from the supervisor-provided upstream snapshot at `/tmp/posthog-ios-test-audit/specs/openspec/specs/`:

- `surveys`: eligibility, event activation, branching, response compatibility, reset, and intro-screen transitions.
- `persistent-storage`: project isolation, durability, migration, typed values, removal.
- `bootstrap`: initial identity, persisted-identity precedence, identified/device-ID separation.
- `tracing-headers`: exact normalized hostname matching and current identity/session headers.
- `autocapture`: eligible interaction capture, privacy, opt-out, observer lifecycle.
- `exception-event-metadata`: native address serialization.
- `screen`: screen-event semantics; custom-container traversal remains platform-specific.

These specifications do not fully prescribe the current survey resume storage schema, translation attribution, shuffle fallback, or auto-submit implementation. Those cases are evaluated against explicit production behavior and local regression contracts, not invented cross-SDK requirements.

Routing inspected:

- `.github/workflows/test.yml:21–46`: macOS `make test`.
- `Makefile`: `make test` uses `swift test --no-parallel -Xswiftc -DTESTING`; both package manifests discover the `PostHogTests` directory without a scoped-file exclusion.
- `.github/workflows/test.yml:51–75`: iOS `make testOniOSSimulator`, followed by `make testSurveyUI`.
- `PostHog.xcodeproj/project.pbxproj:3674–3760`: all scoped root files are in the test source phase.
- `PostHog.xcodeproj/xcshareddata/xcschemes/PostHog.xcscheme:25–42`: Testing configuration, test target not skipped, `parallelizable="NO"`.
- `PostHogSurveyUI.xcscheme:25–54`: separate hosted XCTest UI bundle.
- `make testSurveyUI` disables parallel testing and checks that at least one `SurveyAutoSubmitUITests` test actually passed.
- iOS-only SwiftUI, tracing, traversal, rendering/resume, WebP, and survey-color coverage does **not** run in the macOS SPM job. The iOS job supplies the relevant route.
- iOS SDK tests retry failures up to three times. CI reports retried tests; passing after retry is not evidence of deterministic behavior.
- No execution evidence or required-check configuration was available to establish that these jobs actually passed or are branch-protection requirements.

## Concrete findings and minimal repairs

### A1 — P1: Rating branching tests can pass when response handling returns nothing

**Evidence:** `PostHogTests/PostHogSurveysTest.swift:2150–2330`:

- `handlesRatingResponseBasedBranchingForScale3`
- `handlesRatingResponseBasedBranchingForScale5`
- `handlesRatingResponseBasedBranchingForScale7`
- `handlesNPSRatingResponseBasedBranchingForScale10`

Every next-state assertion is inside an `if let` without an `else`. Returning `nil` skips the assertions. The detractor and final branches of `handlesSingleChoiceResponseBasedBranching` have the same problem at lines 2132–2146.

**Production:** `PostHog/Surveys/PostHogSurveyIntegration.swift:581–648` returns an optional next question; legitimate rejection paths return `nil`. The branching implementation is at lines 981–1057, with rating buckets in `Surveys/Utils/PostHogSurveyMatching.swift:259–310`.

**Smallest fix:** Make the tests throwing and unwrap every expected next state with `try #require`. Preserve every rating value and path. Use `.openEnded("Yes")` for the final open question instead of `.singleChoice("Yes")` at test line 2143.

**Mutation:** Return `nil` only for rating responses; separately return `nil` for `"Very Dissatisfied"`. Repaired cases must fail at the corresponding required unwrap.

### A2 — P1: Malformed-list regression test copies the implementation instead of testing it

**Evidence:** `PostHogTests/PostHogSurveysTest.swift:2348–2363`, `perElementDecodingSkipsMalformedEntries`, constructs its own `compactMap` decoding algorithm. It never invokes production `decodeSurveys`.

**Production:** `PostHog/Surveys/Utils/PostHogSurveyMatching.swift:72–89` owns resilient list decoding. The fixture contains one valid survey and one rating survey missing `scale`.

**Smallest fix:** Feed the parsed fixture to `PostHogSurveyIntegration().decodeSurveys(from: ["surveys": arrayItems])`; retain the exact valid-ID/count assertions.

**Mutation:** Replace production per-element decoding with atomic `[PostHogSurvey]` decoding or return `[]`. The repaired test must fail. Keep the separate atomic-decoder characterization test as explanatory fixture/model coverage.

### A3 — P1: Negative asynchronous rendering tests do not prove the prerequisite callbacks happened

**Evidence:**

- `waitsForFreshFeatureFlagsBeforeShowingRefreshedSurveys`, `PostHogSurveysTest.swift:1336–1378`, awaits two latches but only asserts an empty render list.
- It does not set `sut.hasActiveSurveyWindow = { true }`, unlike neighboring rendering tests.
- `doesNotUseOlderFlagRefreshForNewerSurveys`, lines 1382–1442, checks request count but not that the two expected flags-loaded callbacks occurred.
- `recoversSurveyRenderingAfterFeatureFlagRefreshFailure`, lines 1500–1542, does not assert that its awaited failure notification occurred before beginning recovery.
- `AsyncLatch.wait`, `PostHogTests/TestUtils/TestPostHog.swift:229–263`, deliberately resumes on timeout **without failing**.

**Production:** `PostHogSurveyIntegration.swift:303–310` requires an active window before rendering. `PostHogSurveyMatching.swift:103–169` drives refresh generations and recovery through remote-config/flag callbacks.

**Smallest fix:** Force the active-window prerequisite in the fresh-flags test. Record synchronized callback observations and require them after each wait. For the stale-refresh case require `loadedCount == 2`; for recovery require the failure callback before changing the server response. Keep rendering assertions.

**Mutation:** Suppress the expected callback; separately bypass fresh-flag gating while a known active window exists. Each repaired test must fail rather than time out to green.

### A4 — P1: Event-activation fixture never tears down its SDK or network stubs

**Evidence:** `PostHogTests/PostHogSurveysTest.swift:645–706`, `TestOnEventPropertyFilters`, is a struct that starts a `MockPostHogServer`, creates an SDK, and installs an integration, with no cleanup in any of its three tests.

`MockPostHogServer.swift:136` onward installs global stubs whose closures capture the server; explicit removal occurs only in `stop()` at lines 527–533.

**Smallest fix:** Convert this fixture to a class with teardown, matching the neighboring `TestMatchPropertyFilters`, or add scoped cleanup in every declaration. Stop/uninstall the manually installed integration and close/reset the SDK before stopping the server. Do not depend on deallocation to remove global HTTP stubs.

**Validation/control:** After each case, verify owned subscriptions/stubs are gone and run the neighboring network suites. A deliberately omitted cleanup should fail a scoped harness assertion. No global-concurrency failure is claimed without execution.

### A5 — P2: Storage merge “detection” test only tests its own fixture

**Evidence:** `PostHogTests/PostHogStorageMergeTest.swift:83–105`, `appGroupContainerMergeDetection`, creates a legacy file and checks that it exists. No SDK migration operation is called.

**Production:** `PostHog/PostHogStorage.swift:107–141` discovers the legacy bundle directory and invokes migration.

**Smallest fix:** Use the existing temporary-directory seam to invoke `mergeLegacyContainerIfNeeded(within:to:)`, then assert the expected destination contents and source removal. Make this declaration cover discovery among unrelated sibling directories so it retains a distinct role alongside `mergeLegacyContainerFunction`.

**Mutation:** Make legacy-source discovery return early or select the wrong bundle directory.

### A6 — P2: Boolean-removal assertion reads the wrong type

**Evidence:** `PostHogTests/PostHogStorageTest.swift:78–88`, `persistsAndLoadsBool`, writes a Boolean but checks `getString(forKey: .optOut) == nil` after removal.

**Production:** `PostHogStorage.swift`, `getTypedValue`, only returns a compatible value or compatible dictionary element. Reading an existing Boolean as `String` already returns `nil`.

**Smallest fix:** Assert `getBool(forKey: .optOut) == nil`; optionally also assert the file no longer exists.

**Mutation:** Make `remove(key:)` a no-op only for `.optOut`. The current deletion assertion survives; the repaired assertion must fail.

### A7 — P2: Folder-creation test does not establish that the folder was absent

**Evidence:** `PostHogTests/PostHogStorageTest.swift:47–59`, `createsFolderIfNoneExists`, uses the shared project token and only removes the folder after constructing storage.

**Production:** `PostHogStorage.swift`, `getAppFolderUrl`, calls `createDirectoryAtURLIfNeeded`; the helper returns immediately for an existing path.

**Smallest fix:** Use a unique project token, require that its project directory does not exist before initialization, and clean up with `defer`.

**Mutation:** Remove the production project-directory creation call. Run the repaired case in isolation and after other storage tests.

### A8 — P2: Stack tests contain fallback, empty-result, and insufficient-oracle loopholes

**Evidence:** `PostHogTests/PostHogStackTraceProcessorTest.swift`:

- `marksInAppWhenInIncludes:19–25`: all modules already receive the default `inAppByDefault == true`, documented in `PostHogErrorTrackingConfig.swift:82–95`.
- `framesHaveInstructionAddresses:104–110`: an empty array passes.
- `stripsPostHogFrames:123–128`: `nil != "PostHog"` passes; SDK modules beginning `"PostHog."` are not checked.
- `respectsStripParameter:151–167`: equality is allowed, so ignoring the parameter passes; both empty arrays also pass.
- `formatsAddressesAsHex:222–237`: only `"0x"` prefixes are checked; wrong values and non-hex suffixes pass.

**Production:** `PostHogStackTraceProcessor.swift:39–101` resolves and strips frames; its SDK-module predicate accepts `"PostHog"` and `"PostHog."` prefixes. `PostHogStackFrame.swift:13,37–61` serializes actual 64-bit addresses.

**Smallest fixes:**

1. Set `inAppByDefault = false` in the includes test.
2. Require nonempty captured frames before per-frame checks.
3. Require a nonnil first module and reject both SDK naming forms.
4. For the strip-parameter test, supply a verified SDK-owned leading address plus a non-SDK address and compare the exact retained suffix. Do not replace `<=` with `<` on the existing fixture: its addresses originate in test code and need not contain SDK-leading frames.
5. Assert literal full strings for all three deliberately different addresses.

**Mutations:** Ignore includes; return empty frames; ignore stripping; serialize `image_addr` from `instructionAddress`; serialize a constant `"0x"` string. The strip fixture needs validation under both static SPM and framework linking before its repair is accepted.

### A9 — P2: Display mapping can silently skip type-specific assertions

**Evidence:** `PostHogTests/PostHogSurveyTranslationsTest.swift:957–969`, `displaySurveyWithoutTranslations`, casts the first two questions using `if let` without failure branches.

**Production:** `PostHog/Models/Surveys/PostHogSurvey+Display.swift:49–77` must map these fixtures to rating and choice display questions.

**Smallest fix:** Require both expected display types, then assert their original text, bounds, and choices.

**Mutation:** Map an untranslated rating or choice to another display-question subtype while preserving survey-level fields.

### A10 — P2: Vacuous collection predicates omit required fixture cardinality

**Evidence:**

- `PostHogSurveysTest.swift:1683–1688`, `doesNotRequireFlagsForMissingKeysOrValues`: `allSatisfy` passes if decoding drops both surveys.
- `PostHogSurveyTranslationsTest.swift:152–194`: `emptyResolutionWhenTargetNil`, `nilWhenNoMatch`, `nilWhenTranslationIsNoop` check only that all question entries are nil.

**Production:** `ResolvedSurveyTranslations.questions` is explicitly positionally aligned with survey questions (`SurveyTranslationResolver.swift:12–19`); the empty resolution allocates one nil per question at lines 96–100.

**Smallest fix:** Require both expected survey IDs in the missing-keys case. Require resolution question count to equal the fixture question count before the nil predicate.

**Mutations:** Drop decoded surveys with missing keys; return `questions: []` only in empty translation resolutions.

### A11 — P2: Intro transition test does not observe prohibited response/shown callbacks

**Evidence:** `PostHogSurveyTranslationsTest.swift:851–862`, `dismissIntroScreenIsPureUITransition`, observes only the close callback.

**Contract/production:** The surveys specification’s “Advancing the intro screen records no response and no event” requirement, and `SurveyDisplayController.swift:53–58`, require a pure UI transition.

**Smallest fix:** Install shown, response, and closed callback counters; snapshot/reset counts after initial `showSurvey`; assert none change during `dismissIntroScreen`, alongside the existing state checks.

**Mutation:** Invoke `onSurveyResponse` or re-invoke `onSurveyShown` from `dismissIntroScreen`.

### A12 — P2: Two storage-manager tests need stronger generation/cleanup proof

**Evidence:** `PostHogStorageManagerTest.swift`:

- `"Generates an anonymousId":22–30` only checks a nonoptional `String` against nil and compares repeat reads. A stable empty or malformed string passes.
- `"Uses the correct fallback value for isIdentified":172–183` persists a distinct ID but omits the cleanup present in preceding cases.

**Production:** `PostHogStorageManager.swift:75–93` generates a UUID-derived string. The same test project token is reused throughout the storage suites.

**Smallest fix:** Require a nonempty parseable UUID in the generation test. Use `defer { sut.reset(true) }` immediately after construction in both cases; adopting that cleanup placement throughout this Quick fixture is a small consistent improvement.

**Mutations/control:** Return `""` on anonymous-ID generation; run the fallback case before `savesFileToDiskAndRemovesFromDisk` and verify no persisted distinct ID leaks.

### A13 — P2: One specific-question test submits an impossible response type

**Evidence:** `PostHogSurveysTest.swift:1998–2018`, `jumpsToSpecificQuestionWhenBranchingToSpecificQuestion`, constructs a rating question but answers it with `.openEnded`.

**Production:** `SurveySheet.swift:57–61` submits `.rating` for rating views. Current specific-question branching ignores response type, which hides the fixture mismatch.

**Smallest fix:** Submit a valid `.rating` response; preserve the 0→2→3 progression and completion assertions.

**Mutation:** Make specific-question branching incorrectly depend on an open-ended response. The corrected fixture should reject that defect.

### A14 — P2: Legacy survey-event tests lose teardown on thrown failures

**Evidence:** `PostHogSurveyEventsTest.swift:672–1075` creates SDKs and performs throwing setup/network waits before the trailing `close/reset`. Class `deinit` at lines 21–23 only stops the server. A thrown `getServerEvents` failure skips SDK cleanup.

**Smallest fix:** Move each existing `close/reset` into a `defer` directly after SDK creation. Scope cleanup of manually installed integrations where needed. Retain all payload assertions.

**Validation/control:** Force the batch wait to fail, then run a subsequent survey test and verify that SDK/integration state was released. This is failure-path isolation repair, not evidence that those payload assertions are weak.

## Decision ledger

**R** retain; **F** repair while retaining the contract; **U** unresolved, retained pending evidence. No declaration is recommended for deletion. Decisions cover every existing parameter row unless explicitly split below. Names are exact Swift function names, or exact Quick `it` strings.

### Stack capture and serialization

`PostHogTests/PostHogStackTraceProcessorTest.swift:19–237`

- **R — in-app classification:** `marksNotInAppWhenInExcludes`, `includesTakesPrecedenceOverExcludes`, `marksSystemFrameworksAsNotInApp`, `usesInAppByDefault`, `usesPrefixMatchingForIncludes`, `usesPrefixMatchingForExcludes`. Detect ignored exclusions, reversed precedence, missing framework exclusions, or exact-only matching.
- **R — usable capture:** `capturesCurrentStackTrace`, `framesHaveModuleInfo`, `symbolicatesAddresses`. Detect empty capture/symbolication or missing module metadata.
- **R — wire dictionary:** `convertsToDictionaryWithRequiredFields`, `omitsNilFields`. Detect renamed/dropped required fields or serialized absent values.
- **F — A8:** `marksInAppWhenInIncludes`, `framesHaveInstructionAddresses`, `stripsPostHogFrames`, `respectsStripParameter`, `formatsAddressesAsHex`.

### Identity storage

`PostHogTests/PostHogStorageManagerTest.swift:22–183`

- **F — A12:** `"Generates an anonymousId"`; `"Uses the correct fallback value for isIdentified"`.
- **R — identity stability and customization:** `"Uses the anonymousId for distinctId if not set"`; `"Can accept anon id customization via config"`. Detect overwritten anonymous identity or ignored configured generator.
- **R — bootstrap application:** `"Seeds the anonymous ID from bootstrap.distinctId on fresh install"`; `"Ignores empty bootstrap.distinctId and falls back to UUID"`; `"Ignores whitespace-only bootstrap.distinctId and falls back to UUID"`; `"Seeds the distinct ID but a fresh device ID when bootstrap.isIdentifiedId is true"`; `"Seeds a property-assigned distinctId as anonymous (isIdentifiedId defaults to false)"`. Detect blank bootstrap adoption, wrong identification state, or person ID leaking into device identity.
- **R — persisted precedence:** `"Does not re-apply bootstrap once an anonymous ID is persisted"`; `"Does not re-apply bootstrap after the user has been identified"`. Separate manager instances test rereading durable identity, not merely cached repeat reads.

### Storage migration and merge

`PostHogTests/PostHogStorageMergeTest.swift:83–285`

- **F — A5:** `appGroupContainerMergeDetection`.
- **R:** `mergeLegacyContainerFunction`—migration entry-point wiring and source removal.
- **R:** `fileMigrationWithExistingFiles`—missing files migrate, destination collisions are preserved, sources removed.
- **R:** `nestedDirectoryMigration`—queue/replay hierarchy and bytes survive.
- **R:** `anonymousIdPreservation`—existing destination identity survives while other state migrates.
- **R:** `removeIfEmptyFunction`—empty directory removed; nonempty directory preserved.

`PostHogTests/PostHogStorageMigrationTest.swift:139–329`

- **R — stable-key migrations:** `migratesDistinctIdFileFromLegacyLocation`, `migratesAnonymousIdFileFromLegacyLocation`, `migratesOptOutFileFromLegacyLocation`, `migratesIsIdentifiedFileFromLegacyLocation`, `migratesPersonProcessingEnabledFromLegacyLocation`, `migratesRegisterPropertiesFromLegacyLocation`, `migratesGroupsFromLegacyLocation`, `migratesSessionReplayKeyFromLegacyLocation`, `migratesEnabledFeatureFlagsFromLegacyLocation`, `migratesEnabledFeatureFlagsPayloadFromLegacyLocation`.
- **R — queue durability:** `migratesEventQueueFilesAndPreservesEventData`, `migratesReplayQueueFilesAndPreservesSnapshotData`. Both use two concrete records; migrated count is asserted before zipped content/name comparisons, so the loops are not vacuous.
- **R — unrelated application data:** `preservesNonPostHogFilesInLegacyDirectory`.

These tests invoke actual `PostHogStorage` initialization and compare pre/post bytes via hashes. The misspelled replay fixture dictionary key and inconsistent sample timestamp do not invalidate their byte-preservation contract.

### Storage reads, paths, backup exclusion

`PostHogTests/PostHogStorageTest.swift:19–272`

- **R — correct namespace:** `returnsTheApplicationSupportDirURL`, `returnsTheAppGroupContainerDirURL`, `writesToDiskInAProjectTokenFolderUnderApplicationSupportDirectory`, `writesToDiskInAProjectTokenFolderUnderGroupContainerDirectory`, `fallsBackToApplicationSupportDirectoryWhenAppGroupIdentifierIsNotProvided`.
- **R — typed persistence/removal:** `persistsAndLoadsString`, `persistsAndLoadsDictionary`, `savesFileToDiskAndRemovesFromDisk`.
- **F — A6:** `persistsAndLoadsBool`.
- **F — A7:** `createsFolderIfNoneExists`.
- **R:** `PostHogStorageBackupTest.excludesProjectFolderFromBackup`—all four `existingFolder × appGroup` Boolean combinations. Covers exclusion of new/existing project directories, preservation of parent metadata, all four queue kinds, queue recreation, durable contents, and reopening storage.

### Survey enum compatibility

`PostHogTests/PostHogSurveyEnumsTest.swift:15–398` — **R all**. Literal expected enums and explicit unknown-value failure branches detect raw-value mapping drift and loss of forward compatibility:

- `surveyTypeHandlesUnknownValues`: popover/api/widget; unknown future type.
- `surveyQuestionTypeHandlesUnknownValues`: open/link/rating/multiple_choice/single_choice; unknown future question.
- `surveyTextContentTypeHandlesUnknownValues`: html/text; markdown.
- `surveyMatchTypeHandlesUnknownValues`: regex/not_regex/exact/is_not/icontains/not_icontains; fuzzy_match.
- `surveyAppearancePositionHandlesUnknownValues`: left/right/center; bottom.
- `surveyAppearanceWidgetTypeHandlesUnknownValues`: button/tab/selector; dropdown.
- `surveyRatingDisplayTypeHandlesUnknownValues`: number/emoji; stars.
- `surveyRatingScaleHandlesUnknownValues`: 3/5/7/10; 4.
- `surveyScheduleHandlesUnknownValues`: once/recurring/always; biweekly.
- `surveyQuestionBranchingTypeHandlesUnknownValues`: next_question/end/response_based/specific_question; conditional_jump.

These are the actual tested rows, not a claim that every currently supported enum value is covered.

### Survey attempts, responses, and events

`PostHogTests/PostHogSurveyEventsTest.swift`

**R — attempt lifecycle/privacy, lines 135–571:**

- `resumedSurveyPreservesSeenHistory` — completion and dismissal.
- `resetBeforeFirstAnswer` — reuse anonymous ID false/true.
- `resetDuringDismissalPreservesNewAttempt`.
- `staleRenderCallbacks` — reset false/true.
- `resetSerializesSurveyState`.
- `resetDuringProgressRead` — load/save/remove/reconcile × new attempt false/true.
- `resetDuringResponseValidation`.
- `clearSavedProgress` — dismissal/reset.
- `invalidSavedProgress` — version/questionIndex/questionOrder/responses.
- `invalidatedDisplayQuestion` — iOS only.
- `resumeEligibility`.
- `customDelegateResume` — legacy/disabled/enabled.
- `staleSurveyProgress` — ended/removed, with iteration transition in both rows.
- `unavailableConfigPreservesProgress`.
- `noProgressBeforeAnswer`.

Contracts: no cross-identity restoration, no stale-render mutation, serialized reset, valid durable progress only, delegate opt-in, retained eligible progress, and distinction between unavailable and authoritative empty configuration. Credible regressions include removed generation checks, clearing another attempt, wrong seen-state handling, or treating network unavailability as authoritative deletion.

**R — partial-response event lifecycle, lines 575–667:**

- `partialResponses` — true/false/nil.
- `partialResponseDismissal`.
- `partialResponseBranching`.

Detect extra/missing events, noncumulative answers, unstable submission IDs, or incorrect completion flags.

**F — A14, retaining the existing event contracts, lines 672–1075:**

- `surveyShownEventHasCorrectNameAndBaseProperties`
- `surveyShownEventWithoutIterationHasCorrectProperties`
- `surveySentEventHasCorrectNameAndResponseProperties`
- `surveySentEventWithSingleResponse`
- `surveyDismissedEventHasCorrectNameAndProperties`
- `surveyDismissedEventIncludesResponsesWhenThereAreAnswers`
- `surveyDismissedEventMarksPartialCompletionFalseWhenThereAreNoAnswers`
- `surveyDismissedEventWithIterationHasCorrectInteractionProperty`
- `baseSurveyEventPropertiesIncludeAllRequiredFields`
- `baseSurveyEventPropertiesExcludeNilValues`
- `surveyInteractionPropertyFormatsCorrectly`

These assert independently spelled event/property names, iteration formatting, answer payloads, partial completion, and interaction markers. The network waits are awaited and throw on timeout; they are not fire-and-forget assertions.

### Restart and shared-storage survey safety

`PostHogTests/PostHogSurveyResumeTest.swift:61–139`

- **R:** `resumeAfterRestart` — `(true,false)`, `(false,false)`, `(nil,false)`, `(true,true)` for partial-response setting/dismissal.
- Contract: a fresh SDK/storage object resumes the saved branch, skips intro, preserves submission and answer-time text, applies new language to new answers, and clears completed/dismissed progress.
- Distinct layer: real default delegate/controller plus restart, beyond direct event-builder tests.

`PostHogTests/PostHogSurveySharedStorageTest.swift:7–275` — **R all**:

- `immutableEpochRevokesSharedProgress`
- `surveyEventsDuringResetIdentityGap`
- `freshSurveyEventIdentity`
- `resetReplacesReadOnlyEpoch`
- `ownerlessProgressIsDiscarded`
- `unavailableSurveyCoordination`
- `sharedSurveyEpochInitialization`
- `sharedStorageResetRejectsStaleProgress` — anonymous ID reuse false/true.
- `sharedStorageResetWaitsForWrite`

Contracts: revoke stale generations even on epoch-write failure, coherent identity during reset, read-only-file replacement, legacy ownerless-record rejection, fail-closed coordination, one durable epoch, and inter-instance reset/write ordering. Production synchronization is in `PostHogStorage.swift:285–358`; progress validation is in `SurveyProgressStore.swift:65–118`.

Caveats: these use independent storage instances in one process, not separate app/extension processes; ownerless progress also carries legacy version 1, so it is not an isolated version-2 missing-field test.

### Survey decoding, matching, refresh, and branching

`PostHogTests/PostHogSurveysTest.swift`

**R — `AutoSubmit`, lines 33–71:**

- `ratingSelection` — true/false × number/emoji.
- `choiceSelection` — true/false × open-choice false/true.
- `rating` — true/false/nil × number/emoji.
- `choices` — true/false/nil × open-choice false/true, each with single_choice and multiple_choice.

Detect lost decoding/display flags and wrong binding callbacks; mounted UI tests separately cover SwiftUI state installation and actual controls.

**R — raw-model decoding, lines 77–503:**

- `surveyDecodesCorrectly`
- `surveyWithUnknownTypeDecodesCorrectly`
- `surveyWithUnknownQuestionTypeDecodesCorrectly`
- `basicQuestionDecodesCorrectly`
- `singleChoiceQuestionDecodesCorrectly`
- `multipleChoiceQuestionDecodesCorrectly`
- `linkQuestionDecodesCorrectly`
- `ratingQuestionDecodesCorrectly`
- `ratingQuestionDecodesWithoutBoundLabels`
- `nextBranchingDecodesCorrectly`
- `endBranchingDecodesCorrectly`
- `specificQuestionBranchingDecodesCorrectly`
- `responseBasedBranchingDecodesCorrectly`
- `responseBasedWithLinkertBranchingDecodesCorrectly`
- `responseBasedWithEmptyValuesBranchingDecodesCorrectly`
- `eventConditionDecodesCorrectly`
- `repeatedEventConditionDecodesCorrectly`
- `eventConditionWithPropertyFiltersDecodesCorrectly`
- `deviceTypeConditionDecodesCorrectly`
- `urlConditionDecodesCorrectly`
- `exactUrlMatchTypeDecodesCorrectly`
- `isNotRegexUrlMatchTypeDecodesCorrectly`
- `iContainsUrlMatchTypeDecodesCorrectly`
- `notIContainsUrlMatchTypeDecodesCorrectly`
- `regexUrlMatchTypeDecodesCorrectly`
- `notRegexUrlMatchTypeDecodesCorrectly`

Contract: wire compatibility, subtype selection, optional fields, branching values, and targeting filters. Regression: renamed keys, wrong enum/subtype, mandatory optional bounds, or dropped nested filters.

**R — match operators, lines 508–593:**

- `matchesRegex`, `matchesNotRegex`: all seven rows—numeric URL, screen prefix, case-sensitive rejection, special characters, empty text, joined-word boundary rejection, separated-word boundary acceptance.
- `matchesIcontains`, `matchesNotIcontains`: case variants, substring, and mismatch.
- `matchesExact`, `matchesIsNot`: case sensitivity and multiple targets.
- `matchesGtLt`: greater/less successes and failures, nonnumeric input.
- `TestMatchPropertyFilters.edgeCases`, `icontainsOperatorWorks`: absent filters, absent property, case-insensitive property values.

**F — A4, lines 673–705:**

- `eventWithPropertiesActivatesSurvey`
- `eventWithNoFiltersActivatesSurvey`
- `partialFilterMismatchPreventsActivation`

Preserve activation/filter assertions; repair fixture lifecycle.

**R — repeatability, lines 750–829:**

- `returnsFalseWhenSurveyHasNoEvents`
- `returnsTrueWhenSurveyHasEventsAndRepeatedActivationIsAlsoTrue`
- `returnsFalseWhenSurveyHasEventsButRepeatedActivationIsFalse`
- `returnsTrueWhenScheduleIsAlways`
- `returnsFalseWhenScheduleIsOnce`
- `returnsFalseWhenScheduleIsRecurring`
- `returnsTrueWhenScheduleIsAlwaysRegardlessOfRepeatedActivation`

Detect wrong event prerequisites or schedule precedence.

**R — matching/refresh integration, lines 1203–1730:**

- `returnsActiveSurveys`
- `refreshesCachedSurveysWhenRemoteConfigLoads`
- `defersShowingSurveysUntilForegroundWindowExists`
- `rendersSurveysWithoutFlagsWhileFlagsLoad`
- `returnsSurveysThatMatchDeviceType`
- `doesNotReturnSurveysWithSelectorCondition`
- `doesNotReturnSurveysWithUrlCondition`
- `returnsOnlySurveysWithEnabledFeatureFlags`
- `matchesLinkedFlagVariant`
- `shouldFilterOutSurveysWhenAnyFlagIsDisabled`
- `shouldIgnoreSurveysWithMissingFeatureFlagsKeysOrValues`
- `returnsSurveysThatMatchInternalTargetingFlags`

`matchesLinkedFlagVariant` retains all 14 rows: matching/wrong/case-different variants; Boolean enabled/disabled/missing flags; `"any"` across variant/true/false/missing; nil/empty variants; nil/empty keys. Every row also includes a separately targeting-blocked survey.

Contracts: active/device/native targeting, refreshed activation maps, foreground deferral, nonblocking unflagged surveys, AND gating, and variant semantics.

**F — A3:** `waitsForFreshFeatureFlagsBeforeShowingRefreshedSurveys`, `doesNotUseOlderFlagRefreshForNewerSurveys`, `recoversSurveyRenderingAfterFeatureFlagRefreshFailure`.

**F — A10:** `doesNotRequireFlagsForMissingKeysOrValues`.

**R — wait periods, lines 1804–1885:**

- `surveyWithoutWaitPeriodIsNotFiltered`
- `surveyWithWaitPeriodPassesWhenNoPreviouslySeen`
- `surveyWithWaitPeriodIsFilteredWhenNotElapsed`
- `surveyWithWaitPeriodPassesWhenElapsed`
- `surveyWithoutWaitPeriodNotAffectedByLastSeenDate`

Detect ignored wait periods, erroneous first-survey rejection, and applying one survey’s wait rule to another. One/ten-day offsets avoid exact threshold timing.

**R — branch navigation, lines 1918–2069:**

- `returnsNextQuestionIndexWhenNoBranching`
- `completesSurveyWithSingleQuestion`
- `endsSurveyWhenBranchingIsEnd`
- `jumpsToLastQuestionWhenBranchingOutOfBounds`

**F — A13:** `jumpsToSpecificQuestionWhenBranchingToSpecificQuestion`.

**F — A1:**

- `handlesSingleChoiceResponseBasedBranching`: Very Satisfied→3, Neutral→2, Very Dissatisfied→1, then final completion.
- `handlesRatingResponseBasedBranchingForScale3`: 1→negative, 2→neutral, 3→positive.
- `handlesRatingResponseBasedBranchingForScale5`: every 1–5 value.
- `handlesRatingResponseBasedBranchingForScale7`: every 1–7 value.
- `handlesNPSRatingResponseBasedBranchingForScale10`: every 0–10 value.

**R:** `atomicArrayDecodeFailsOnMalformedEntry`—documents malformed-fixture/model decoding behavior supporting issue #611; not credited as integration resilience coverage.

**F — A2:** `perElementDecodingSkipsMalformedEntries`.

**R — display model mapping, lines 2400–2499:**

- `mapsPopupDelaySecondsToDisplayAppearance`
- `keepsPopupDelayNilWhenMissing`
- `mapsIntroScreenFieldsToDisplayAppearance`
- `defaultsDisplayIntroScreenToFalseWhenMissing`
- `ratingDisplayDefaultsMissingBoundLabelsToEmptyString`—both bounds missing, lower missing, upper missing.

Detect dropped timing/intro configuration and incorrect optional-label defaults.

### Survey language and display updates

`PostHogTests/PostHogSurveyTranslationsTest.swift`

**R — language precedence, lines 19–76:**

- `overrideWinsOverPersonPropertyAndLocale`
- `trimsOverride`
- `fallsBackToPersonProperty`
- `fallsBackToDeviceLocale`
- `returnsNilWhenNothingSet`
- `ignoresNonStringPersonLanguage`

**R — `TestTranslationMatching`, lines 82–120:**

- `exactMatch`
- `caseInsensitiveOriginalCasing`
- `baseLanguageFallback`
- `prefersExactMatch`
- `noBaseFallbackWithoutHyphen`
- `emptyInputs`—empty/nil dictionary; nil/empty/whitespace target.

Detect wrong precedence, casing, or regional fallback.

**R — resolution/model decoding, lines 126–177:**

- `surveyDecodesTranslations`
- `questionDecodesTranslations`
- `matchesExactLanguage`
- `TestTranslationResolution.baseLanguageFallback`

**F — A10:** `emptyResolutionWhenTargetNil`, `nilWhenNoMatch`, `nilWhenTranslationIsNoop`.

**R — event attribution, lines 275–375:**

- `surveyShownStampsLanguage`
- `surveyShownOmitsLanguageWhenNil`
- `surveySentStampsLanguage`
- `surveySentCarriesTranslatedQuestionText`
- `surveySentPrefersAnswerTimeSnapshot`
- `surveyDismissedStampsLanguage`
- `surveyDismissedOmitsLanguageWhenNil`

Detect missing/spurious language properties and overwritten answer-time snapshots. Fixture teardown is already in `deinit`.

**R — live integration updates, lines 550–733:**

- `languageChangeRetranslatesActiveSurvey`
- `sameLanguageIsNoop`
- `delegateWithoutUpdateSurveyKeepsState`
- `resetRevertsActiveSurveyLanguage`
- `noActiveSurveyIsNoop`
- `showReconcilesPreDisplayLanguageChange`
- `showDoesNotReconcileWhenLanguageUnchanged`
- `sentReportsAnswerTimeLanguagePerQuestion`
- `dismissKeepsAnswerTimeLanguage`

Contracts: actual delegate capability, no redundant updates, pre-display reconciliation, frozen rendered-language attribution, and per-answer text. Main-queue draining is awaited.

**R — controller updates, lines 753–790:**

- `updatePreservesProgress`
- `updateDifferentSurveyIgnored`
- `updateWithNoSurveyIgnored`

**R — intro/delayed rendering:**

- `showSurveyInitializesIntroState`
- `showSurveySkipsEmptyIntro`
- `delayedDisplayShowsUpdatedCopy`

The delayed-display polling loop ends with a positive updated-name assertion; timeout cannot pass with no displayed survey.

**F — A11:** `dismissIntroScreenIsPureUITransition`.

**R:** `displaySurveyApplies`—translated fields plus untranslated fallback fields.

**F — A9:** `displaySurveyWithoutTranslations`.

### Stored responses and choice identities

`PostHogTests/StoredSurveyResponseTest.swift:5–17`

- **R:** `storedResponseRoundTrip`—rating nil/5; open text/nil; single choice A; multiple A+B/nil; link true/false.
- Contract: typed answers survive Codable storage; all relevant response accessors are compared. Round-trip coverage is not evidence of compatibility with every historical serialized schema.

`PostHogTests/SurveyChoiceOrderTests.swift:5–57` — **R all**:

- `disabled`—open choice false/true.
- `shuffled`—open choice false/true.
- `twoChoices`—open choice false/true.
- `edgeCases`—empty, singleton Other, A+Other, duplicate A+A+Other × open choice false/true.
- `SurveyChoiceOrderUpdateTests.update`—all seven explicit growth/shrink/unchanged/empty rows.
- `SurveyChoiceOrderUpdateTests.selection`—all four explicit selection-remapping rows.

Contracts: no lost/duplicated identities, pinned Other, unchanged-order fallback, preservation across translation-driven count changes. Production at `MultipleChoiceOptions.swift:194–223` explicitly enforces the shuffle fallback, so asserting changed order for distinct multi-option fixtures is not an accidental probabilistic test.

### Swizzling

`PostHogTests/PostHogSwizzlerTest.swift:70–137` — **R all**:

- `addsMethodWhenMissing`
- `exchangesWhenImplemented`
- `reinstallAfterUnswizzleOnImplementingClass`
- `addsEmptyCallThroughForMultiArgSelectorWithoutNoop`
- `reinstallAfterUnswizzleOnAddedClass`

Exact invocation logs detect missing callbacks, recursion, wrong original/no-op routing, and contamination of `NSObject`. Separate fixture classes and serialization are intentional, not redundant boilerplate.

### Tracing headers

`PostHogTests/PostHogTracingHeadersTest.swift:98–277` — **R all**:

- `addsHeadersToListedHostsForClassicURLSessionAPIs`—request/URL data tasks, custom-session data task, upload task, download task.
- `normalizesConfiguredHostnamesWhileKeepingExactHostMatching`.
- `addsHeadersToListedHostsForAsyncAwaitURLSessionAPIs`—data request/URL, upload data/file, download request/URL, bytes request/URL.
- `addsHeadersToPostHogURLSessionWrapperAPIs`—data request/URL, upload data/file, download request/URL.
- `appliesRequestModifiersOnlyOnceForURLOverloads`.
- `requestModifiersCoexistWithTaskLifecycleHandlers`.
- `doesNotAddHeadersToUnlistedHostsForURLDataTasks`.
- `omitsSessionHeadersWhenSessionHasEnded`.

Contracts: interception coverage across overloads, exact allow-list, one modifier pass, lifecycle coexistence, absent-session omission. Each network operation is awaited and the captured request required. Positive identity/session getters are appropriate independent state sources for header propagation. Older unsupported OS versions return early; CI uses a current simulator.

### View-controller traversal

`PostHogTests/PostHogViewControllerTraversalTest.swift:38–249` — **R all**:

- `capturesNavigationScreens`—custom container false/true × titled controllers false/true; One/Two/Three screens in every row.
- `nestedContainers`
- `replacesChild`
- `ambiguousChildren`
- `ignoresInactiveChildren`—hidden/transparent/detached/unloaded/hidden ancestor.
- `ignoresInvisibleGeometry`—offscreen/zero width/zero height/clipped ancestor.
- `partiallyVisibleChild`—wrapper clipping false/true.
- `respectsAncestorClipping`—false/true.
- `presentedController`
- `detachedController`

Contracts: correct navigation/tab/presentation precedence, unambiguous visible child selection, geometry/ancestor visibility, no accidental view loading. Production ownership: `PostHog/UIViewController.swift:16–76`. Real window attachment assertions prevent geometry checks from passing on wholly detached fixtures.

### WebP

`PostHogTests/PostHogWebPTest.swift:19–96` — **R all**:

- `"correctly encodes WebP image with -q 0.80"`
- `"correctly encodes WebP image with -q 0.30"`
- `"correctly encodes WebP image with alpha"`
- `PostHogWebPBufferTests.encodedDataOutlivesEncoder`—fixtures 1/0.8, 2/0.3, 3/0.8.

Contracts: pinned encoder output, alpha handling, output survival after encoder cleanup/subsequent encodes, base64 conversion, and copy-on-write ownership. Production transfers native writer ownership at `UIImage+WebP.swift:131–140`. Goldens are useful but sensitive to deliberate encoder/platform changes; no byte-level fixture regeneration was performed.

### Rage-click classifier

`PostHogTests/RageClickDetectorTest.swift:15–160` — **R all**:

- `detectsRageClick`
- `retriggersAfterTemporalReset`
- `retriggersAfterSpatialReset`
- `noDetectionWhenTooFarInTime`
- `noDetectionWhenTooFarInSpace`
- `resetClearsBuffer`
- `customTapCount`
- `customTimeout`
- `customThreshold`

Explicit timestamps/coordinates avoid wall-clock scheduling. Detect threshold/configuration loss, premature capture, repeated capture without reset, and ineffective reset. Production: `Autocapture/RageClickDetector.swift:44–67`.

### SwiftUI tap autocapture

`PostHogTests/SwiftUITapAutocaptureTests.swift:21–481` — **R all**:

**Configuration, wiring, and legacy coexistence**
- `swiftUICaptureDefaultsToDisabled`
- `independentCaptureOptions`—legacy false/true × SwiftUI false/true.
- `legacyHostingGestureStillCaptures`—1/2 taps × 1/2 touches.
- `legacyMarkerKeepsHostingAncestorLabel`
- `hostingNamedUIKitViewKeepsGestureCapture`
- `genuineSwiftUIHostingViewCapturesOnlyThroughTouchObserver`

Detect incorrect opt-in defaults, coupled flags, duplicate capture, legacy regression, and opt-out/close leakage.

**Tap classification**
- `tapClassifierAcceptsShortStationaryTouchOnlyOnce`
- `dragReturningToOriginIsNotATap`
- `longPressCancellationAndInvalidTimeAreNotTaps`
- `edgeReleaseOutsideMarkerDoesNotCapture`
- `pointerTapUsesTheSameCaptureRoute`

Detect duplicate ends, displacement-history loss, accepted long/cancelled/negative-time touches, and mismatched release targets.

**Target identity/privacy**
- `developerMarkerWinsAndDoesNotLabelNeighbor`
- `logicalTargetUsesDeveloperLabelWithoutInventingButtonRole`
- `accessibilityTraitsDetermineLogicalButtonRole`—false/true.
- `structuralFallbackIsNotAnAriaLabel`
- `identifierGetterWithoutProtocolConformanceHonorsExclusion`
- `accessibilityLabelExclusionPreventsStructuralFallback`—exact and mixed-case containing marker.
- `smallestNestedMarkerWins`
- `nativeControlsAreLeftToUIKitCaptureEvenInsideHostingView`
- `noCaptureAndHiddenTargetsAreExcluded`
- `explicitMaskRegionIsExcluded`
- `accessibilityIdentifierNotUserFacingTextIsUsed`
- `unresolvedHostingSurfaceIsSkippedRatherThanCapturingDisplayText`
- `paddedTextFieldRetainsLabel`—0/20 padding.
- `labelMarkerDoesNotTagUnrelatedUIKitControl`
- `labelMarkerFindsMatchingCousinAndClearsSupersededTarget`
- `hitTestLeafStillReceivesItsIndexedFallback`

Detect display-text leakage, wrong accessibility role, ignored exclusions/masks, broad label attribution, and broken label relocation. Production: `Autocapture/SwiftUITapAutocapture.swift:129–308`.

**Lifecycle**
- `observerStartIsIdempotentAndStopRemovesSubscription`—exact subscription counts through enable/disable/re-enable.
- Suite restores the previous global event processor. Tests using real UIKit/accessibility remain OS-sensitive despite meaningful assertions.

### Numeric, date, color, and UUID utilities

`PostHogTests/UtilsTest.swift`

**R — each of `CGFloatTests`, `DoubleTests`, and `FloatTests`:**
- `safelyConvertsNanToInt`
- `safelyConvertsMaxToIntAndDealsWithOverflow`
- `safelyHandlesInfinity`
- `safelyConvertsToIntAndRoundsValue`

Twelve declarations, testing three concrete numeric types. Detect traps on nonfinite/huge values and truncation instead of rounding (`Replay/Float+Util.swift:11–15`).

**R — `SurveyColorTests.normalizesHexColorsByLength`:** all eleven literal rows for `#`, one through nine digits, and long input; checks normalization and alpha.

**R — `DateTests`:**
- `canParseISO8601DateWithMicroseconds`
- `canParseISO8601DateWithMilliseconds`
- `canParseISO8601DateWithSeconds`
- `convertsDateToISO8601StringConsistently`

Detect precision/format/UTC regressions. Literal expected strings prevent a purely self-comparing round trip.

`PostHogTests/UUIDTest.swift:34–94` — **R all**:

- `"mostSignificantBits"`
- `"leastSignificantBits"`
- `"generates lowercase UUID strings"`
- `"formats UUID strings as lowercase"`—uppercase/lowercase/mixed input.
- `"test sorted and duplicated"`—10,000 generated UUIDs.

The first two declarations calibrate **test-only ordering helpers**, not production UUID APIs: their implementations are at lines 101–126, with no production matches. Retain because they provide independently known endian/sign oracles used by the ordering test; do not count them as direct SDK coverage. Remaining declarations detect wrong version/case, duplicates, and nonmonotonic generation. Real clock/randomness remain a limitation.

### Mounted survey UI

`PostHogSurveyUITests/SurveyAutoSubmitUITests.swift:17–84` — **R all**:

- `testNumberAutoSubmitAndConsecutiveQuestionReset`
- `testEmojiAutoSubmitAndConsecutiveQuestionReset`
- `testSingleChoiceAutoSubmitAndConsecutiveQuestionReset`
- `testFalseAndMissingFlagRequireExplicitSubmission`—number/emoji/single × false/missing.
- `testOpenChoiceRequiresTextAndExplicitSubmission`
- `testMultipleChoiceKeepsExplicitSubmission`
- `testOptionalQuestionCanStillSkipWithExplicitSubmission`

These tap actual controls and assert answer sequence, question transition, submit-button availability, and fresh selection state. `Host/SurveyTestApp.swift:61–67` deliberately supplies the branch result and records responses; therefore these tests prove controller/view navigation **given** a branch result, not the SDK branching algorithm. That algorithm remains covered by the repairable unit cases above.

The emoji selector depends on 48×48 control geometry (`SurveyAutoSubmitUITests.swift:117–124`), a maintenance sensitivity rather than a false-positive finding.

## Remaining uncertainty and follow-up validation

- **Unread test declarations/parameter rows in scope: none.**
- Production and support code were read to substantiate the findings and retained contracts, but this was not an exhaustive audit of every production dependency, vendor implementation, or every referenced binary/JSON fixture.
- Upstream specifications came from the parent’s downloaded `main` snapshot; its exact commit was not independently established.
- Git history was unavailable beyond the supplied baseline and comments such as issue #611. No historical regression execution is claimed.
- No baseline test outcomes were available. All mutation suggestions are **proposed**, not run.
- Stack stripping needs a linking-mode-safe fixture; static SPM and framework module identities may differ.
- Shared-storage locking tests establish same-process multi-instance behavior, not a real cross-process app-group run.
- Semaphore negative windows establish practical contention checks but remain scheduler-dependent.
- Several suites use shared project tokens and application-support roots; broad cleanup and parallel execution outside the inspected routing remain isolation risks.
- `getNextQuestion` is a test seam that assigns the active index before dispatch (`PostHogSurveyIntegration.swift:1106–1111`). Branch tests must not be credited with validating production rejection of out-of-order indices.
- Native/UI runtime coverage on tvOS, watchOS, visionOS, older iOS, and physical devices was not established by the inspected CI jobs.
- The atomic-decoder test, UUID helper tests, and host-supplied branch callback are explicitly distinguished from direct production regression coverage.

Parent validation after coherent repairs:

1. `make test filter=PostHogStackTraceProcessorTest`
2. `make test filter=PostHogStorage`
3. `make test filter=PostHogSurveysTest`
4. `make test filter=PostHogSurvey`
5. `make testOniOSSimulator`
6. `make testSurveyUI`
7. Controlled isolated mutations described above, then restoration and a passing rerun.
8. Repository-wide `make test`, `make lint`, and required builds, under parent ownership.