# Replay-range test audit

## Review

- **Correct:** The scoped suites preserve valuable privacy, persistence, lifecycle, and concurrency coverage. Particularly strong examples include real screenshot/touch emission, metadata recovery after failed masking, identity-based queue acknowledgements, and presentation-geometry preconditions.
- **Fixed:** None. This was read-only; all checkout edits are parent-owned.
- **Findings:** Concrete repairs are listed below. No deletions or consolidations are proposed.
- **Merge verdict: OK with notes** for this audit artifact, **not an exhaustive test-validation or patch signoff**. Unfinished verification is explicitly **U — retain**.

## Scope and limitations

Baseline supplied: `c99f607d81549d5034a9ccd093ccb07fea21f642`.

Scope: the **30 root Swift test files** from `PostHogMaskFailClosedTest.swift` through `PostHogSessionReplayTest.swift`, inclusively by basename. Helpers and production files were inspected as supporting evidence.

Read the audit `SKILL.md` and sibling `CAMPAIGN.md`. Relevant canonical specifications were supplied locally under `/tmp/posthog-ios-test-audit/specs/openspec/specs/`, including replay privacy, ingestion controls, debug properties, start/stop/status, session management, remote configuration, retry queues, capture, identify, screen, consent, person profiles, and before-send.

**No commands, tests, builds, mutations, edits, commits, or publishing were performed.** The final checkpoint patch was not reviewed. The initial working tree was clean; the last inspected delta contained parent-owned changes outside this scope.

Some earlier large reads were truncated. The ledger therefore distinguishes verified retention/repair decisions from declarations whose complete body or parameter verification remains unfinished. **Do not treat U entries as approved for deletion or as established defects.**

---

## Concrete findings and smallest repairs

### F1 — P1: Snapshot privacy assertion always examines an empty dictionary

**Location:** `PostHogTests/PostHogSDKTest.swift:407–430`, `"excludes $recording_status and $sdk_debug_* properties from $snapshot events"`.

The test parses `/s/` using `parseRequest`, which casts the JSON root to a dictionary (`TestUtils/MockPostHogServer.swift:563–575`). Production sends a **top-level array** (`PostHog/PostHogApi.swift:203–224`). Consequently, `body` is nil and line 427 substitutes `[:]`; both absence assertions pass regardless of the actual snapshot properties.

**Smallest fix:** Decode the decompressed body as `[[String: Any]]`; require exactly the intended `$snapshot` event and a properties dictionary; assert its session/source fields before checking absence of debug keys.

**Mutation:** Add `$recording_status` and one `$sdk_debug_*` property to a snapshot. The repaired test must fail. This directly protects the canonical replay-debug-properties exclusion contract.

### F2 — P1: Missing crash-context notification passes lazy-install test

**Location:** `PostHogTests/PostHogSessionReplayRemoteConfigBufferTest.swift:613–637`, `crashContextAfterLazyInstall()`.

Both the wait and assertion compare optional status with `"disabled"`. **nil != `"disabled"` is true**, so no notification—or a context lacking the key—passes immediately.

Production deliberately refreshes context after assigning the lazy integration (`PostHog/PostHogSDK.swift:3113–3116`).

**Smallest fix:** Await a present, expected status for the seeded fixture; require the context and status before asserting. Establish whether this fixture should report `active` or `buffering`, rather than accepting any non-disabled string.

**Mutation:** Suppress the post-install context notification or omit `$recording_status`; require failure.

### F3 — P1: Before-send drop cases can finish before the target event is uploaded

**Location:** `PostHogTests/PostHogSDKTest.swift:1318–1360`, generated `"skips the event"` and `"preserves other events"` declarations.

All seven input rows configure `flushAt: 1`, capture `other_event` first, then trigger the target. The first request can satisfy the waiter before a wrongly retained target reaches a later request. Counting the requests presently available is not proof that the target was dropped.

**Affected rows:** `capture`, `screen`, `autocapture`, `identify`, `group`, `alias`, `get feature flag`.

**Smallest fix:** Disable threshold flushing for the arrangement, invoke both inputs, then explicitly flush after both capture paths have completed. Assert the complete resulting event sequence is exactly `["other_event"]`.

**Mutation:** Bypass the nil-returning hook for each target. Each repaired parameter case must fail.

### F4 — P1: Feature-flag reload deduplication is asserted before the second lookup

**Location:** `PostHogTests/PostHogSDKTest.swift:1268–1285`, `"does not capture $feature_flag_called again when getFeatureFlag called twice after reloading flags"`.

The second lookup is inside the asynchronous reload callback, but the flush sentinel is captured outside it. The first lookup plus sentinel can complete the asserted batch before the second lookup runs.

**Smallest fix:** Await the reload callback and second lookup before capturing the sentinel; explicitly flush the complete sequence with a high threshold.

**Mutation:** Clear flag-call deduplication on every reload. Require the extra `$feature_flag_called` event to fail the test.

### F5 — P1: Configuration opt-out test overwrites the condition it claims to test

**Location:** `PostHogTests/PostHogSDKTest.swift:555–564`, `"sets opt out via config"`.

Calling `sut.optOut()` before asserting means a regression ignoring `config.optOut` still passes.

**Smallest fix:** Remove the runtime `optOut()` call and assert immediately after setup. The isolated `PostHogOptOutPersistenceTest.configDecidesWithoutPersistedState()` already provides a good independent model; retain both until ownership is deliberately reconciled.

**Mutation:** Ignore `config.optOut` during setup.

### F6 — P1: Sanitization checks inspect the wrong property level

**Location:** `PostHogTests/PostHogSDKTest.swift:1017–1047`, `"sanitize properties"`.

`test2` and `test3` are supplied through `userProperties` and `userPropertiesSetOnce`, but checked at the event-properties root. Production nests these under `$set` and `$set_once`; see `PostHog/PostHogSDK.swift:650–651,1845–1846`. `test4` is never supplied.

**Smallest fix:** Require `$set` and `$set_once`, assert `userProp`/`userPropOnce` survive, and inspect `test2`/`test3` inside those dictionaries. Supply a meaningful `test4` fixture or remove only that unsupported assertion—not the test.

**Mutation:** Preserve an otherwise-invalid nested value as a serializable sentinel. Root-only checks would miss it; repaired nested checks must fail.

### F7 — P1: Replay stop is hidden by opt-out cleanup

**Location:** `PostHogTests/PostHogSessionReplayTest.swift:48–74`, `sessionReplayToggle()`.

The test calls `stopSessionRecording()`, then `optOut()`, and only then checks that the integration is nil. Opt-out uninstalls integrations independently. Production stop only calls `replayIntegration.stop()` (`PostHog/PostHogSDK.swift:2764–2774`); it does not remove the integration.

**Smallest fix:** Seed deterministic replay eligibility. Assert active → inactive immediately around stop, before opt-out, then active after restart. Keep consent transitions as separately observed steps if desired. Use `defer { sut.close() }` in this test and `manualSessionReplayStart()`; `reset()` is not equivalent teardown.

**Mutation:** Make `stopSessionRecording()` a no-op. The repaired toggle must fail before opt-out.

### F8 — P1: “Empty triggers” supplies nil, not an empty array

**Location:** `PostHogTests/PostHogSessionReplayEventTriggersTest.swift:205–213`, `emptyTriggersNoWaiting()`.

The test calls `getSut(eventTriggers: nil)`, duplicating the absent-config case instead of testing a present empty list.

**Smallest fix:** Pass `[]`, retaining the nil case at line 61.

**Mutation:** Treat a present empty trigger list as a pending gate while leaving absent triggers unrestricted.

### F9 — P1: Retry-retention tests accept the pre-response queue state

**Location:** `PostHogTests/PostHogQueueTest.swift:207,224,241,438`:

- `"retains batch on retriable 5xx and does not change cap"`
- `"retains batch on HTTP 429 and does not change cap"`
- `"retains batch on HTTP 408 (request timeout is retriable) and does not change cap"`
- `"retains batch on a network error"`

The server waiter proves request arrival. Depth and cap already have their expected values before the response handler runs; `toEventually` can succeed immediately. Production disposition is applied later by `sendBatch`/`handleResult` (`PostHog/PostHogQueue.swift:143–157`).

**Smallest fix:** Await an observable response-processing transition, such as retry count becoming one, before checking retained identities/depth/cap. The controlled sender used by `receivedHTTPDisposition` is an alternative already present in this file.

**Mutation:** Acknowledge/drop a retryable batch after request receipt. The repaired test must fail.

### F10 — P1: Replay flush suppression has an empty inner queue

**Location:** `PostHogTests/PostHogReplayQueueTest.swift:148–159`, `flushSuppressedWhenBuffering()`.

The fixture only populates the buffer. Removing the suppression guard still calls `innerQueue.flush()` on an empty queue and leaves buffer depth unchanged. Production guard: `PostHog/Replay/PostHogReplayQueue.swift:79–85`.

**Smallest fix:** First enqueue a real inner-queue event while not buffering, then enable buffering, add buffered data, and invoke flush. Prove no inner-queue send occurs while held; release the hold and prove the same event can send.

**Mutation:** Remove the buffering guard in `flush()`.

### F11 — P1: Duplicate-filename test creates distinct filenames

**Location:** `PostHogTests/PostHogReplayBufferQueueTest.swift:194–221`, `migrateHandlesDuplicates()`.

Two `add` calls separated by a sleep produce distinct UUIDv7 filenames. No destination collision is constructed. Production has a specific destination-exists branch (`PostHog/Replay/PostHogReplayBufferQueue.swift:73–80`).

**Smallest fix:** Read the buffered filename, create a target file with the **same basename**, initialize/reload the target index, and assert the intended existing-target preservation and source removal. Assert payload identity, not merely readability.

**Mutation:** Overwrite the destination on collision, or leave a stale source/index entry.

### F12 — P1: Two “during migration” tests are entirely sequential

**Location:** `PostHogTests/PostHogReplayBufferQueueTest.swift:225–294`:

- `concurrentWritesDuringMigration()`
- `writesPreservedDuringMigration()`

Both complete `migrateAll` before issuing every supposed concurrent write.

**Smallest fix:** Preserve these useful sequential post-migration checks, but arrange overlapping work with bounded synchronization, then assert the exact complete payload set. Existing task-group tests in the same file protect additional schedules but do not make these particular inputs concurrent.

**Mutation:** Lose target additions during migration/index reload. The repaired overlapping schedule must detect it.

### F13 — P1: Retry-After test does not observe the retry window

**Location:** `PostHogTests/PostHogPushNotificationTest.swift:781–790`, `honorsRetryAfterHeader()`.

The header is `"1"` and the test only checks that the first failure increments retry count and produced one request. It never attempts a retry inside or after the window. Production selects `info.retryAfter ?? retryDelay(...)` and compares its deadline against `Date()` (`PostHog/PushNotifications/PostHogPushSubscriptionHandler.swift:587,832–833`).

**Smallest fix:** Use a header distinguishable from normal initial backoff; prove a retry is suppressed before that deadline and accepted after it. Prefer a narrowly injectable clock or explicit deadline observation over a long real sleep. Merely overriding global `now` will not control the current `Date()` calls.

**Mutation:** Ignore `Retry-After` and always use normal backoff.

### F14 — P1: Opted-out unregister test has no token to unregister

**Location:** `PostHogTests/PostHogPushNotificationTest.swift:1453–1462`, `sdkUnregisterNoRequestWhenOptedOut()`.

An opted-out SDK is created without a persisted subscription. The handler’s no-record guard also suppresses a request, even if the public opt-out guard is broken. See handler `unregisterCurrentToken()` at `PostHog/PushNotifications/PostHogPushSubscriptionHandler.swift:394–396`.

**Smallest fix:** After opted-out setup has completed, seed a valid delivered subscription and invoke the public API; observe a bounded completed-work boundary and verify no DELETE. Include an otherwise-identical allowed control.

**Mutation:** Remove the public opt-out short-circuit while leaving the no-record guard intact.

### F15 — P1: App-id recovery test never seeds the delivered marker it promises to clear

**Location:** `PostHogTests/PostHogPushNotificationTest.swift:2377–2392`, `reregistersWhenAppIdBecomesRegisterable()`.

The fixture starts with `appIds = []`, so the initial subscription is persisted **undelivered**. The later POST proves retrying an undelivered record, not clearing a delivered marker after the server previously discarded a token. Production documents and implements that recovery in `onPushAppIdsChanged` (`PostHog/PushNotifications/PostHogPushSubscriptionHandler.swift:497–500`).

**Smallest fix:** Seed or establish a delivered subscription for the current identity, assert that precondition, then announce newly registerable app-id eligibility. Assert a new POST and renewed delivered state.

**Mutation:** Remove delivered-marker clearing but retain the ordinary retry call.

### F16 — P1: Timeout-opening latch is mistaken for callback completion

**Locations:**

- `PostHogTests/PostHogRemoteConfigTest.swift:338–353`, `surveyRefreshCoalescesWithMatchingRequest()`.
- `PostHogTests/PostHogRemoteConfigTest.swift:954–976`, `disablesAutocaptureExceptionsFromRemoteConfigDict()`.
- `PostHogTests/PostHogRemoteConfigTest.swift:1010–1032`, `disablesAutocaptureExceptionsWhenErrorTrackingKeyIsMissing()`.
- `PostHogTests/PostHogSamplingTest.swift:251–272`, `remoteConfigWithoutSampleRate()`.

`AsyncLatch.wait()` deliberately resumes on timeout without recording failure (`TestUtils/TestPostHog.swift:229–263`).

The coalescing test only checks one request; missing either callback still passes after timeout. The negative-config tests assert the already-default false/nil value, so an unprocessed response can pass.

**Smallest fixes:**

- Count and assert both coalesced completions.
- Prove the specific configuration response completed.
- For actual disable/clear contracts, start from enabled/non-nil state and assert the transition; do not silently redefine a default-state test as a transition test.

**Mutations:** Drop the survey completion; skip remote-config application; retain the old enabled value.

Related unresolved timing: `shouldNotClearFlagsIfHasFeatureFlagsKeyIsMissing()` explicitly uses a two-second settle at lines 289–299. A timeout is not proof that the branch has run. Retain pending a completion boundary after the clear-or-keep decision.

### F17 — P2: Filesystem reset test asserts only that the parent directory exists

**Location:** `PostHogTests/PostHogSDKTest.swift:1152–1163`, `"reset deletes posthog files but not other folders"`.

No unrelated folder/sentinel is created, and no resettable SDK value is checked. A no-op reset satisfies the assertion.

**Smallest fix:** Create an unrelated sibling sentinel and known resettable SDK user state. Verify the sentinel survives and the user state resets. Respect the intentional retention of project configuration and durable queues; do not interpret the title as requiring deletion of every SDK file.

**Mutation:** Delete an unrelated sibling, or skip resetting the chosen user-state key.

### F18 — P2: Request arrival is not queue-drain completion

**Location:** `PostHogTests/PostHogReplayQueueTest.swift:163–185`, `flushWorksWhenNotBuffering()`.

The snapshot waiter completes on server request arrival, followed immediately by `#expect(queue.depth == 0)`. The success response may not yet have been processed.

**Smallest fix:** After proving request arrival, await queue depth zero with an asserted timeout; disable the queue timer for this explicitly driven flush and defer `queue.stop()`.

### F19 — P2: Negative rage-click tests wait for a request that should never arrive

**Location:** `PostHogTests/PostHogRageClickIntegrationTest.swift:75–88,119–132`:

- `noRageClickWhenTooFarApart()`
- `noRageClickWithoutScreenNameAndElementId()`

They use `server.start(batchCount: 0)` followed by `getBatchedEvents(server)` with its default `failIfNotCompleted: true`. The helper waits for a request-fulfilled expectation and calls `XCTFail` on timeout (`TestUtils/TestPostHog.swift:39–45`).

**Smallest fix:** Use an explicit negative-event observation strategy: a bounded no-event check with a valid positive control, or a flushed sentinel after processing taps. Do not use an expected-success request waiter to prove absence. This also avoids relying on XCTest failure reporting inside Swift Testing.

### F20 — P2: Unbounded/silent synchronization weakens diagnostics

- `PostHogTests/PostHogMaskPresentationPrivacyTest.swift:325–357`, `slideTransitions()`: both animation-completion loops are unbounded. Keep the valuable `samples > 0` assertion; add a monotonic deadline and assert completion separately for presentation and dismissal.
- `PostHogTests/PostHogPushNotificationTest.swift:1988–2034`, `openDedupeCapturesOnceWhenReportsRace()`: outer semaphore waits are unbounded, while the clock’s 0.2-second parking timeout is ignored. The forced race can silently disappear or the test can hang. Use bounded asserted waits and guaranteed release/cleanup.
- Several throttled multicast tests use 50 ms sleeps as positive completion barriers, despite asynchronous main-queue delivery. Use completion latches/condition waits, preserve explicit negative windows, and synchronize reads as well as writes.

### F21 — P2: Two plugin declarations describe the opposite of their fixtures

**Location:** `PostHogTests/PostHogSessionReplayPluginTest.swift:118–137`:

- `networkPluginDisabledWhenNetworkTimingIsNull()`
- `networkPluginDisabledWhenNetworkTimingIsNSNull()`

Both set `network_timing: true`, make **`web_vitals_allowed_metrics`** null, and assert enabled.

**Smallest fix:** Rename the declarations/display names to reflect the useful existing contract: unrelated null web-vitals settings must not disable network timing. Add actual null `network_timing` cases only as separate cases.

### F22 — P1: CI result salvage can convert incomplete test runs into success

**Location:** `scripts/check-ios-test-result.sh:24–55`; invoked by `Makefile:99–106`.

For a nonzero build/test status, the script:

1. Accepts any `Executed N tests, with 0 failures` line when no recognized failed-name line exists; that can describe only one completed subset, even zero tests.
2. Matches failures against successes by **display name only**, losing suite and case identity.

The scoped multicast suites alone contain repeated display names such as `"Multiple subscribers all receive value"`.

**Smallest fix:** Preserve nonzero status unless authoritative result-bundle data proves all intended tests completed with acceptable final outcomes. If retry salvage is retained, match stable fully qualified test/case identifiers and independently reject build, crash, discovery, and infrastructure failures.

**Control:** Feed a nonzero-status run containing a successful subset plus an undiscovered/crashed suite; it must stay failed. Also test one failed suite and a different successful suite sharing a display name.

This is supporting CI evidence, not a claim that a particular current CI run was falsely green.

---

## Policy uncertainties — retain, do not reconcile in this audit

- **U-privacy:** Native explicit-mask precedence differs from the supplied canonical privacy specification’s explicit-unmask precedence. Relevant tests include `PostHogMaskScenarioTest.noMaskChildInsideMaskedContainer`, `maskChildInsideNoMaskContainer`, snapshot scenarios 6/7, and the explicit-reporter assertion in presentation `noMaskAncestorAboveCover`. Production explicitly documents its mask-winning behavior in `PostHog/SwiftUI/PostHogMaskViewModifier.swift`. The supervisor directed retaining these pending policy reconciliation.
- **U-screen:** `PostHogScreenNameTest.swift:81` pins properties overriding the explicit `screen("Home")` argument. Current production agrees; supplied screen specification Behavior 3 says the explicit argument wins. Retain pending reconciliation.
- **Not a confirmed discrepancy:** `firstConfigFlagOffDoesNotStopCapturer()` concerns internal integration activity. Public `isSessionReplayActive()` also gates session/remote eligibility (`PostHogSDK.swift:2833–2844`). Do not rewrite the internal assertion merely because the public getter should be false.
- **U-push-spec:** No canonical push capability was identified in the supplied specification set. Push findings above rely on concrete fixtures and production behavior, not asserted cross-SDK conformance.

---

## Declaration ledger

**Notation**

- **R:** Retain. The short description gives the contract and credible regression.
- **F:** Retain and repair; numbered references identify the evidence and smallest fix above.
- **U:** Retain pending missing evidence or policy reconciliation.
- **U-body:** Complete body/fixture verification was not established after truncated earlier reads. Listed names identify intended behavior, not a verified finding.
- Line numbers are declaration locations in the inspected checkout. Functions are shown without trailing `()` unless parameters matter.
- Grouped rows assign the stated status to **every explicitly named declaration**, not to unspecified tests.

### 1. `PostHogMaskFailClosedTest.swift`

Production owner: `RRWireframe` and replay snapshot collection/emission. These unit/queue tests complement—not replace—rendered goldens.

| Line | Declaration | Decision / contract and regression |
|---:|---|---|
| 114 | `maskRenderFailureDropsTheFrame` | R — failed masked render emits no base64 and marks failure; catches raw-image fallback. |
| 127 | `unmaskedScreenshotStillSends` | R — ordinary screenshots remain sendable; catches blanket frame dropping. |
| 139 | `maskedScreenshotSends` | R — successful masked render produces an image; catches erroneous failure flag/drop. Pixel correctness belongs to goldens. |
| 207 | `firstFrameFailurePreservesMetadata` | R — `[failure, success]` produces `[4,2]`; catches metadata consumed by failed frame. |
| 212 | `queuedRecoveryIncludesMetadata` | R — queued `[failure, success, success]` produces `[[4,2],[2]]`; catches enqueue-time metadata race. |
| 217 | `laterFailureDoesNotResendMetadata` | R — success/failure/recovery does not duplicate initial metadata. |
| 222 | `queuedSuccessesSendMetadataOnce` | R — two queued successful frames produce one metadata event. |
| 227 | `failedEpisodeOpeningPreservesMetadata` | R — failed new bridge episode retains its metadata obligation. |
| 234 | `zeroSizeNonClippingParentIsTraversed` | R — visible overflowing text remains masked; catches bounds-only pruning. |
| 248 | `zeroSizeClippingParentIsSkipped` | R — invisible clipped subtree produces no stale masks. |
| 261 | `inheritedMaskSurvivesSiblingTraversal(zeroSizeFirstChild:)` | R — **true/false** rows; preceding zero/sized sibling cannot clear inherited masking. |
| 279 | `inheritedMaskRespectsScopeAndNoMask` | R — accessibility masking stays scoped and respects accessibility no-mask; catches sibling leakage. |
| 297 | `collapsingClippingParentUsesRenderedBounds(presentationIsVisible:)` | R — **true/false** rows; presentation visibility, not destination bounds, controls traversal. |
| 316 | `fadingOutParentIsTraversed` | R — visible fading content remains masked. |
| 329 | `transparentParentIsSkipped` | R — fully transparent content produces no mask. |

### 2. `PostHogMaskPresentationPrivacyTest.swift`

Production owner: presentation-aware mask collection. The harness requires visible, nonempty target geometry before testing coverage; this prevents empty-rectangle “privacy” passes.

| Line | Declaration | Decision / contract and regression |
|---:|---|---|
| 128 | `normalScreen` | R — explicit reporter, label, input, image all covered; catches lost heuristic categories. |
| 137 | `explicitAndSecureWithGlobalsDisabled` | R — explicit and secure-field privacy survives disabling global heuristics. |
| 150 | `insideOpaqueCover(fullScreen:)` | R — **false/true** (`overFullScreen/fullScreen`); cover PII masked and presenter masks recover. |
| 165 | `mediumSheet` | R — exposed presenter and sheet PII masked; asserts exposure precondition. |
| 180 | `partialCover` | R — partial cover cannot suppress visible presenter masks. |
| 194 | `nestedCovers(transparentTop:)` | R — **false/true**; nested presentation/dismissal restores correct privacy at each level. |
| 255 | `swiftUISensitiveCover` | R — requires four realized probes before iterating; catches lost SwiftUI text/input/image/explicit coverage. |
| 295 | `transparentSwiftUIFullScreenCover` | R — visible presenter plus clear-cover content masked; catches inappropriate presenter suppression. |
| 325 | `slideTransitions` | F20 — preserve real-transition sampling; bound completion waits. |
| 361 | `fadingReporterAncestor` | R — rendered opacity precondition; prevents premature explicit-mask removal. |
| 375 | `fadingCover` | R — translucent rendered cover cannot hide PII. |
| 395 | `translucentCoverAncestor` | R — ancestor opacity affects occlusion. |
| 411 | `animatedCoverState(property:)` | R — **background, rotation, cornerRadius, ancestorOpacity**; each requires unsafe rendered state, then checks settled suppression. |
| 451 | `maskedCoverAncestor` | R — ancestor layer mask invalidates opaque-rectangle occlusion. |
| 468 | `noCaptureAncestorAboveCover` | R — inherited accessibility no-capture reaches presented plain views. |
| 486 | `noMaskAncestorAboveCover` | U-privacy — heuristic no-mask plus explicit reporter behavior is intentionally pinned; reconcile specification separately. |
| 504 | `invisibleSibling(visibility:raised:)` | R — Cartesian **hidden/transparent × false/true**; visible control → hidden suppression → restored coverage. |
| 537 | `animatedZPosition(animateCover:)` | R — **false/true**; paused animation proves rendered and model z-orders differ. |
| 576 | `fadingSibling` | R — intermediate rendered opacity retains masks, fully faded sibling does not veto occlusion. |
| 599 | `rotatedCover` | R — bounding-box containment alone cannot prove actual coverage; visible-point precondition is explicit. |

### 3. `PostHogMaskPresentationTest.swift`

| Line | Declaration | Decision / contract and regression |
|---:|---|---|
| 90 | `fullScreenCoverDropsMasksBehindIt` | R — covered masks disappear and return on dismissal; catches stale/never-restored masks. |
| 109 | `opaqueCoverDropsMasksBehindIt` | R — attached-but-occluded presenter is handled correctly. |
| 124 | `transparentCoverKeepsMasks` | R — transparent cover cannot suppress presenter privacy. |
| 132 | `roundedCoverKeepsMasks` | R — rounded corners invalidate rectangular full occlusion. |
| 146 | `siblingAboveCoverByZPositionKeepsMasks` | R — rendered order overrides subview order. |
| 166 | `invisibleSiblingAboveCoverDropsMasks(hidden:)` | R — **true/false** hidden/alpha-zero rows, with visibility restored as control. |
| 187 | `hiddenAncestorDropsMask` | R — ancestor hide/unhide updates reporter masks. |

### 4. `PostHogMaskScenarioTest.swift`

| Line | Declaration | Decision / contract and regression |
|---:|---|---|
| 39 | `maskOnText` | R — nonempty leaf-sized mask; catches screen-wide overcollection or missing reporter. |
| 55 | `maskOnImage` | R — image-sized explicit mask; catches wrong reporter extent. |
| 72 | `maskOnContainer` | R — full container extent, not a single leaf. |
| 94 | `noMaskChildInsideMaskedContainer` | U-privacy. |
| 113 | `maskChildInsideNoMaskContainer` | U-privacy. |
| 135 | `perRowLeafMasks` | R — nonvacuous visible-row count plus narrow masks. |
| 147 | `wholeRowMasks` | R — nonvacuous visible-row count plus full-row width. |
| 161 | `perRowMasksTrackScroll` | R — scroll view required; before/after positions differ. |
| 166 | `wholeRowMasksTrackScroll` | R — same live-geometry contract for full-row masks. |
| 304 | `exactlyAtTolerance` | R — inclusive still threshold; catches comparator boundary regression. |
| 314 | `justOverTolerance` | R — drift band reachable above still threshold. |
| 323 | `exactlyAtDriftBudget` | R — inclusive drift boundary. |
| 332 | `justOverDriftBudget` | R — motion beyond budget, no drift inflation. |
| 342 | `nilBefore` | R — unknown geometry fails closed to motion. |
| 350 | `nilAfter` | R — same for missing later sample. |
| 358 | `countMismatch` | R — inconsistent owner counts cannot be treated as settled. |
| 371 | `differentOwnerSet` | R — same count is not identity equivalence. |
| 381 | `permutedOrderIdenticalGeometry` | R — owner identity, not index, pairs samples. |
| 398 | `duplicateOwnerFailsClosed` | R — duplicate before-owner does not trap or settle. |
| 415 | `duplicateOwnerInAfterFailsClosed` | R — duplicate after-owner cannot conceal a missing owner. |
| 435 | `thresholdsAreOrdered` | R — drift remains reachable; no deletion merely because constants are referenced. |
| 443 | `bandsPickRenderer` | R — fidelity for still/drift, presentation renderer for motion. |
| 450 | `emptyArraysStill` | R — legitimate no-mask geometry settles. |
| 457 | `driftInflationCoversSweepInAfterOrder` | R — swept coverage and owner ordering; catches wrong pairing/under-inflation. |
| 486 | `driftInflationCoversTrailBehindBefore` | R — displayed-pixel lag requires trailing inflation. |
| 502 | `sweptRectsCoversBothSamplesInAfterOrder` | R — union and owner ordering independently specified. |
| 526 | `sweptRectsNilBefore` | R — missing sample cannot manufacture a safe union. |
| 533 | `sweptRectsNilAfter` | R — same later-sample guard. |
| 540 | `sweptRectsCountMismatch` | R — newly appearing owner remains covered. |
| 558 | `sweptRectsDuplicateOwnerInBefore` | R — ambiguous duplicate pairing returns nil. |
| 573 | `sweptRectsDuplicateOwnerInAfter` | R — symmetric ambiguity guard. |
| 588 | `sweptRectsDisjointOwnerSet` | R — recycled owners cover both samples instead of losing disappeared content. |
| 603 | `sweptRectsStationaryOwnerUnchanged` | R — stationary union does not distort mask. |

### 5. `PostHogMaskSnapshotTest.swift`

- **68 `recordGoldens` — R:** Retain as explicitly gated authoring support, not independent regression evidence. Verify runs cannot rewrite goldens.
- **80 `verifyGoldens` — R with U rows below:** Independent committed-image oracle catches missing, shifted, or enlarged masks. Missing/orphaned goldens fail. Production painter is used.

Both declarations loop over these **24 explicit scenario rows**:

1. Mask a Text — R.
2. Mask an Image — R.
3. Mask a container — R.
4. TextField — R.
5. Image — R.
6. noMask child in masked container — U-privacy.
7. mask child in noMask container — U-privacy.
8. List, per-row leaf mask (top) — R.
9. List, per-row leaf mask (scrolled) — R; scroll-fixture note below.
10. List, TextField rows (scrolled) — R; same note.
11. List, whole-row mask (top) — R.
12. List, whole-row mask (scrolled) — R; same note.
13. SecureField — R.
14. Multiple text inputs — R.
15. Text, text masking OFF — R.
16. Image, image masking OFF — R.
17. noMask rescues text — R.
18. noMask rescues image — R.
19. Disabled explicit mask — R.
20. Sibling explicit masks — R.
21. Button + Toggle — R.
22. SecureField, text masking OFF — R.
23. SF Symbol under maskAllImages — R; distinguishes text-layer and raster-image paths.
24. TextField, placeholder only — R.

**U fixture hardening:** `Capture.composite` at line 445 silently skips scrolling if no scroll view exists. Require the scroll fixture and achieved offset before capturing scrolled cases. Existing golden differences may catch failure to scroll; no claim that this currently passes incorrectly. Golden pixel contents were not independently visually approved in this audit.

### 6. `PostHogMaskingCharacterizationTest.swift`

**U-body:** Full test-body verification remains unfinished. Production tagging traversal, ownership reconciliation, and test seams were inspected; no deletion justified. Intended contracts are traversal compatibility, ownership lifetime, coalescing, and live reporter geometry.

Explicit retained inventory:

- 35 `targetViewsFlatSandwich`
- 56 `targetViewsWrappedSandwich`
- 89 `targetViewsNotInHierarchy`
- 98 `targetViewsDisjointTrees`
- 112 `descendantsPreOrder`
- 131 `nearestCommonAncestorSiblings`
- 142 `nearestCommonAncestorAncestorDescendantQuirk`
- 160 `nearestCommonAncestorDisjoint`
- 165 `nearestCommonAncestorSelfIsAncestor`
- 179 `targetViewsTaggerInsideAnchor`
- 196 `contentLayerCollection`
- 253 `overlappingOwnersOnView`
- 270 `overlappingOwnersOnLayer`
- 285 `deadOwnerClaimSelfHeals`
- 299 `overlappingMasksThroughMachinery`
- 329 `emptyResolutionReleasesAllClaims`
- 352 `reconcileAndEmitEmptyLayerResolution`
- 372 `reconciliationReleasesDroppedTargets`
- 400 `layerScanBoundedToCaptureExtent`
- 430 `layerScanPrunesClippedSubtrees`
- 453 `coalescerDrainsOncePerTagger`
- 488 `liveRects`
- 512 `windowFiltering`
- 534 `weakSelfHealing`
- 545 `reporterLifecycle`
- 566 `captureCollectionIncludesReporters`
- 585 `zeroSizeReporterCompletesFirstLayout`
- 600 `preLayoutReporterMarksUnsettled`
- 621 `laidOutZeroSizeReporterDoesNotBlock`
- 636 `unsettledReporterInOtherWindowDoesNotBlock`
- 664 `hiddenPreLayoutReporterDoesNotMarkUnsettled`
- 680 `alphaZeroPreLayoutReporterDoesNotMarkUnsettled`
- 696 `sameWindowReaddKeepsSettled`
- 717 `reattachmentRequiresFreshLayout`
- 740 `swiftUIHostedZeroSizeMaskSettles`
- 760 `captureCollectionSkipsUnsettledFrame`

The named ancestor “quirks” are explicitly preserved by production comments; implementation specificity alone is not deletion evidence.

### 7. `PostHogMulticastCallbackTest.swift`

**`PostHogMulticastCallbackTests`:**

- 8 `singleSubscriber` — U-body.
- 23 `multipleSubscribers` — U-body.
- 43 `subscriberCount` — U-body.
- 58 `tokenDeallocationRemovesSubscriber` — U-body.
- 81 `optionalValue` — U-body.

**`PostHogThrottledMulticastCallbackTests`:**

- 103 `reentrantSubscriberCountChanges` — U-body.
- 133 `subscriberCountDeliveryYields(finalCount:)` — U-body; rows **0, 2** inventoried.
- 189 `subscriberCountDeliveryDrainsMultipleBatches` — U-body.
- 224 `singleSubscriber` — F20; retain zero-throttle asynchronous delivery.
- 242 `multipleSubscribers` — F20; retain fanout, synchronize completion and reads.
- 265 `subscriberCount` — R; counts reflect live tokens, catches subscription loss.
- 280 `tokenDeallocationRemovesSubscriber` — F20; retain delivery-before-release and no delivery afterward.
- 305 `throttlePreventsRapidInvocations` — F20; retain `[1,3]` across controlled clock steps.
- 339 `differentThrottleIntervals` — F20; retain independent fast/slow windows.
- 380 `onSubscriberCountChanged` — R; synchronous count notifications must be `[1,2]`.
- 398 `voidType` — F20; retain void-payload asynchronous delivery.
- 414 `invokeWithoutSubscribers` — R; no-subscriber invocation is safely inert.
- 424 `lateSubscriberFiresImmediately` — F20; new subscriber must not inherit another token’s throttle window.
- 459 `resubscribeAfterEmpty` — F20; unsubscribed delivery stays cancelled and fresh subscription receives new input.

**`PostHogTrailingThrottleTests`:**

- 500 `latestPendingValue` — R; burst delivers latest pending value once, not a recurring timer.
- 517 `trailingStartsNextWindow` — R; trailing delivery establishes next interval and stays on main.
- 539 `optionalPendingValue` — R; pending nil is a value, not absence of pending work.
- 552 `defaultStillDrops` — R; opt-in trailing behavior does not change default subscribers.
- 567 `noUnnecessaryTrailingCapture` — R; quiet screens do not generate redundant captures.
- 581 `unsubscribeAndResubscribe` — R; pending old-token work is cancelled.
- 599 `cancelQueuedLeadingDelivery` — R; cancellation works before queued main delivery.
- 611 `pendingWorkDoesNotRetainOwner` — R; delayed work does not retain publisher/subscriber.
- 634 `busyMainThread` — R; overdue captures coalesce instead of flooding main.
- 655 `concurrentInvocations` — R; concurrent burst produces one trailing latest value.
- 670 `independentWindows` — R; subscribers own independent throttle windows.
- 689 `zeroInterval` — R; zero interval preserves every invocation.

### 8. `PostHogOptOutPersistenceTest.swift`

Production owner: SDK setup consent read and guarded runtime persistence (`PostHogSDK.swift:243–249,2563–2569,2612–2618`).

- 45 `persistedOptOutWins` — R; persisted true beats false config.
- 53 `persistedOptInWins` — R; persisted false beats true config.
- 61 `configDecidesWithoutPersistedState` — R; missing storage leaves config authoritative.
- 69 `runtimeChangesArePersisted` — R; runtime opt-out and opt-in write corresponding disk values.
- 83 `hostOptOutBeatsPersistedOptIn` — R; host-owned consent ignores stale stored false.
- 91 `hostOptInBeatsPersistedOptOut` — R; host-owned consent ignores stale stored true.
- 99 `runtimeOptOutIsNotPersisted` — R; memory changes without writing disk.
- 110 `runtimeOptInLeavesStoredValueAlone` — R; existing disk state remains untouched.
- 121 `runtimeOptInIsNotPersisted` — R; absent disk state remains absent.

These contrasting fixtures catch reversed precedence and accidental persistence without requiring consolidation.

### 9. `PostHogPropertiesSerializationTest.swift`

**R for the narrow crash-safety/delivery contract**, not proof of exact value encoding:

- 128 `captureWithPropertyType(_:)`
- 147 `screenWithPropertyType(_:)`
- 166 `identifyWithPropertyType(_:)`
- 185 `groupWithPropertyType(_:)`
- 204 `registerWithPropertyType(_:)`
- 223 `setPersonPropertiesWithPropertyType(_:)`
- 242 `setPersonPropertiesForFlagsWithPropertyType(_:)`
- 259 `setGroupPropertiesForFlagsWithPropertyType(_:)`

Every declaration runs all **27 rows**:

`primitives`, `collections`, `nullables`, `date`, `url`, `data`, `encodableStruct`, `nonEncodableObject`, `nestedWithDate`, `uuid`, `decimal`, `doubleInfinity`, `doubleNaN`, `floatInfinity`, `cgFloat`, `cgPoint`, `cgSize`, `cgRect`, `nsError`, `nsRange`, `locale`, `timeZone`, `calendar`, `indexPath`, `mixedTypes`, `nestedMixed`, `arrayWithMixedTypes`.

The first six declarations require outgoing event delivery/count; unsafe serialization or event loss can fail them. The last two intentionally protect the no-crash local flag-property path with reload disabled. Do not present them as wire-value assertions.

Additional declarations:

- 276 `handlesEmptyProperties` — R; empty dictionary does not prevent delivery.
- 289 `handlesNilProperties` — R; nil dictionary does not prevent delivery.
- 302 `handlesDeeplyNestedStructuresWithDate` — R; deeply nested unsupported values do not crash/drop capture.

**Residual:** Value-preservation assertions, especially valid siblings inside mixed payloads, remain a distinct coverage opportunity. No deletion proposed.

### 10. `PostHogPushNotificationSwizzlingTest.swift`

**U-body** for all declarations below. Intended contracts are delegate forwarding, prewarm buffering lifecycle, setup consent/configuration gates, completion invocation, and safe inheritance-aware swizzling.

- 100 `forwardsApplicationDelegateCallbacks`
- 129 `buffersResponseDeliveredBeforeSubscriber`
- 142 `dropsResponseWhenNotPrewarmed`
- 152 `prewarmIsIdempotent`
- 164 `discardEndsPrewarmWindow`
- 179 `prewarmWithLiveSubscriberIsIgnored`
- 193 `prewarmOvertakenByFirstSubscriberDoesNotOutliveIt`
- 216 `discardOvertakenByPrewarmReArmsInterception`
- 238 `prewarmAfterLastSubscriberDetachesBuffers`
- 253 `publicPrewarmApiReachesPublisher`
- 290 `setupDiscardsPrewarmWhenCaptureDisabled`
- 301 `setupDiscardsPrewarmWhileOptedOut`
- 310 `setupKeepsPrewarmWhenCaptureEnabled`
- 320 `callsObjectiveCDelegate`
- 337 `duplicateInstallationIsHarmless`
- 354 `missingImplementationCompletes`
- 370 `superclassFirstDoesNotWrapInheritedMethodTwice`
- 390 `inheritedImplementationDoesNotMutateBaseClass`

### 11. `PostHogPushNotificationTest.swift`

**U-body unless separately classified below.** No public API or push-policy reconciliation is authorized.

Unfinished declaration verification, retained explicitly:

- 186 `configFlagsDefaultToTrue`
- 195 `getIntegrationsGatesOpenedIntegration`
- 209 `getIntegrationsGatesSubscriptionIntegration`
- 225 `registersAndKeepsDeliveredRecord`
- 246 `latestWinsOverwritesRecord`
- 261 `sendSkipsAlreadyDeliveredToken`
- 275 `sendSendsNewTokenAfterDelivery`
- 287 `sendResendsDeliveredTokenForNewDistinctId`
- 303 `unregisterFiresOneDeleteNoRetry`
- 327 `unregisterCurrentForgetsRecord`
- 341 `unregisterGuardedWhenDisabled`
- 349 `unregisterSendsWhileOptedOut`
- 358 `resetMovesTokenToAnonymous`
- 389 `resetReuseAnonymousIdSkipsDelete`
- 408 `resetDuringMintServicesPendingResend`
- 444 `resetDuringInFlightPostSerializesDelete`
- 482 `resetMintsPerLegIdentityTokens`
- 524 `resetNoTokenNoRequests`
- 534 `reregisterAfterResetPersistsWhenCleared`
- 550 `reregisterAfterResetSkipsWhenSuperseded`
- 573 `recordForResetClearsUnderLockPreservesConcurrentSend`
- 601 `staleDistinctIdDuringMintSkipsSend`
- 630 `repeatIdenticalRegisterKeepsBackoffPause`
- 646 `registrationDuringUnregisterMintCancelsDelete`
- 679 `retryFiresDifferentAppIdUnregisterWhenRegistrationQueued`
- 706 `retryBackoffIsExponential`
- 716 `retriesAfter500ThenSucceeds`
- 734 `givesUpKeepsRecordThenRetriesOnRelaunch`
- 839 `nonRetryable400KeepsRecordNoInSessionRetry`
- 861 `identityTokenOnRegisterAndUnregister`
- 888 `noProviderOmitsIdentityToken`
- 903 `nilCompletionOmitsIdentityToken`
- 915 `neverCompletingProviderFallsBackTokenLess`
- 933 `lateMintTokenIsCachedForNextSend`
- 961 `onlyFirstProviderCompletionHonored`
- 977 `lateMintAfterOptOutNotCached`
- 1010 `retryReusesCachedIdentityToken`
- 1034 `authRetryWithFreshTokenSucceeds`
- 1054 `secondAuthFailureIsTerminal`
- 1079 `coalescedResendDoesNotBreakAuthRetryCap`
- 1114 `unauthorizedWithoutProviderIsTerminal`
- 1127 `unregisterAuthRetryWithFreshTokenSucceeds`
- 1148 `unregisterAuthRetryTerminalDropsIntent`
- 1167 `unregisterOfflinePersistsAndDrains`
- 1184 `retryDropsSameIdentityUnregisterWhenRegistrationQueued`
- 1206 `unregisterTerminalDropsIntent`
- 1217 `reRegisterCancelsPendingUnregister`
- 1241 `offlineDefersWithoutBurningAttempt`
- 1258 `disallowedKeepsRecordSendsNothing`
- 1271 `reRegistersOnDistinctIdChange`
- 1294 `noResendWhenDistinctIdUnchanged`
- 1311 `optedOutIdentityChangeDoesNotResend`
- 1337 `resendRunsOffCallerThread`
- 1536 `optedOutSetupUnregistersOnceAndParksRecord`
- 1572 `sdkResetReregistersPersistedSubscription`
- 1595 `openCaptureFlattensPosthogPayload`
- 1617 `openCaptureParsesPosthogJSONString`
- 1636 `openCaptureIgnoresInvalidPosthogString`
- 1655 `openCaptureBasePropsOnly`
- 1677 `openCaptureOmitsEmptyFields`
- 1697 `openCaptureOmitsEmptyTitle`
- 1716 `openCaptureIncludesCustomAction`
- 1734 `openCaptureAllNilArguments`
- 1747 `openCaptureNoEventWhenOptedOut`
- 1764 `openCaptureWorksWithoutSwizzling`
- 1825 `openDedupeSkipsManualRepeatOfAutomatic`
- 1838 `openDedupeSkipsAutomaticRepeatOfManual`
- 1851 `openDedupeCapturesResend`
- 1864 `openDedupeSkipsRepeatOfSameDelivery`
- 1876 `openDedupeSkipsResendAfterManualFirstCapture`
- 1888 `openDedupeKeysByInvocationAndAction`
- 1904 `openDedupeIgnoresPushWithoutPosthogEntry`
- 1918 `openDedupeIgnoresMalformedPosthogEntry`
- 1940 `openDedupeExpiresAfterTheWindow`
- 1959 `openDedupeCapturesRepeatAfterBackwardClock`

Verified decisions:

| Line | Declaration | Decision / contract and regression |
|---:|---|---|
| 781 | `honorsRetryAfterHeader` | F13. |
| 793 | `retries429ThenSucceeds` | R — failed/delivered state and two requests prove rate-limit recovery. |
| 809 | `retriesTransportErrorThenSucceeds` | R — scripted transport error then success proves recovery. |
| 1375 | `sdkHandleDeviceTokenWithExplicitAppId` | R — validates token/app/platform on a real request. |
| 1389 | `sdkRegistrationNoRequestWhenOptedOut` | R — valid registration input is suppressed under consent gate; bounded absence window. |
| 1400 | `sdkUnregisterFiresDelete` | R — registered token reaches DELETE path. |
| 1413 | `sdkOptOutFiresDelete` | R — consent revocation triggers server-side cleanup. |
| 1426 | `sdkAppOwnedTokenSurvivesOptOutRoundTrip` | R — observes DELETE then later POST without app re-registration. |
| 1453 | `sdkUnregisterNoRequestWhenOptedOut` | F14. |
| 1465 | `sdkFlushRetriesPersistedSubscription` | R — persisted token becomes delivered after flush. |
| 1484 | `optedOutFlushUnregistersPersistedSubscription` | R — DELETE uses delivered identity and parks token instead of POSTing. |
| 1509 | `setupRetriesPersistedSubscriptionFromPreviousLaunch` | R with teardown note — seeded previous-launch token reaches request; add deferred close. |
| 2003 | `openDedupeCapturesOnceWhenReportsRace` | F20. |
| 2039 | `openDedupeEvictsOldestAtCap` | R — 21 inserts plus old/new repeats distinguish eviction from permanent suppression. |
| 2055 | `openDedupeRecordsNothingWhileOptedOut` | R — dropped opted-out report cannot poison later deduplication. |
| 2072 | `optInReRequestsPushToken` | R — eligible opt-in calls token refresh once. |
| 2089 | `optInSkipsReRequestWhenAutoCaptureDisabled` | R — manual mode does not invoke automatic token lifecycle. |
| 2105 | `optInSkipsReRequestWhenSwizzlingDisabled` | R — no refresh when no observer is installed. |
| 2126 | `optOutUnregistersDevice` | R — POST followed by consent-gated DELETE and parked record. |
| 2146 | `optOutUnregistersDeliveredIdentity` | R — DELETE targets old delivered identity, not newly current user. |
| 2168 | `optInResubscribesParkedToken` | R — exactly two POSTs/one DELETE across round-trip. |
| 2189 | `optedOutFlushDoesNotRedeleteParkedRecord` | R — repeated flush does not repeat already-completed cleanup. |
| 2209 | `offlineOptedOutFlushKeepsItsOwnDelete` | R — offline consent cleanup intent survives and drains online. |
| 2240 | `undeliveredRecordKeepsQueuedUnregister` | R — unrelated pending identity is not overwritten. |
| 2262 | `offlineResetThenOptOutDeletesLoggedOutIdentity` | R — offline identity transition retains old-user cleanup. |
| 2296 | `optOutDuringUnregisterStrandsDelete` | R — parked mint injects opt-out during DELETE preparation; cleanup must still send. |
| 2340 | `skipsUnconfiguredAppId` | U — empty request assertion follows record persistence, not proven send-work completion. Preserve fixture; establish completion boundary. |
| 2354 | `sendsWhenNoListPublished` | R — backward-compatible nil-list path sends and marks delivered. |
| 2367 | `sendsWhenAppIdConfigured` | R — matching app-id sends and marks delivered. |
| 2377 | `reregistersWhenAppIdBecomesRegisterable` | F15. |
| 2396 | `onPushAppIdsChangedRunsCompletionOnEarlyReturn` | R — explicit completion counter catches missing early-return callback. |
| 2410 | `skipsSendWhenEligibilityRevokedDuringMint` | U — eligibility is restored before a verified post-mint rejection boundary; retain pending deterministic synchronization. |
| 2438 | `doesNotReregisterForUnrelatedAppId` | R — delivered precondition plus unrelated app-id change must not add a POST; bounded absence window. |

### 12. `PostHogQueueTest.swift`

Quick declarations:

- 59 `"add item to queue"` — U-body.
- 77 `"add item to queue and flush respecting flushAt"` — U-body.
- 101 `"add item to queue and rotate queue"` — U-body.
- 127 `"halves both batch cap and flush threshold and retains batch on HTTP 413 when cap > 1"` — R; observes changed cap/threshold, catches wrong adaptive sizing.
- 146 `"halves cap based on actual batch size when queue depth was below cap"` — R; catches halving configured cap rather than actual batch.
- 167 `"clamps flushAt to cap on halve so we don't buffer more than a batch"` — R; catches threshold exceeding reduced cap.
- 190 `"drops batch on HTTP 413 when cap is already 1"` — R; singleton poison item cannot block delivery.
- 207 `"retains batch on retriable 5xx and does not change cap"` — F9.
- 224 `"retains batch on HTTP 429 and does not change cap"` — F9.
- 241 `"retains batch on HTTP 408 (request timeout is retriable) and does not change cap"` — F9.
- 258 `"retains retryable HTTP failures past maxRetries and drains after recovery"` — R; multiple acknowledged retry transitions, recovery, and fresh-event retry reset.
- 303 `"retains transport failures past maxRetries and drains after recovery"` — R; durable recovery despite configured maxRetries zero.
- 335 `"late success removes exact in-flight identities after full-capacity replacement"` — R; byte-identical replacement events retain different durable identities.
- 386 `"halves cap repeatedly across multiple 413s and drops once cap reaches 1"` — R; observes 4→2→1→single-item removal.
- 418 `"pops batch on 5xx codes outside the narrow retriable set"` — R; 501 does not poison queue.
- 438 `"retains batch on a network error"` — F9.
- 456 `"pops batch on non-retriable 4xx so a poison record cannot block the queue"` — R; terminal 401 removes batch.
- 473 `"pops batch on 2xx and leaves cap unchanged (no ramp-up)"` — R; successful removal without cap change.

Swift Testing declarations:

- 524 `receivedHTTPDisposition(statusCode:snapshot:)` — **R**, Cartesian **[-1, 200, 400, 408, 429, 503] × [false, true]**. Received HTTP disposition outranks accompanying transport error; durable identities checked in memory and after reload.
- 551 `shrinkingAfterRetryableFailures(snapshot:)` — **R**, **false/true** analytics/replay. Three 503 retries, two halvings, singleton 413 removal, then successful drain; catches deletion of later records or stale retry state.

### 13. `PostHogRageClickIntegrationTest.swift`

- 56 `emitsRageClickAfterRapidTaps` — R; three clustered taps yield one rageclick, not autocapture.
- 75 `noRageClickWhenTooFarApart` — F19.
- 92 `emitsRageClickWhenElementInteractionsDisabled` — R; rage detection does not depend on element-autocapture enablement.
- 111 `doesNotInstallWhenDisabled` — R; disabled feature has no integration.
- 119 `noRageClickWithoutScreenNameAndElementId` — F19.
- 136 `rageClickWithoutScreenNameWithElementId` — R; element id provides valid context when screen absent.
- 153 `rageClickWithScreenNameAndNoElementsChain` — R; screen context permits missing element chain.
- 170 `rageClickEventHasExpectedProperties` — R; requires actual event and touch/screen fields.
- 195 `keyboardWindowIsIneligible` — R; keyboard typing cannot create rage clicks.
- 223 `intentionalControlIsIneligible(_:)` — R; all **textField, textView, searchBar, stepper, slider, datePicker, pickerView, segmentedControl, pageControl** rows protect intentional repeated interaction.
- 230 `subviewOfIneligibleControlIsIneligible` — U-body.
- 241 `viewMarkedByAccessibilityIdentifierIsIneligible` — U-body.
- 251 `viewMarkedByAccessibilityLabelIsIneligible` — U-body.
- 261 `viewMarkedByFlagIsIneligible` — U-body.
- 272 `plainViewIsEligible` — U-body.
- 302 `fallbackHitTestNeverForwardsLiveEvent` — U-body.
- 324 `noHitTestWhenTouchHasView` — U-body.

### 14. `PostHogReachabilityTest.swift`

- 14 `multicastNoStomp` — R; two subscribers each see reachable/unreachable transitions; catches single-slot callback replacement.
- 48 `tokenDeallocUnsubscribesOnReachable` — R; prior delivery establishes positive control, release suppresses later delivery.
- 68 `tokenDeallocUnsubscribesOnUnreachable` — R; same lifetime contract for unreachable channel.

These are publisher-surface tests, not tests of real network transitions.

### 15. `PostHogReactNativeMaskingTest.swift`

- 64 `fabricParagraphViewMasked` — R; text heuristic recognizes Fabric paragraph class.
- 75 `fabricImageComponentViewMasked` — R; image heuristic recognizes Fabric image class.
- 86 `svgImageMasked` — R; SVG image descendants mask SVG extent.
- 98 `svgTextMasked` — R; nested SVG text recognized.
- 112 `noMaskIdentifierTokenUnmasksParagraph` — R; compound identifier token is honored.
- 126 `noMaskAncestorSkipsSensitiveSubtree` — R; inherited accessibility no-mask bypasses heuristic subtree.
- 140 `noMaskLabelTokenUnmasksParagraph` — R; explicit label carrier works.
- 152 `noMaskTokenIsCaseInsensitive` — R; uppercase marker remains effective.
- 164 `noMaskAncestorOutranksNoCaptureDescendant` — R for accessibility-carrier behavior; distinct from explicit SwiftUI reporter policy.
- 179 `nothingMaskedWithFlagsOff` — R; disabling both heuristics prevents automatic overmasking.
- 196 `textViewsNotMaskedByImageSetting` — R; image setting does not accidentally enable text masking.
- 213 `imageViewsNotMaskedByTextSetting` — R; inverse independence.
- 243 `explicitLabelIsRead` — R; explicit carrier is recognized.
- 251 `textDerivedLabelIsNotRead` — R for observed UILabel context; does not independently prove all accessibility-runtime derivation paths.
- 262 `overriddenLabelIsNotRead` — R; malicious/content-derived override returning marker cannot unmask.
- 270 `noCaptureUsesSameCarriers` — R; text content is not mistaken for an explicit no-capture label.

### 16. `PostHogRemoteConfigTest.swift`

Verified/focused decisions:

- 242 `shouldNotClearFlagsIfRemoteConfigCallFails` — U; cached flag retention is meaningful, but latch timeout is not asserted as response completion.
- 271 `shouldNotClearFlagsIfHasFeatureFlagsKeyIsMissing` — U; two-second settle does not establish clear-or-keep completion.
- 308 `guardPreventsConcurrentRequestsAndQueuesPending` — R; both callback booleans and two requests detect dropped pending work.
- 338 `surveyRefreshCoalescesWithMatchingRequest` — F16.
- 901 `enablesAutocaptureExceptionsFromRemoteConfigDict` — R; false→true outcome and persisted config prove useful application.
- 927 `errorTrackingReArmsFromCachedConfigAfterReset` — R; enabled→cleared→rearmed state distinguishes persistence ownership.
- 954 `disablesAutocaptureExceptionsFromRemoteConfigDict` — F16.
- 979 `disablesAutocaptureExceptionsWhenErrorTrackingIsBooleanFalse` — R; enabled cached precondition, then disabled result.
- 1010 `disablesAutocaptureExceptionsWhenErrorTrackingKeyIsMissing` — F16.
- 1035 `errorTrackingReArmsOnQuotaLimitedFlagsReload` — R; rearm must survive quota-limited flags result.
- 1142 `gateClearsWhenFieldDisappears` — R; true→false across awaited responses.
- 1160 `clearDropsGate` — **F/P2**: declaration promises persisted clearing but asserts only live getter. Add direct storage assertion or a fresh remote-config instance after clear; mutation: clear memory only.

**U-body**, retained intended cache, request-coalescing, replay eligibility, callback, and gate contracts:

- 74 `loadsCachedRemoteConfig`
- 86 `remoteConfigSurvivesReset`
- 99 `clearKeepsRemoteConfigFetched`
- 115 `remoteConfigLoadsFeatureFlagsIfNotPreviouslyLoaded`
- 138 `remoteConfigDoesNotFetchFeatureFlagsIfPreloadFeatureFlagsIsDisabled`
- 164 `remoteConfigFetchesFeatureFlagsOnInitEvenIfFlagsAreCached`
- 198 `remoteConfigClearsCachedFlagsWhenHasFeatureFlagsIsFalse`
- 356 `pendingRequestUsesCorrectIdentity`
- 385 `pendingRequestReplacesEarlierPending`
- 418 `callbacksFireForBothRequests`
- 447 `noPendingQueueWhenNoConcurrentLoad`
- 468 `reloadRemoteConfigConcurrentCallsDoNotCrash`
- 488 `returnsIsSessionReplayFlagActiveTrueIfThereIsAValue`
- 501 `returnsIsSessionReplayFlagActiveFalseIfThereIsNoValue`
- 508 `sessionReplayConfigSurvivesReset`
- 522 `returnIsSessionReplayFlagActiveFalseIfFeatureFlagDisabled`
- 540 `returnIsSessionReplayFlagActiveTrueIfFeatureFlagActive`
- 556 `returnsIsSessionReplayFlagActiveTrueIfBoolLinkedFlagIsEnabled`
- 574 `returnsIsSessionReplayFlagActiveTrueIfBoolLinkedFlagIsDisabled`
- 593 `returnsIsSessionReplayFlagActiveTrueIfMultiVariantLinkedFlagIsAMatch`
- 614 `returnsIsSessionReplayFlagActiveFalseIfMultiVariantLinkedFlagIsNotAMatch`
- 635 `returnsIsSessionReplayFlagActiveFalseIfBoolLinkedFlagIsMissing`
- 656 `callsFeatureFlagCalledCallbackWhenBoolLinkedFlagIsChecked`
- 681 `callsFeatureFlagCalledCallbackWhenMultiVariantLinkedFlagIsChecked`
- 709 `doesNotCallFeatureFlagCalledCallbackWhenSendFeatureFlagEventDisabled`
- 731 `doesNotCallFeatureFlagCalledCallbackWhenNoLinkedFlag`
- 750 `sessionReplayReArmsFromCachedConfigAfterReset`
- 782 `sessionReplayStaysOffAfterResetWhenLinkedFlagMissing`
- 811 `sessionReplayReArmsOnQuotaLimitedFlagsReload`
- 837 `flagsReloadWithoutCachedRecordingConfigLeavesReplayInactive`
- 864 `returnsAutocaptureExceptionsDisabledByDefault`
- 875 `returnsAutocaptureExceptionsEnabledFromCache`
- 888 `returnsAutocaptureExceptionsDisabledFromCache`
- 1058 `flagsReloadWithoutCachedErrorTrackingDoesNotReArm`
- 1082 `capturePerformanceSurvivesReset`
- 1109 `gateOffWhenFieldAbsent`
- 1124 `gatePersistsAcrossRestart`

### 17. `PostHogReplayBufferQueueTest.swift`

- 32 `bufferDurationEmpty` — R; empty buffer has no duration.
- 38 `bufferDurationSingleItem` — R; one item has zero span.
- 45 `bufferDurationIncreases` — R; later UUID timestamp extends duration.
- 61 `migrateMovesAllItems` — R; counts transfer completely.
- 85 `migratePreservesData` — R; each distinct source payload survives.
- 111 `migrateIsAtomic` — R for its displayed **clear-buffer-with-existing-target** contract, not proof of transaction atomicity.
- 138 `migrateResultsInSortedQueue` — R; explicit payload ordering follows chronology.
- 176 `migrateEmptyBuffer` — R; existing target is unchanged by empty migration.
- 194 `migrateHandlesDuplicates` — F11.
- 225 `concurrentWritesDuringMigration` — F12.
- 265 `writesPreservedDuringMigration` — F12.
- 297 `concurrentAddsFromMultipleThreads` — R; four tasks × twenty writes must retain eighty entries.
- 322 `concurrentAddsAndMigrationFromDifferentThreads` — R; task-group stress catches loss/corruption across buffer migration and two target writers; not deterministic overlap proof.
- 373 `migrationWhileAddingToBuffer` — R; fifteen entries conserved across both destinations, regardless of legal migration cutoff.

### 18. `PostHogReplayCaptureTouchesTest.swift`

- 97 `defaultEnabled` — R; actual began/ended records, count two, types **7/9**, coordinates **123/456**, queue barrier.
- 111 `initiallyDisabled` — R; does not even read touch coordinates, plus no touch records.
- 122 `screenshotsRemainActive` — R; requires real nonempty screenshot base64 and active replay while touches disabled.

These protect separate privacy and availability risks; no consolidation proposed.

### 19. `PostHogReplayQueueTest.swift`

- 66 `migratesLegacyReplayQueueFolder` — U-body.
- 91 `addRoutesToBufferWhenBuffering` — R; buffer-only routing.
- 104 `addRoutesToInnerQueueWhenNotBuffering` — R; ordinary queue routing.
- 117 `delegateNotifiedAfterBuffering` — R; callback per buffered item with correct queue identity.
- 135 `delegateNotNotifiedWhenNotBuffering` — R; no spurious buffer callback.
- 148 `flushSuppressedWhenBuffering` — F10.
- 163 `flushWorksWhenNotBuffering` — F18.
- 191 `migrateBufferToQueue` — R; awaited complete depth transfer.
- 215 `migrateEmptyBuffer` — R; safe empty no-op.
- 231 `clearBufferRemovesAllEvents` — R; awaited removal.
- 251 `clearBufferDoesNotAffectInnerQueue` — R; isolated deletion preserves ready events.
- 278 `bufferDurationEmptyBuffer` — R; empty duration nil.
- 284 `bufferDurationReturnsValue` — R; nonempty temporal span exposed by wrapper.
- 300 `clearRemovesAllEvents` — R; both stores emptied.
- 324 `switchingBufferingState` — R; subsequent events route directly without disturbing old buffer.
- 345 `delegateCanTriggerMigration` — R; callback-initiated migration does not deadlock and transfers all three.
- 384 `eventsDuringMigrationGoToInnerQueue` — R for paused-delegate routing; **P2 note:** replace final 150 ms sleep with an asserted completion condition. It pauses before migration begins, not inside file moves.

### 20. `PostHogReplayScreenshotDedupTest.swift`

40 `screenshotDedupDecision(_:)` — **R**, all five independent rows:

1. Equal image hashes, no pending metadata → skip.
2. Different hashes → send.
3. Equal hashes with pending snapshot data → send.
4. Nil image hash/wireframe mode → send.
5. No previous hash → send.

Credible regressions: duplicate traffic, lost metadata, wireframe suppression, or missing first frame.

### 21. `PostHogSDKPersonProfilesTest.swift`

All **R**. Outgoing event counts and `$process_person_profile` exercise the capture pipeline, while differing input causes protect distinct policy paths:

- 51 `"capture sets process person to false if identified only and not identified"`
- 68 `"capture sets process person to true if identified only and with user props"`
- 86 `"capture sets process person to true if identified only and with user set once props"`
- 104 `"capture sets process person to true if identified only and with group props"`
- 122 `"capture sets process person to true if identified only and identified"`
- 141 `"capture sets process person to true if identified only and with alias"`
- 160 `"capture sets process person to true if identified only and with groups"`
- 179 `"capture sets process person to true if always"`
- 196 `"capture sets process person to false if never and identify called"`
- 216 `"capture sets process person to false if never and alias called"`
- 236 `"capture sets process person to false if never and group called"`

Regression controls: remove each transition to processing-enabled, or allow `.never` identity/group calls to emit/process a person.

### 22. `PostHogSDKTest.swift`

Focused decisions:

- 383 `"captures $recording_status and $sdk_debug_* debug properties on custom, screen, and exception events"` — R; explicitly requires three events before looping, protecting enrichment on all three event kinds.
- 407 `"excludes $recording_status and $sdk_debug_* properties from $snapshot events"` — F1.
- 436 `"reports screenshot capture mode for the flutter host"` — R; host override must change reported capture mode.
- 540 `"setups optOut"` — R; runtime opt-out then opt-in changes getter both ways.
- 555 `"sets opt out via config"` — F5.
- 566 `"removes all integrations on opt-out"` — R; positive installed precondition and post-opt-out absence.
- 582 `"does not capture event if opt out"` — R; valid event suppressed with explicitly non-failing bounded negative waiter.
- 1017 `"sanitize properties"` — F6.
- 1152 `"reset deletes posthog files but not other folders"` — F17.
- 1165 `"client sanitize properties"` — R; actual event carries no sanitizer-removed `"empty"` property.
- 1238 `"captures $feature_flag_called when getFeatureFlag is called"` — R; emitted event and absent legacy experiment detail.
- 1252 `"does not capture $feature_flag_called when getFeatureFlag is called twice"` — R; synchronous second lookup precedes sentinel, expected two-event sequence.
- 1268 `"does not capture $feature_flag_called again when getFeatureFlag called twice after reloading flags"` — F4.
- 1287 `"captures $feature_flag_called again when getFeatureFlag returns different value after reloading flags"` — R; changed response and sentinel inside reload callback require second flag event.

Generated `beforeSend hook` declarations, each expanded over **capture/test_event; screen/$screen; autocapture/$autocapture; identify/$identify; group/$groupidentify; alias/$create_alias; get feature flag/$feature_flag_called**:

- 1338 `returns nil / <row> / "skips the event"` — **F3**, all seven.
- 1349 `returns nil / <row> / "preserves other events"` — **F3**, all seven.
- 1379 `event is updated / <row> / "updates the event"` — **R**, all seven; two-event batch must contain renamed target.
- 1390 `event is updated / <row> / "preserves all events"` — **R**, all seven; total count and unrelated event preservation.
- 1411 `default hook / <row> / "keeps the events intact"` — **U-body**, all seven; final assertions not fully reverified.

**U-body** remaining declarations:

- 130 `"no-ops setup when project token is empty after trimming"`
- 141 `"no-ops setup when legacy api key is empty after trimming"`
- 170 `"merges an anonymous local user into an identified bootstrap"`
- 184 `"preserves a different already-identified local user against an identified bootstrap"`
- 196 `"upgrades a matching anonymous id to identified via an identified bootstrap"`
- 208 `"reconciles an identified bootstrap while opted out"`
- 221 `"early lifecycle events carry the reconciled bootstrap identity"`
- 242 `"applies an identified bootstrap on a fresh install even when personProfiles is never"`
- 259 `"drops a differing identified bootstrap for a returning anonymous user when personProfiles is never"`
- 273 `"drops a differing identified bootstrap for a returning anonymous user when personProfiles is never and opted out"`
- 287 `"identifies an anonymous user via identify() when the id already matches the persisted distinct id"`
- 307 `"does not emit a second $set on a repeated matching-id identify"`
- 325 `"forwards userProperties and userPropertiesSetOnce on a matching-id identify"`
- 351 `"captures the capture event"`
- 452 `"SDK-computed debug keys win over a same-named registered super property"`
- 469 `"reports disabled recording status with no replay keys on non-iOS platforms"`
- 488 `"invokes reloadFeatureFlags callback when not enabled"`
- 500 `"captures a screen event"`
- 519 `"captures a group event"`
- 597 `"calls reloadFeatureFlags"`
- 615 `"loads feature flags automatically"`
- 625 `"send feature flag event for isFeatureEnabled when enabled"`
- 649 `"send feature flag event with variant response for isFeatureEnabled when enabled"`
- 673 `"send feature flag event without has_experiment when server omits it"`
- 692 `"sends minimal feature flag event when gated and flag has no experiment"`
- 736 `"keeps $groups on minimal feature flag events"`
- 780 `"sends full feature flag event when gated but flag has an experiment"`
- 803 `"sends full feature flag event when gated but has_experiment is unknown"`
- 823 `"sends full feature flag event when the server does not gate minimal events"`
- 843 `"send feature flag event for getFeatureFlag when enabled"`
- 862 `"force send feature flag event for getFeatureFlag when config disabled"`
- 881 `"don't send feature flag event for getFeatureFlag when config enabled"`
- 895 `"reloadFeatureFlags adds groups if any"`
- 923 `"merge groups when group is called"`
- 945 `"register and unregister properties"`
- 968 `"add active feature flags as part of the event"`
- 992 `"caller-supplied feature flag properties override cached values"`
- 1051 `"sets sessionId on app start"`
- 1067 `"uses the same sessionId for all events in a session"`
- 1095 `"clears sessionId for background events after 30 mins in background"`
- 1118 `"reset sessionId after reset"`
- 1181 `"reset reloads flags as anon user"`
- 1192 `"captures an event with a custom timestamp as the equivalent UTC instant"`
- 1426 `"skip updated to $session event"`
- 1447 `"runs boxed Objective-C callbacks through the exception boundary"`
- 1464 `"contains Objective-C exceptions from boxed callbacks"`
- 1494 `"properly handles empty beforeSend array"`
- 1515 `"supports trailing closure syntax for single block"`
- 1531 `"supports multiple beforeSend blocks"`
- 1563 `"sets default person properties on SDK setup when enabled"`
- 1590 `"does not set default person properties when disabled"`
- 1611 `"isAutocaptureActive() should be false if disabled by config"`
- 1619 `"isAutocaptureActive() should be false if SDK is not enabled"`

### 23. `PostHogSamplingTest.swift`

- 10 `simpleHashConsistent` — R; same-input stability is a legitimate invariant, though not a fixed cross-process vector.
- 17 `simpleHashPositive` — R; five inputs including generated UUID must stay nonnegative.
- 31 `simpleHashDistinct` — R; distinguishes the two chosen session strings, catches constant hash.
- 38 `simpleHashEmpty` — R; explicit empty-input result zero.
- 46 `sampleOnPropertyFullRate` — R; **session-0…99**, all retained at 1.
- 54 `sampleOnPropertyZeroRate` — R; same 100 inputs, none retained at 0.
- 62 `sampleOnPropertyDeterministic` — R; repeated same-property decision stable.
- 71 `sampleOnPropertyClampsAboveOne` — R; same 100 inputs at 1.5 retained.
- 79 `sampleOnPropertyClampsBelowZero` — R; same 100 inputs at −0.5 excluded.
- 87 `sampleOnPropertyApproximateRate` — R; **1,000 fixed input strings**, ratio strictly 0.3–0.7 catches constant/broken distribution.
- 138 `noSampleRateConfigured` — R; absent configuration yields nil.
- 144 `preloadsSampleRateFromCacheAsString` — R; `"0.75"` parsed.
- 156 `preloadsSampleRateFromCacheAsNumber` — R; `0.5` accepted.
- 168 `preloadsSampleRateOneFromCache` — R; `"1"` accepted.
- 180 `preloadsSampleRateZeroFromCache` — R; `"0"` accepted.
- 192 `ignoresInvalidSampleRateAboveOneFromCache` — R; `"1.5"` rejected.
- 204 `ignoresNegativeSampleRateFromCache` — R; `"-0.5"` rejected.
- 216 `ignoresNonNumericSampleRateFromCache` — R; `"invalid"` rejected.
- 228 `parsesSampleRateFromRemoteConfig` — R; observed nondefault 0.5 proves application.
- 251 `remoteConfigWithoutSampleRate` — F16.
- 292 `remoteSampleRateIsAppliedAfterConfigLoads` — R; remote zero and both internal/public inactive outcomes required.
- 330 `sampleRateDefaultsToNil` — R; public config default.
- 336 `sampleRateAcceptsValidValue` — R; NSNumber 0.5 preserved.
- 343 `sampleRateAcceptsZero` — R; lower boundary accepted.
- 350 `sampleRateAcceptsOne` — R; upper boundary accepted.
- 357 `sampleRateRejectsAboveOne` — R; invalid upper value rejected.
- 364 `sampleRateRejectsNegative` — R; invalid lower value rejected.

### 24. `PostHogScreenNameTest.swift`

- 43 `"event captured before screen has no screen_name"` — R; requires real event before negative property assertion.
- 55 `"event captured after screen carries screen_name"` — R; cached name propagated.
- 68 `"caller-supplied screen_name overrides cached value"` — R for ordinary event property override.
- 81 `"screen() with screen_name in properties carries the override on the $screen event"` — U-screen.
- 93 `"reset clears screen_name from subsequent events"` — R; stale screen does not cross reset.
- 106 `"exception event carries screen_name"` — R; crash-context enrichment wired.
- 119 `"snapshot event does not carry screen_name"` — R; actual intercepted snapshot required before absence check.

### 25. `PostHogScreenViewIntegrationTest.swift`

- 50 `capturesScreenEvent` — R; publisher→integration→outgoing event with name.
- 68 `respectsConfigurationAndDoesNotCaptureScreenEvent` — R; disabled auto-capture plus positive sentinel.
- 86 `integrationOwnsAutoCaptureLifecycle` — R; install and close own publisher registration.
- 101 `manualScreenInvokesSubscribers` — R; manual API broadcasts synchronously without auto-capture.
- 126 `sanitizePassesUIKitNames` — R; **MyHomeViewController, SettingsVC** unchanged.
- 132 `sanitizeStripsHostingController` — R; extracts `HomeView`.
- 137 `sanitizePeelsOneModifier` — R; extracts `DetailView`.
- 143 `sanitizeRecursesNestedModifiers` — R; nested wrappers reduce to `HomeView`.
- 152 `sanitizeReturnsNilForAnyViewFromStripping` — R; both modified/direct hosted `AnyView` discarded.
- 160 `sanitizeKeepsLiteralAnyView` — R; explicitly supplied literal preserved.
- 167 `sanitizeReturnsNilForEmpty` — R for **empty string only**; display name’s whitespace claim is not exercised.
- 172 `screenWithDegenerateInputPreservesLastUsefulName` — R; discarded wrapper noise cannot erase useful cache.
- 189 `screenCachePopulatedFromManualCall` — R; manual names update cache even without integration.

### 26. `PostHogSessionManagerTest.swift`

**U-body**: production session management and intended lifecycle contracts were inspected, but complete test-body/loop verification is not attested.

- 29 `sessionClearedBackgrounded`
- 59 `sessionClearedWhenMovingBetweenBackgroundAndForeground`
- 91 `sessionRotatedWhenInactive`
- 121 `sessionRotatedWhenPastMaxSessionLength`
- 206 `sessionClearedAfterBackgroundInactivity`
- 242 `sessionRotatedAfterInactivity`
- 283 `debugSessionKeysDescribeRotatedSession`
- 319 `debugSessionDurationUsesEventTimestamp`
- 360 `sessionRotatedAfterMaxSessionLength`
- 446 `applicationLifecyclePublisherHandlesTokenDeallocationCorrectly`
- 489 `sessionNotClearedBackgrounded`
- 517 `sessionNotRotatedWhenInactive`
- 545 `sessionNotRotatedWhenPastMaxSessionLength`
- 580 `sessionNotRotatedWhenStartSessionCalled`
- 600 `sessionNotRotatedWhenEndSessionCalled`
- 620 `sessionNotRotatedWhenResetSessionCalled`
- 650 `seedsForegroundOnLateSetup`
- 663 `seedsBackgroundOnSetup`

Retain both session-state and outgoing-event layers: manager correctness does not alone prove event enrichment, nor does native rotation cover React Native-owned sessions.

### 27. `PostHogSessionReplayEventTriggersTest.swift`

- 61 `isActiveWithoutTriggers` — R; absent triggers permit recording.
- 71 `isActiveWhileWaitingForTrigger` — R; configured trigger holds recording.
- 81 `isActiveAfterTriggerFired` — R; capture path activates recording.
- 97 `nonMatchingEventDoesNotActivate` — R; `page_view`/`button_clicked` cannot satisfy purchase gate.
- 111 `anyMatchingTriggerActivates` — R; **purchase_completed/signup_finished/checkout_started** list, middle entry activates.
- 126 `newSessionRequiresNewTrigger` — R; activation cannot leak across session ids.
- 142 `triggerPersistsInSameSession` — R; unrelated events do not clear activation.
- 160 `manualStartRespectsTriggers` — R; manual start does not bypass pending trigger.
- 181 `triggerDoesNotRestartWhenManuallyStopped` — R; stop observed before later matching event.
- 205 `emptyTriggersNoWaiting` — F8.
- 217 `reactNativeOptsOutOfTriggerGating` — R; wrapper-owned gate is not applied twice.
- 236 `triggerStatusReflectsCurrentState` — R; initial linked/event pending conditions, then event condition resolves. It does **not** exercise subsequent linked-flag activation.

### 28. `PostHogSessionReplayPluginTest.swift`

Console configuration:

- 24 `consoleLogsPluginDisabledWhenConfigNil` — R.
- 29 `consoleLogsPluginDisabledWhenSessionRecordingMissing` — R.
- 35 `consoleLogsPluginEnabledWhenTrue` — R.
- 43 `consoleLogsPluginDisabledWhenKeyMissing` — R.
- 51 `consoleLogsPluginDisabledWhenFalse` — R.

Together these protect default-off plus explicit remote opt-in, catching accidental default-on or ignored configuration.

Network configuration:

- 61 `networkPluginDisabledWhenConfigNil` — R.
- 66 `networkPluginDisabledWhenCapturePerformanceMissing` — R.
- 72 `networkPluginEnabledWhenCapturePerformanceIsTrue` — R.
- 78 `networkPluginEnabledWhenCapturePerformanceIsObject` — R.
- 89 `networkPluginDisabledWhenNetworkTimingFalse` — R.
- 100 `networkPluginDisabledWhenEmptyObject` — R.
- 108 `networkPluginDisabledWhenNetworkTimingMissing` — R.
- 118 `networkPluginDisabledWhenNetworkTimingIsNull` — F21.
- 129 `networkPluginDisabledWhenNetworkTimingIsNSNull` — F21.
- 140 `networkPluginDisabledWhenCapturePerformanceIsFalse` — R.

212 `networkReplayCaptureIgnoresPostHogIngestionRequests(_:)` — **R**, nine rows:

1. Configured host `/s/?ip=1` → ignore.
2. Configured host `/batch` → ignore.
3. Reverse-proxy `/ingest/s/?ip=1` → ignore.
4. Reverse-proxy `/ingest/batch` → ignore.
5. Remotely configured `/newS/?ip=1` → ignore.
6. Legacy `/i/v0/e/?ip=1` → ignore.
7. Same-host `/flags?v=2` → retain.
8. `/ingest-extra/batch` outside proxy base → retain.
9. Third-party `/batch` → retain.

Protects ingestion self-observation loops without suppressing unrelated traffic.

Xcode-only exception-boundary declarations:

- 227 `taskResumeFallbackIgnoresAVFoundationTasksThatThrowOnCurrentRequest` — R; exception contained, no setter attempted.
- 245 `taskResumeFallbackIgnoresGenericGetterExceptionsWhenProbingCurrentRequest` — R; generic getter exception contained.
- 263 `taskResumeFallbackIgnoresTasksWhoseCurrentRequestIsNil` — R; nil request neither traps nor mutates.
- 282 `taskResumeFallbackStillRewritesStandardRequestBackedTasks` — R; positive rewriting control prevents blanket no-op passing negatives.
- 298 `taskResumeFallbackIgnoresSetterExceptionsWhenMutatingCurrentRequest` — R; setter exception contained and mutation absent.

Residual: full synthetic-task implementation verification was not repeated; these declarations are compiled out under `SWIFT_PACKAGE`.

### 29. `PostHogSessionReplayRemoteConfigBufferTest.swift`

Focused verified decisions:

- 436 `firstConfigFlagOffDoesNotStopCapturer` — R for internal capturer lifecycle; public eligibility is a different contract. Preserve pending clarification of historical specification comment.
- 567 `linkedFlagTriggerStatus(linkedFlag:flagActive:triggerStatus:recordingStatus:)` — R, three rows:
  - nil / true → `trigger_disabled`, `active`.
  - configured / true → `trigger_activated`, `active`.
  - configured / false → `trigger_pending`, `disabled`.
- 581 `crashContextTracksRecordingStatus` — R; requires active context, excludes point-in-time counters, then observes disabled after stop.
- 613 `crashContextAfterLazyInstall` — F2.
- 643 `spiGetterMatchesCapturedEventReplayKeys` — R; nondefault buffering fixture and exact map equality with captured event.
- 674 `spiGetterIsEmptyWithoutReplayIntegration` — R; absent integration requires empty SPI map.
- 688 `concurrentStopWhileCapturing` — U; body tail/postconditions not fully reverified; retain concurrency stress.

**U-body** remaining declarations:

- 98 `snapshotsBufferWhileAwaiting`
- 112 `firstConfigFlagOnMigrates`
- 131 `firstConfigFlagOffDropsBuffer`
- 154 `firstConfigFlagOnSampledOutDropsBuffer`
- 175 `firstConfigIntroducingEventTriggerDropsBuffer`
- 197 `minimumDurationDoesNotMigrateWhileAwaiting`
- 218 `firstConfigFlagOnUnderMinimumDurationKeepsBuffer`
- 239 `featureFlagsBeforeFirstConfigDoNotResolve`
- 258 `rotationWhileAwaitingRearmsAndFlagsResolve`
- 284 `offlineConfigFailureResolvesViaFeatureFlags`
- 306 `featureFlagsResolveDropsWhenSampledOut`
- 333 `linkedFlagDefersToFlagsAndDropsWhenOff`
- 361 `linkedFlagResolvesAtConfigWhenPreloadDisabled`
- 381 `booleanConfigDoesNotDeferWithPreload`
- 400 `subsequentConfigFlagOffStopsCapturer`
- 418 `subsequentConfigFlagOnResumesCapturer`
- 456 `noMinimumDurationConfiguredReportsActiveOnceResolved`
- 475 `throttleDelayMsDoesNotTrapOnNonFiniteValue`
- 487 `bufferingReportsHoldReasonThenActive`
- 513 `stopClearsHoldReason`
- 537 `uninstallReportsDisabled`

These retained declarations own distinct first-config, later-config, sampling, trigger, duration, recovery, and status contracts; no blanket consolidation justified.

### 30. `PostHogSessionReplayTest.swift`

- 31 `manualSessionReplayStart` — **F/P2:** preserve disabled-config→lazy-install contract; require deterministic active state rather than only integration existence, and defer close.
- 48 `sessionReplayToggle` — **F7:** independently observe stop before consent teardown.

---

## CI routing and shared-state evidence

| Route | What actually runs | Limitations |
|---|---|---|
| `make test` | macOS SPM tests, `--no-parallel`, `-DTESTING` (`Makefile:189–190`) | iOS blocks absent; Xcode-only exception tests absent. |
| `make testOniOSSimulator` | Shared PostHog Xcode scheme, up to three retries (`Makefile:99–106`) | Result-salvage concern F22; first available iPhone, not minimum supported OS. |
| `make testPresentationMasks` | App-hosted presentation suites, explicit compile flag/selectors, no parallel testing (`Makefile:122–135`) | Correctly requires both named suites to pass; real animations remain environment-sensitive. |
| `make maskSnapshots` | Verify-only suite, iOS **26.2**, Xcode **26.3**, explicit compile gate and selector (`Makefile:144–173`) | Correctly rejects missing runtime and zero-test output; no golden visual review or execution performed here. |

`.github/workflows/test.yml` routes non-Markdown PRs through macOS, iOS, presentation, and pinned masking-snapshot jobs. Branch-protection requirements were not independently checked.

Shared support considerations:

- Quick’s reset hook resets global clock and deletes application-support storage (`TestUtils/TestPostHog.swift:15–29`); it is not a universal Swift Testing hook.
- `.resetsGlobalState` restores selected globals but is not a cross-suite mutual-exclusion mechanism.
- `.serialized` serializes the annotated suite’s tests, not every unrelated suite touching global DI, SDK install flags, clocks, storage, or OHHTTPStubs.
- The macOS `--no-parallel` route and Xcode nonparallel settings reduce exposure; do not assume every local invocation uses them.
- `MockPostHogServer` locks push-request storage, but other request arrays remain bare mutable arrays. Runtime race validation was not performed.
- Positive asynchronous completion must be asserted; `AsyncLatch` and `waitUntil` timeouts do not themselves guarantee failure.
- Preserve unique-token fixtures, explicit queue barriers, positive controls, and deferred SDK closure when repairing tests.

## Recommended parent sequence

1. Repair deterministic false positives first: **F1–F16**, especially snapshot decoding, nil status, wrong trigger input, before-send ordering, and missing fixture preconditions.
2. Keep production/spec policy discrepancies **U**, separate from test repairs.
3. Add bounded completion/teardown improvements without deleting scenarios.
4. Run parent-owned baselines and repaired tests through the relevant existing `make` routes.
5. Run the proposed isolated mutations and verify failure for the intended assertion—not a timeout, unrelated guard, or harness crash.
6. Finish **U-body** verification before calling this an exhaustive audit.

No runtime failure, passing test count, mutation result, or repaired patch is attested by this artifact.