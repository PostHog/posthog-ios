# Core test audit

## Review

- **Correct:** Retain the layered coverage for wire formats, identity persistence, durable queues, lifecycle ownership, privacy, exception processing, and swizzle compatibility. Unit, SDK-integration, and golden tests protect different failure modes.
- **Fixed:** None. This was read-only.
- **Findings:** Concrete repair candidates and unresolved cases are recorded below. No deletions or consolidations are proposed.
- **Merge verdict:** **OK with notes for this audit artifact; not an attestation that the baseline suite passes.** Repair the CI false-green and shared-harness issues before relying on green results.

## Scope, baseline, and limitations

Evaluated baseline: `c99f607d81549d5034a9ccd093ccb07fea21f642`.

Scope:
- All 33 root Swift files from `ApplicationViewLayoutPublisherTest.swift` through `PostHogLogsQueueTest.swift`, including `ExampleSanitizer.swift`.
- All six `PostHogTests/TestUtils` files.
- All four `PostHogTestsObjC` files.
- Relevant production seams, package manifests, Xcode discovery, CI workflows, and test-result processing.

The working tree was clean at audit launch. Later inspection found parent-owned changes to `PostHogDeviceBucketingTests.swift` and four files outside this audit’s root-file boundary. Device-bucketing baseline findings below refer to the original version; the parent’s partial repairs are distinguished explicitly. `/tmp/posthog-ios-test-audit/checkpoint.patch` was supplied at handoff but was not reviewed.

No tests, builds, shell commands, mutations, commits, or publication were performed by this auditor. Parent-reported baseline failures are not independently reproduced results.

Read `SKILL.md`, `CAMPAIGN.md`, contributor instructions, scoped tests/support, and relevant production code. Canonical specifications were supplied by the supervisor as an upstream-main checkout under `/tmp/posthog-ios-test-audit/specs/openspec/specs`. Reviewed capabilities included HTTP client, logs, capture exception, exception steps, identify, bootstrap, application lifecycle, autocapture, feature-flag results/reloading, and persistent storage. Their exact upstream revision was not independently established.

Historical commits and issue discussions were not independently inspected. Existing issue references in test comments are useful context, not reproduced historical evidence.

### Decision notation

- **R — retain:** Meaningful contract and credible regression identified. This does **not** mean executed or proven mutation-sensitive.
- **F — repair:** Preserve the scenario and strengthen its setup, oracle, isolation, or routing.
- **U — unresolved:** Retain while obtaining missing execution evidence or resolving policy.
- Parameter rows inherit the declaration’s decision unless explicitly split below.
- Setup/helper methods are covered in the support ledger or their owning suite, not counted as independently discovered tests.

## Concrete findings and smallest repairs

### A1 — P1: iOS result processing can turn failures into success

**Evidence:** `scripts/check-ios-test-result.sh:25–35` extracts Swift Testing **display names**, then subtracts every passed name from failed names. It does not retain suite identity, parameter identity, or attempt order. `:37–41` additionally accepts a nonzero command status when no recognized failure is parsed and any `Executed … tests, with 0 failures` line exists.

The scoped API suites reuse host-test display names. A pass in one suite can therefore cancel a different suite’s persistent failure. A successful XCTest subtotal can also coexist with an unparsed Swift Testing failure or later runner failure.

**Smallest repair:** Fail closed on nonzero status until a structured result establishes successful retries for the same fully qualified test and case. Do not treat a zero-failure subtotal as an aggregate result.

**Controlled checks:** Feed the checker:
1. A failed test and an unrelated same-display-name passed test.
2. A nonzero run containing a successful subtotal and a later runner failure.
3. A real same-test successful retry, if retry normalization remains required.

All three must receive deliberate, distinguishable treatment. No such checks were run here.

### A2 — P1: nine scoped suites lack Xcode/iOS discovery

The following filenames had no project references/source membership in `PostHog.xcodeproj/project.pbxproj`:

- `PostHogDeviceBucketingTests.swift`
- `PostHogEnrichedAnalyticsTest.swift`
- `PostHogErrorTrackingIgnoredTypesTest.swift`
- `PostHogExceptionStepsBufferTest.swift`
- `PostHogExceptionStepsTest.swift`
- `PostHogFeatureFlagsTest.swift`
- `PostHogFeatureFlagsV3Test.swift`
- `PostHogFileBackedQueueAlignmentTest.swift`
- `PostHogFileBackedQueueConcurrencyTest.swift`

SPM discovers these on macOS, but `.github/workflows/test.yml:48–74` routes simulator testing through the Xcode scheme. Directory presence does not establish simulator execution.

**Smallest repair:** Add the intended files to Xcode test source membership, then inspect actual discovered/executed tests. Preserve platform guards.

**Mutation suggestion:** Introduce a temporary failing assertion in one newly routed eligible test and verify the simulator job fails before restoring it.

### A3 — P1: shared request recording is unsynchronized

**Evidence:** `PostHogTests/TestUtils/MockPostHogServer.swift:15–26,61–94,536–560` exposes and mutates bare request arrays and expectation state. Network completion callbacks append while tests poll/read/reset. For example, `PostHogLogsCaptureTest.swift:134–159` iterates `logsRequests` while awaiting additional requests.

Only push request storage has an explicit lock (`MockPostHogServer.swift:27–36`). Serial test scheduling does not serialize a test with its network callbacks.

**Smallest repair:** Protect request recording and snapshot reads consistently. Reset/request-generation changes must not race with callbacks from the prior generation. Avoid invoking arbitrary handlers while holding the state lock.

**Validation:** Run relevant API/log/flag consumers with race detection through a repository-approved make target. No race-detector result is claimed.

### A4 — P1: baseline SDK fixtures leave HTTP stubs registered

**Evidence:** Baseline `PostHogIdentityTests.swift:44–49` calls `server.reset()` in teardown rather than `server.stop()`. Baseline DeviceBucketing used the same pattern. `MockPostHogServer.swift:527–534` removes registered stub descriptors only in `stop()`; `reset()` clears observations but does not unregister stubs. Stub handlers capture their server.

This leaves stale handlers/server state alive across tests. Identity teardown also resets SDKs and deletes the entire application-support root (`PostHogIdentityTests.swift:31–35`), widening cross-test effects.

**Smallest repair:** Close owned SDKs before stopping their server; unregister owned stubs; clean only owned storage. Avoid teardown operations that initiate new network work.

**Parent-owned partial repair:** The later DeviceBucketing diff closes SDKs, uses per-token cleanup, calls `server.stop()`, disables the queue timer, and disables automatic remote config. This auditor did not validate that change or review the supplied checkpoint patch. Identity still had the baseline pattern when inspected.

**Rage-click qualification:** This proves a fixture-isolation defect, **not** a leaked rage-click installation. See unresolved item U3.

### A5 — P2: host/path tests prove response success, not URL construction

**Evidence:** Shared API helpers at `PostHogApiTest.swift:39,49,83,93` check successful responses. `MockPostHogServer` matches endpoint suffixes, so a wrong port or dropped base path can still receive the expected response.

Affected declarations are listed under `TestBatchEndpoint`, `TestSnapshotEndpoint`, `TestPushSubscriptionEndpoint`, and `TestFlagsEndpoint` in the ledger.

**Smallest repair:** Require the actual request and compare independently specified scheme, host, port, path, and relevant query values for every existing host case. Preserve all seven cases per endpoint.

**Mutation:** Drop the configured base path or port in endpoint construction. The corresponding host case must fail. Request goldens cover a concrete localhost configuration, not this entire matrix.

### A6 — P2: custom-header privacy negatives pass without a destination request

**Evidence:** `PostHogApiTest.swift:490–505` and `:508–526` end with:

`captured.request?.value(forHTTPHeaderField: "Authorization") == nil`

This succeeds when no request was captured. Callback success and destination reachability are not required.

**Smallest repair:** Require the captured destination request, assert its destination and successful operation, then assert the header’s absence. For redirects, also establish that the initial request carried the configured header.

**Mutation:** Suppress the rewritten-host request or fail redirect handling before reaching the destination. Both tests must fail rather than pass their negative assertion.

### A7 — P2: logs identity-snapshot test does not change identity before flushing

**Evidence:** `PostHogLogsCaptureTest.swift:256–281` identifies `user-A`, captures, then identifies `user-B` without reset. `PostHogSDK.swift:930–1023` does not switch an already-identified SDK to a different ID this way. The asserted `user-A` therefore does not distinguish capture-time from flush-time identity.

The setup also uses `maxBatchSize: 1`; the repaired scenario must explicitly prevent early delivery.

**Smallest repair:** Disable automatic/threshold flushing, capture under A, perform a supported transition to B, require `getDistinctId() == "user-B"`, and require no logs request before explicit flush. Then require the captured record still has A.

**Mutation:** Resolve the log’s distinct ID at serialization/flush time. The repaired test must fail.

### A8 — P2: logs persistence/FIFO tests only inspect depth

**Evidence:**
- `PostHogLogsQueueTest.addPersistsRecord`, `:109–118`: depth becomes one; no disk/reopen proof.
- `fifoEvictionAtMaxBufferSize`, `:122–138`: after adding `"1"` through `"5"` to capacity three, only depth three is checked.

The FIFO test passes if the queue drops newest records or evicts the wrong entries.

**Smallest repair:** Verify durable recovery through a reopened queue for persistence; decode delivered/recovered bodies and require `["3", "4", "5"]` in FIFO order for eviction.

**Mutations:** Disable persistence; replace oldest eviction with newest eviction. Preserve lower-level file-queue tests because they cover a different boundary.

### A9 — P2: logs concurrent-capture oracle removes duplicate evidence

**Evidence:** `PostHogLogsCaptureTest.swift:134–163` accumulates bodies into a `Set`. The comment promises “No duplicates, no missing records,” but duplicate deliveries vanish before assertion.

**Smallest repair:** Keep the raw delivered-body array/multiset. Assert total count and exact expected membership/multiplicity.

**Mutation:** Duplicate each log during enqueue or batching. The test should fail even though the unique set remains correct.

### A10 — P2: poison-record drain has no failure deadline

**Evidence:** `PostHogLogsQueueTest.swift:345–348` loops while depth is nonzero without a deadline. A regression retaining singleton 413 records can hang rather than produce a bounded test failure.

**Smallest repair:** Use a bounded drain and assert completion, preserving the request-count assertion and singleton-removal behavior. Decode record identities if strengthening the record-by-record claim.

**Mutation:** Retain a singleton on 413. Require an assertion failure within the test’s deadline.

### A11 — P2: log codec omits a distinct observed-timestamp assertion

**Evidence:** `PostHogLogsQueueTest.swift:867–908` checks `timeUnixNano`, but not `observedTimeUnixNano`. The record constructor defaults the observed timestamp to event time (`PostHog/Logs/PostHogLogRecord.swift:77–105`), so equal defaults would not expose conflation anyway.

**Smallest repair:** Supply distinct explicit timestamp strings and assert both survive storage serialization.

**Mutation:** Omit `observedTimeUnixNano` or deserialize it from `timeUnixNano`.

### A12 — P2: circular-reference fixture is acyclic

**Evidence:** `PostHogExceptionProcessorTest.swift:116–129` constructs `error2 → error1`, with no link back. `count <= 2` also permits an empty result.

**Smallest repair:** Use a fixture that actually returns itself or a prior NSError as its underlying error; prove the cycle exists before calling production code; require the expected unique exception entries. Keep `walksErrorChain` for the distinct acyclic-ordering contract.

**Mutation:** Remove visited-error protection. Execute only with an external deadline so the controlled defect cannot hang the campaign.

### A13 — P2: crash classification and UUID checks contain vacuous branches

**Evidence:**
- `PostHogCrashReportProcessorTest.swift:111–131`: `frames ?? []` can execute no assertions.
- `:208–229`: `marksFramesAsInApp` checks only that the filtered array is non-nil, not that it contains a matching in-app frame.
- `:233–259`: the system-frame loop can be empty.
- `PostHogExceptionProcessorTest.swift:328–345`: UUID validation is skipped entirely when no UUID-bearing image is found.
- `PostHogDebugImageProviderTest.swift:37–66`: address/UUID loops do not establish a nonempty population within those scenarios.

**Smallest repair:** Require suitable subjects before checking fields. For classification, select/construct frames with known module identities and assert their individual expected classifications. Do not rely solely on whatever stack a particular runner happens to expose.

**Mutations:** Return empty frames; mark every frame not-in-app; omit exception debug IDs; return no eligible UUID-bearing images.

Sibling nonempty tests are valuable retained coverage but do not make each conditional oracle independently meaningful.

### A14 — P2: “main executable” accepts a PostHog library image

**Evidence:** `PostHogDebugImageProviderTest.swift:26–33` accepts any image whose name contains `"xctest"` or `"PostHog"`.

**Smallest repair:** Identify the actual runner executable independently and require its exact image identity/path, accommodating the supported runners deliberately.

**Mutation:** Omit only the executable image while retaining PostHog libraries. The repaired test must fail.

### A15 — P2: feature-flag clearing and equivalence tests need stronger preconditions

**Evidence:**
- `PostHogFeatureFlagsTest.swift:241–285` proves disk clearing for person and group properties, but the reload assertion checks only person `"plan"` absence. It does not prove in-memory group properties were cleared.
- `:377–410` conditionally checks reset person properties only when the dictionary cast succeeds.
- `:830–849` compares optional results, allowing `nil == nil`.
- `:909–920` compares single/all results by iterating `getAllFeatureFlags() ?? []`, allowing no comparisons.

**Smallest repair:** Establish populated pre-reset state; require request/container shapes that the contract promises; check both person and group removal; require known loaded flags and the expected key population before comparing result APIs. Preserve dedicated expected-value tests.

**Mutations:** Retain in-memory group properties after clear; omit required person properties; return nil from both flag APIs; return an empty all-results collection.

### A16 — P2: “stays installed after enabled config” need not observe a fetch

**Evidence:** `PostHogIntegrationInstallationTest.swift:269–294` polls `hasFetchedRemoteConfig`, but `waitUntil` silently returns at timeout (`TestUtils/TestPostHog.swift:187–192`). The final assertion only checks an integration that was already installed before the wait.

**Smallest repair:** Require fetch completion and the expected enabled response before checking retention. Use a completion/latch tied to this SDK where possible.

**Mutation:** Prevent the config request/completion entirely. The test must fail rather than accept its initial installed state.

### A17 — P2: selected queue stress oracles permit substantial lost/no-op work

**Evidence:**
- `PostHogFileBackedQueueConcurrencyTest.swift:185–212`: no deletes occur, but the final count may be anywhere from 50 to 250. Losing all concurrent writes passes.
- `:216–235`: a completely no-op delete implementation satisfies `0 <= depth <= 100`.
- `:106–135`: mixed-operation proof only has a lower bound; duplicate adds can exceed the number submitted.

**Smallest repair:** For reads/writes require exactly 250 uniquely expected records. For indexed deletes require observable deletion plus memory/disk consistency without imposing an invalid scheduling-dependent exact count. For mixed operations add the valid upper bound and uniqueness checks.

**Mutations:** Drop writes while reads occur; make indexed delete a no-op; duplicate concurrent adds. Keep crash/stress scenarios rather than deleting them as “assertion-light.”

### A18 — P2: autocapture integration count assertions do not identify captured events

**Evidence:** `PostHogAutocaptureIntegrationSpec.swift:59–115` checks only aggregate batch counts. Setup at `:20–33` enables autocapture but does not disable unrelated lifecycle capture. Counts do not establish `$autocapture` event identity or distinct source handling.

**Smallest repair:** Disable unrelated automatic capture in this fixture and assert event name plus relevant source/properties, retaining count and debounce checks. Use explicit readiness/gating instead of relying on incidental flush timing.

**Mutation:** Emit a wrong event name while retaining event counts. The processing scenarios should fail.

### A19 — P2: two test names overstate their current proof

- `PostHogConfigTest.swift:98–101`, `"should enable autocapture by default"`, asserts **false**, matching `PostHogConfig.captureElementInteractions`’ default. Rename to describe disabled-by-default behavior; do not change production policy to fit the name.
- `PostHogConsoleLogInterceptorTest.swift:34–61`, `stopCapturingRestoresOriginalDescriptors`, promises stdout **and stderr**, but redirects/verifies only stdout. Exercise stderr independently as well.

These are small maintenance/proof repairs, not grounds to remove the tests.

### A20 — P2: request-body helpers turn malformed input into traps or hangs

**Evidence:**
- `TestUtils/URLSession+body.swift:27–29` appends the stream’s return count without handling negative/error or zero-byte reads.
- `TestUtils/MockPostHogServer.swift:563–575` force-unwraps the body and `unzippedData`; a gzip error is caught and then the nil result is force-unwrapped.

**Smallest repair:** Handle stream EOF/error explicitly with guaranteed resource cleanup; return nil or throw a useful parsing error rather than force-unwrapping. Callers should record a diagnostic assertion failure.

**Controlled checks:** Absent body, malformed gzip, a stream returning an error, and EOF/zero reads. Preserve the helpers because many suites depend on real request decoding.

## Unresolved dispositions

### U1 — HTTP retry policy

`PostHogApiTest.doesNotRetryNonTransientURLSessionErrors(errorCode:)` includes `NSURLErrorCannotConnectToHost` at `:710`. Canonical HTTP-client guidance treats transient connection/socket failures as retryable; the existing implementation’s retry classification is narrower.

Per supervisor decision, retain this parameter row as **U**, pending separate production/spec policy work. The cancellation row remains **R**. Do not silently change expected retry policy as test cleanup.

### U2 — logs recovery ramp policy

`PostHogLogsQueueTest.capStaysPutOnSuccess`, `:234–264`, explicitly pins no upward recovery. The logs spec recommends a healthy-send ramp with **SHOULD**, not **MUST**.

Per supervisor decision, retain as **U**, pending deliberate policy resolution. This is not asserted to be a mandatory-spec violation.

### U3 — baseline privacy failure / suspected rage-click installation leak

The relevant scoped integration tests are:

- `PostHogAutocaptureTextPrivacyTest.rageClickOnly(captureText:)`, `:106`, both `true` and `false`.
- `PostHogAutocaptureTextPrivacyTest.pipeline(captureText:)`, `:158`, both `true` and `false`.

**No verified root-cause evidence establishes a leaked rage-click install.** No failure log, owning-instance trace, or isolated-versus-sequence reproduction was captured by this auditor.

Relevant isolation evidence, but not causal proof:

- `resetPostHogTestGlobals()` only resets `now` and `postHogSdkName` (`TestUtils/TestPostHog.swift:139–142`).
- `.resetsGlobalState` invokes that limited reset (`:163–174`); it does not establish that integration ownership/swizzles are reset.
- Identity’s baseline fixture leaks HTTP stubs, but that is not evidence that it leaks a rage-click integration.
- Suite-local `.serialized` is not itself a general process-wide integration-ownership reset.

Mark the two integration declarations’ execution diagnosis **U** and retain both privacy modes. Required follow-up: capture the failing parameter, its predecessor, the SDK/integration owner before setup, and release behavior after close; compare isolated and sequence execution. Do not remove the privacy assertion or add an unexplained global reset merely to make the baseline green.

### U4 — parent-reported device-bucketing failure

The parent reported failure of `"sends $device_id in feature flag requests"` during its baseline run. No independent result was produced here.

`PostHogDeviceBucketingTests.sendsDeviceIdInFlagRequests` is **U** pending the parent’s failing-control/passing-candidate evidence. The contract is retained. Parent-owned isolation changes observed later are not proof that the diagnosis is complete.

### U5 — XCTest failure attribution from Swift Testing helpers

`getBatchedEvents`, `waitFlagsRequest`, and `waitForFeatureFlagsLoaded` use `XCTFail`/`XCTWaiter` and are consumed by Swift Testing tests (`TestUtils/TestPostHog.swift:39–76`).

Retain pending a controlled timeout proving failure attribution under the actual runner. This audit did not inspect enough XCTest/Swift Testing bridge behavior to claim these failures are lost.

## Exact-name decision ledger

### 1. Transport, logging, and wire compatibility

#### `PostHogApiTest.swift`

**Contract:** Endpoint construction, compression, header isolation, registration serialization, retry budgets, and safe response processing.

**R**
- `pushSubscriptionBodyFields`
- `pushSubscriptionBodyIdentityToken`

**F — A5: `TestBatchEndpoint`**
- `hostWithNoPath`
- `hostWithNoPathAndTrailingSlash`
- `hostWithPath`
- `hostWithPathAndTrailingSlash`
- `hostWithPortNumber`
- `hostWithPortNumberAndPath`
- `hostWithPortNumberAndTrailingSlash`

**F — A5: `TestSnapshotEndpoint`**
- `testHostWithNoPath`
- `testHostWithNoPathAndTrailingSlash`
- `testHostWithPath`
- `testHostWithPathAndTrailingSlash`
- `testHostWithPortNumber`
- `testHostWithPortNumberAndPath`
- `testHostWithPortNumberAndTrailingSlash`

**F — A5: `TestPushSubscriptionEndpoint`**
- `testHostWithNoPath`
- `testHostWithNoPathAndTrailingSlash`
- `testHostWithPath`
- `testHostWithPathAndTrailingSlash`
- `testHostWithPortNumber`
- `testHostWithPortNumberAndPath`
- `testHostWithPortNumberAndTrailingSlash`

**R: `TestContentEncodingHeader`**
- `batchDeclaresGzip`
- `snapshotDeclaresGzip`
- `logsDeclaresGzip`
- `pushSubscriptionDeclaresGzip`
- `batchFallsBackToUncompressedWhenGzipFails`
- `flagsDoesNotDeclareGzip`
- `compressionDefaultsToGzip`
- `batchSendsUncompressedWhenCompressionIsNone`
- `snapshotSendsUncompressedWhenCompressionIsNone`
- `logsSendsUncompressedWhenCompressionIsNone`
- `batchDropsSessionContentEncodingWhenCompressionIsNone`
- `pushSubscriptionSendsUncompressedWhenCompressionIsNone`

Header tests retain their narrow contract; body-decoding/golden coverage supplies additional serialization proof.

**R: `TestCustomRequestHeaders`**
- `attachesToBatch`
- `attachesToFlags`
- `noHeaderWhenUnset`
- `doesNotOverrideSDKManagedHeaders`

**F — A6: `TestCustomRequestHeadersHostScoping`**
- `skipsRewrittenConfigHost`
- `stripsHeadersOnCrossHostRedirect`

**R: `TestFlagsEndpoint`**
- `featureFlagRetryDelayStartsAt300msAndDoubles`
- `retriesURLSessionErrors`
- `retriesRetryableHTTPStatusResponses` — `502`, `504`
- `doesNotRetryRetryableHTTPStatusResponsesWhenFeatureFlagRequestMaxRetriesIsZero` — `502`, `504`
- `doesNotRetryWhenFeatureFlagRequestMaxRetriesIsZero`
- `stopsRetryingRetryableHTTPStatusResponsesAfterFeatureFlagRequestMaxRetries` — `502`, `504`
- `stopsRetryingTransientURLSessionErrorsAfterFeatureFlagRequestMaxRetries`
- `doesNotRetryNonTransientURLSessionErrors` — **R:** `NSURLErrorCancelled`; **U:** `NSURLErrorCannotConnectToHost`, U1
- `doesNotRetryHTTPErrorResponses` — `408`, `429`, `500`

**F — A5: `TestFlagsEndpoint`**
- `testHostWithNoPath`
- `testHostWithNoPathAndTrailingSlash`
- `testHostWithPath`
- `testHostWithPathAndTrailingSlash`
- `testHostWithPortNumber`
- `testHostWithPortNumberAndPath`
- `testHostWithPortNumberAndTrailingSlash`

**R: `TestUploadResponseHandling`**
- `preservesHTTPStatusAlongsideError` — `200`, `400`, `408`, `429`, `503`
- `dropsRedirectStatusAlongsideError` — `301`, `302`, `307`, `308`
- `preservesRetryAfterAlongsideError`

**R: `TestNonHTTPResponseHandling`**
- `flagsHandlesNonHTTPResponse`
- `remoteConfigHandlesNonHTTPResponse`

These protect against force-cast crashes and against dropping durable data because a failed redirect misleadingly retains a status.

Support: retain `NonHTTP` URLProtocol fixture and locked `CapturedRequestBox`; repair endpoint helpers with A5. Their narrow transport simulation is not a reason to delete them.

#### `PostHogLogsCaptureTest.swift`

**Contract:** Public logging entry points, consent/close gates, severity mapping, capture-time context, encoding, lifecycle flushing, ObjC exception containment, and concurrent delivery.

**R**
- `captureFromMainThread`
- `captureFromBackgroundThread`
- `captureEmptyBody`
- `captureWhileOptedOut`
- `loggerInfoEquivalence`
- `loggerAllLevels`
- `captureWirePayloadResourceAttributes`
- `flushFromBackgroundThread`
- `backgroundingFlushesLogs`
- `objcBeforeSendExceptionDropsLog`
- `captureWithTraceContext`
- `captureWhitespaceBody`
- `captureUnicodeBodyRoundTrip`
- `captureAfterClose`
- `captureRateCapDropsAtSDKBoundary`

**F**
- `captureConcurrent` — A9
- `captureSnapshotsDistinctIdAtCaptureTime` — A7

Retain SDK-boundary consent/rate-limit cases even where lower-level queue tests cover related rules.

#### `PostHogLogsQueueTest.swift`

**Contract:** Durable bounded buffering, delivery/backpressure, retry/drop decisions, rate limiting, before-send behavior, concurrent usability, reachability, OTLP shape, and disk codec compatibility.

**R**
- `flushSendsBatch`
- `thresholdFlush`
- `flushEmpty`
- `handle413HalvesCap`
- `handle413SingleRecordDrops`
- `handle5xxRetains`
- `handle413HalvesByActualBatchSize`
- `handleNon413_4xxDrops`
- `rateCapEnforced`
- `rateCapWindowResets`
- `rateCapDisabled`
- `rateCapDisabledWhenNegative`
- `nonLogsEndpointsDisableRateCap`
- `beforeSendDrop`
- `beforeSendEmptyBodyDrops`
- `beforeSendMutates`
- `concurrentAdd`
- `concurrentAddAndFlush`
- `clearRacingAdd`
- `reachabilityPauseAndResume`
- `sdkFlushDrainsLogsQueue`
- `otlpPayloadShape`
- `otlpNonStringAttributeTypes`
- `traceFlagsOnTheWire`

`concurrentAddAndFlush` retains a progress/drain contract; it is not claimed to establish exact-once delivery by itself.

**F**
- `addPersistsRecord` — A8
- `fifoEvictionAtMaxBufferSize` — A8
- `handle413PoisonDropIsNotARetry` — A10
- `recordRoundTripsThroughDiskCodec` — A11

**U**
- `capStaysPutOnSuccess` — U2

#### `PostHogEventSnapshotTests.swift`

**R**
- `enrichedEventBatchGolden`
- `sessionReplayRequestGolden`
- `featureFlagRequestGolden`

**Contract/regression:** Preserve request method, destination, headers, envelope keys, enrichment, identity transitions, feature interactions, exception shape, and replay payloads. These detect wiring/serialization drift that individual value tests miss.

Read the three corresponding JSON goldens. Normalization deliberately removes unstable environment values while retaining types/shapes. Retain normalization/assertion helpers; do not regenerate goldens merely to accept unexplained changes.

### 2. Durable queues and migration

#### `PostHogFileBackedQueueTest.swift`

**R — all Quick declarations**
- `"create folder and init queue"`
- `"load cached files into memory"`
- `"trims cached files to configured capacity on load"`
- `"delete from queue and disk"`
- `"pop from queue and disk"`
- `"removes exact stable entry identities"`
- `"enforces capacity atomically across concurrent adds"`
- `"add to queue and disk"`
- `"clear queue and disk"`
- `"loads and sorts files in chronological order"`
- `"migrates files from old queue folder to new queue folder"`

**Contract/regression:** Initialization/recovery, bounded storage, stable entry removal, disk-memory alignment, ordering, and migration. Stable identities protect against acknowledging the wrong records after queue contents change.

#### `PostHogFileBackedQueueAlignmentTest.swift`

**R**
- `failedWritePreservesFullQueue`
- `happyPath`
- `tiedCreationDatesTrimDeterministically`
- `unreadableFilePrecedingReturnedItems` — `.missing`, `.corrupt`
- `depthReflectsPrunedEntries`
- `deletesRunOfCorruptFiles`
- `deleteRemovesStuckHead`
- `keepsTemporarilyUnreadableFile`
- `prunesCorruptBeforeTemporarilyUnavailable`
- `randomizedNoDuplicateDelivery`
- `concurrentPruneIsThreadSafe`

**Contract/regression:** Failed writes must not evict accepted events; corrupt/missing files must not shift acknowledgment onto unrelated records; temporary unreadability differs from permanent corruption. Retain seeded randomized coverage alongside deterministic reproductions.

**Routing F:** A2 applies to this file.

#### `PostHogFileBackedQueueConcurrencyTest.swift`

**R**
- `concurrentAddPreservesAllEvents`
- `highlyConcurrentAddPreservesAllEvents`
- `concurrentDeleteDoesNotCrash`
- `concurrentAddOperations`
- `concurrentAddsDetectDuplicateFilenames`
- `chaoticMixOfAllOperations`
- `maximumContentionStressTest`

**F — A17**
- `mixedConcurrentOperations`
- `concurrentReadsAndWrites`
- `concurrentDeletesAtVariousIndices`

**Contract/regression:** Lost additions, filename collisions, invalid-index crashes, and disk/index divergence under contention. `maximumContentionStressTest` is a useful stress input, not evidence that CI actually enables TSan.

**Routing F:** A2 applies.

#### `PostHogLegacyQueueTest.swift`

**R**
- `"migrate old queue to new queue"`
- `"ignore and delete corrupted file"`

**Contract/regression:** Upgrade compatibility preserves valid historical events and does not leave corrupt historical storage blocking migration. Do not delete merely because the old producer no longer exists.

### 3. Identity, feature flags, and enriched analytics

#### `PostHogIdentityTests.swift`

**R — test contracts retained**
- `doesNotClearAnonymousIdOnReset`
- `doesNotClearAnonymousIdOnClose`
- `anonymousIdIsNotOverwrittenOnReIdentifyWhenReuseAnonymousIdIsTrue`
- `anonymousIdIsRetailainedAcrossSeriesOfIdentifyAndResetReuseAnonymousIdIsTrue`
- `skipAnonDistinctIdInIdentifyEventWhenFlagReuseAnonymousIdIsTrue`
- `identifySetsDistinctAndAnonIds`
- `capturesCaptureEventWithCustomDistinctId`
- `capturesIdentifyEvent`
- `capturesEventWithIsIdentifiedFalse`
- `doesNotCaptureIdentifyEventIfAlreadyIdentified`
- `updatesUserPropsWhenAlreadyIdentified`
- `doesNotCaptureUserPropsForDifferentDistinctId`
- `capturesAliasEvent`
- `setupsDefaultIds`
- `setPersonPropertiesSendsSetEvent`
- `setPersonPropertiesDeduplicatesIdenticalCalls`
- `setPersonPropertiesAllowsDifferentPropertyValues`
- `setPersonPropertiesWithOnlySetOnceProperties`
- `setPersonPropertiesIgnoresEmptyProperties`
- `setPersonPropertiesUsesCurrentDistinctId`
- `setPersonPropertiesDeduplicatesNestedDictionariesWithDifferentKeyOrder`
- `identifyDeduplicatesSetEventWithSameProperties`
- `identifyDoesNotDeduplicateSetEventWithDifferentProperties`
- `identifyAndSetPersonPropertiesShareDeduplicationCache`
- `identifyDeduplicatesWithSetOnceProperties`
- `optedOutPropertiesCanBeSentAfterRelaunch`
- `droppedSetCanBeRetriedAfterRelaunch`
- `resetClearsPersistedDeduplication`
- `failedQueueWriteCanBeRetriedAfterRelaunch`
- `failedQueueWriteStillNotifiesSubscribers`
- `droppedTransitionCanBeRetriedAfterRelaunch`
- `concurrentIdenticalPropertiesAreDeduplicated`
- `changedBeforeSendOutputIsCapturedAfterRelaunch` — `useIdentify=false,true`
- `sanitizedEmptyPropertiesAreDeduplicated` — all four `useIdentify × setOnce` Boolean combinations
- `enqueueFailuresStillNotifyLocalIntegrations` — `personUpdate=false,true`
- `setPersonPropertiesDeduplicationSurvivesRelaunch`
- `setPersonPropertiesCapturesAfterRelaunchWhenPropertiesChanged`
- `setPersonPropertiesCapturesAfterRelaunchWhenPropertiesWithDateChanged`
- `setPersonPropertiesDeduplicatesSanitizedEmptyProperties`
- `sanitizedEmptyPropertiesDeduplicationSurvivesRelaunch`
- `identifyDoesNotResendPropertiesCarriedByIdentifyAfterRelaunch`

**Contract/regression:** Identity state/wire semantics and deduplication must distinguish accepted durable updates from dropped, opted-out, or failed updates. Relaunch, reset, sanitizer output, and concurrency cases protect genuinely different failure modes.

**Fixture F:** A4 applies to setup/teardown, not a recommendation to remove any declaration.

#### `PostHogDeviceBucketingTests.swift`

**R**
- `initializesDeviceIdOnFirstSetup`
- `preservesDeviceIdAcrossIdentify`
- `preservesDeviceIdAcrossReset`
- `preservesDeviceIdAcrossMultipleCycles`
- `sendsSameDeviceIdAfterIdentify`
- `persistsDeviceIdAcrossSdkRestarts`

**U**
- `sendsDeviceIdInFlagRequests` — U4

**Contract/regression:** Device bucketing uses a stable persistent ID rather than a changing user/anonymous identity. `PostHogSDK.swift:401–408` is the relevant ownership seam.

**Fixture/routing F:** Baseline A4 and A2. Parent-owned repairs were observed but not validated.

#### `PostHogFeatureFlagsTest.swift`

**Contract:** Loaded/cache/bootstrap result semantics; payload decoding; person/group overrides; usage events; evaluation contexts; and reload completion/order.

**R**
- `returnsTrueBoolean`
- `returnsTrueString`
- `returnsFalseDisabled`
- `getFeatureFlagValue`
- `getFeatureFlagPayloadInt`
- `getFeatureFlagPayloadDictionary`
- `loadsCachedFeatureFlags`
- `mergeFlagsIfComputedErrors`
- `retainsFeatureFlagsWhenQuotaLimited`
- `clearRemovesInMemoryFeatureFlags`
- `storeAndRetrievePersonProperties`
- `personPropertiesAreAdditive`
- `storeAndRetrieveGroupProperties`
- `multipleGroupTypesHandled`
- `resetGroupPropertiesSpecificType`
- `resetAllGroupProperties`
- `bothPersonAndGroupPropertiesSent`
- `captureWithUserPropertiesAutomaticallySetsPersonPropertiesForFlags`
- `groupWithGroupPropertiesAutomaticallySetsGroupPropertiesForFlags`
- `returnsResultForEnabledBoolFlag`
- `returnsResultForVariantFlag`
- `returnsResultForDisabledFlag`
- `returnsNilForNonExistentFlag`
- `includesPayloadInResult`
- `sendsEventByDefault`
- `respectsSendEventParameterFalse`
- `returnsNilBeforeLoad`
- `returnsAllFlagsIncludingDisabled`
- `decodesPayloads`
- `doesNotSendEvent`
- `payloadAsNil`
- `payloadAsDirectMatchString`
- `payloadAsDirectMatchInt`
- `payloadAsDirectMatchDict`
- `payloadAsDecodable`
- `payloadAsInvalidType`
- `payloadAsDecodingFails`
- `evaluationContextsIncludedInRequest`
- `emptyEvaluationContextsNotIncluded`
- `nilEvaluationContextsNotIncluded`
- `canUpdateEvaluationContexts`
- `deprecatedEvaluationEnvironmentsStillWorks`
- `servesBootstrappedFlagsBeforeLoad`
- `sanitizesInvalidBootstrappedValues`
- `servesBootstrappedPayload`
- `loadedFlagsOverrideBootstrap`
- `disabledBootstrapFlagNotServed`
- `disabledBootstrapPayloadNotServed`
- `completeLoadDropsBootstrappedOnlyKeys`
- `bootstrapNotReappliedAfterReset`
- `bootstrapSeedFiresFlagsLoaded`
- `reportsUsedBootstrapTrueBeforeLoad`
- `reportsUsedBootstrapFalseAfterLoad`
- `displacedReloadResolvesAgainstRealResponse`
- `startupSequenceReadsFlagsWithOverrides`
- `setPropertiesThenReloadResolvesWithProperties`
- `queuedReloadCarriesLatePersonProperties`
- `completionResolvesOnFailedReload`

**F — A15**
- `clearClearsPersonAndGroupProperties`
- `resetPersonPropertiesClearsAll`
- `getFeatureFlagReturnsSameValue`
- `matchesSingleKeyResult`

`PostHogRemoteConfig.clear()` intentionally preserves project remote configuration/fetch state while clearing identity-related flag state. Do not broaden clearing expectations accidentally. Keep bootstrap and reload-order scenarios: they catch stale-response/completion errors that simple getters cannot.

**Routing F:** A2.

#### `PostHogFeatureFlagsV3Test.swift`

**R**
- `returnsTrueBoolean`
- `returnsTrueString`
- `returnsFalseDisabled`
- `getFeatureFlagValue`
- `getFeatureFlagPayloadInt`
- `getFeatureFlagPayloadDictionary`
- `loadsCachedFeatureFlags`
- `mergeFlagsIfComputedErrors`
- `retainsFeatureFlagsWhenQuotaLimited`

**Contract/regression:** Legacy response-format compatibility is distinct from the newer envelope’s identical public result semantics. Similar test names do not establish redundant coverage.

**Routing F:** A2.

#### `PostHogEnrichedAnalyticsTest.swift`

**R**
- `capturesFeatureViewEvent`
- `capturesFeatureInteractionEvent`
- `doesNotCaptureFeatureViewWhenNoVariant`
- `doesNotCaptureFeatureInteractionWhenNoVariant`
- `doesNotCaptureFeatureViewIfOptOut`
- `doesNotCaptureFeatureInteractionIfOptOut`
- `doesNotCaptureFeatureViewIfDisabled`
- `doesNotCaptureFeatureInteractionIfDisabled`

**Contract/regression:** Feature view/interaction capture and person-property enrichment respect variant availability and SDK consent/enabled gates. Production ownership: `PostHogSDK.captureFeatureEvent`, `:2251–2288`.

**Routing F:** A2.

### 4. Platform integrations, lifecycle, configuration, and privacy

#### `ApplicationViewLayoutPublisherTest.swift`

**R**
- `lifecycleStaleCount`
- `lifecycleConcurrentSubscriptions`
- `concurrentFirstAccess`
- `forwardsCapturedLayoutAfterUnsubscribe` — `background=false,true`
- `preservesNewerSwizzler`
- `retiredHookDoesNotDuplicateNotifications`
- `externallyDetachedHook` — all four `removeEarlierSwizzler × retainOtherSubscriber` Boolean combinations
- `forwardsLayout` — `background=false,true`
- `warnsAboutBackgroundLayout` — `calls=1,32`
- `throttleLayoutViews`

**Contract/regression:** Preserve host layout forwarding, subscription ownership, main-thread notification semantics, warning throttling, and compatibility with other swizzlers. Captured/retired hooks and externally detached hooks are different compatibility hazards; retain both.

#### `BundleUtilsTest.swift`

**R**
- `returnsIntForNumericValue`
- `returnsStringForDottedValue`
- `returnsStringForAlphanumericValue`
- `returnsStringForEmptyValue`
- `returnsIntForZero`

**Contract/regression:** Bundle-version serialization preserves nonnumeric versions while representing numeric versions as integers (`PostHog/Utils/BundleUtils.swift:6–7`). These are externally observable payload types, not merely an implementation inventory.

#### `PostHogAppLifeCycleIntegrationTest.swift`

**R**
- `installsWithCaptureDisabled`
- `disabledClientDoesNotBlockLifecycleCapture` — `previousInstall=false,true`
- `disabledCaptureRemembersVersion` — `previousInstall=false,true`
- `enablingCaptureDoesNotFabricateInstall`
- `sameBuildRefreshesVersion`
- `capturesApplicationInstalledEvent`
- `capturesApplicationUpdatedEvent`
- `capturesDelayedApplicationInstalled`
- `capturesApplicationInstalledEventOnce`
- `capturesApplicationOpenedEvent`
- `capturesApplicationBackgroundedEvent`
- `respectsConfigurationAndDoesNotEmitEvents`
- `capturesApplicationOpenedEventFromBackgroundTrue`
- `doesNotCaptureConsecutiveApplicationBackgroundedEvents`
- `flushesQueueOnBackground`

**Contract/regression:** Installation ownership and capture consent differ; disabled clients must not block enabled capture or fabricate future installation events. Persisted versions, duplicate notifications, background metadata, and background flushing are distinct contracts.

#### `PostHogAutocaptureEventTrackerSpec.swift`

**R — all Quick declarations**
- `"should correctly create event data for UIView"`
- `"should correctly create event data for UIView with view hierarchy"`
- `"when sanitizing text for autocapture text should be trimmed"`
- `"when sanitizing text for autocapture text should be limited"`
- `"should not track hidden views"`
- `"should not track views without user interaction enabled"`
- `"should not track views marked as ph-no-capture"`
- `"should track views that are visible and interactive"`

**Contract/regression:** Hierarchy/event extraction, bounded normalized text, and view exclusion. Production `shouldTrack` and event-data construction are separate from SDK wire delivery, so retain these lower-cost checks.

#### `PostHogAutocaptureIntegrationSpec.swift`

**R**
- `"should set the eventProcessor to itself on start"`
- `"should clear the eventProcessor on stop"`

**F — A18**
- `"should process events without a debounce interval"`
- `"should process events from different sources"`
- `"should debounce events if debounceInterval is greater than 0"`

**Contract/regression:** Integration registration, source delivery, and debounce behavior. Strengthen observable events without deleting the routing tests.

#### `PostHogAutocaptureTextPrivacyTest.swift`

**R**
- `defaultRetainsText`
- `removesAncestorText`
- `doesNotReadText`
- `removesInputAndSelectionValues`
- `exclusions` — `captureText=true,false`

**U — U3, retain both modes pending baseline diagnosis**
- `rageClickOnly` — `captureText=true,false`
- `pipeline` — `captureText=true,false`

**Contract/regression:** Disabling text capture must prevent text **reads**, ancestor leakage, and value leakage, not merely remove one final field. The rage-click-only path and integration pipeline remain essential distinct coverage.

#### `PostHogConfigTest.swift`

**R**
- `"init config with default values"`
- `"init takes project token"`
- `"deprecated init(apiKey:) maps to project token"`
- `"deprecated init(apiKey:host:) maps to project token and host"`
- `"deprecated init(apiKey:host:) trims whitespace-sensitive values"`
- `"trims whitespace-sensitive config values"`
- `"defaults a blank host after trimming whitespace"`
- `"init takes host"`
- `"should disable tracing headers by default"`
- `"should allow disabling autocapture"`

**F — A19**
- `"should enable autocapture by default"`

**Contract/regression:** Defaults and deprecated initializers are compatibility promises. Fix the misleading name, not the disabled default.

#### `PostHogConsoleLogInterceptorTest.swift`

**R**
- `stdioIsMarkedNoSigPipeWhileCapturing`
- `capturedStdoutReachesTheCallback`
- `concurrentStartStopWhileLoggingIsSafe`

**F — A19**
- `stopCapturingRestoresOriginalDescriptors`

**Contract/regression:** Descriptor safety, actual capture delivery, and restoration under churn. Retain the stress test: process survival plus descriptor identity is meaningful evidence, even without asserting every captured line.

#### `PostHogContextScreenSizeTest.swift`

**R**
- `reportsSizeOnKeyWindowChange`
- `reportsSizeAfterSilentResize`
- `reportsMeasuredSizeOnRotation`
- `reportsRotatedSizeWhenBoundsFlipLate`
- `reportsRotatedSizeWhenCapturedBeforeBoundsFlip`
- `throttlesAgainAfterTransitionWindow`
- `keepsLastKnownSizeWhenMeasurementIsEmpty`
- `reportsLatestSizeAfterRapidResizes`
- `coalescesRefreshesCapturedOffMain`
- `closesTransitionWindowAfterClockMovesBackwards`
- `refreshesAfterClockMovesBackwards`

**Contract/regression:** Cached context must converge to measured screen state without blocking arbitrary calling threads or leaving transition throttles stuck. Silent resize, delayed bounds flips, and backward-clock behavior are distinct regressions.

The TESTING-only measurement seam is legitimate; it does not by itself prove UIKit’s real measurement source on every device.

#### `PostHogContextTest.swift`

**R**
- `"returns static context"`
- `"returns dynamic context"`
- `"returns sdk info"`
- `"returns person properties context"`

**Contract/regression:** Context field presence/type and public enrichment shape. Preserve these alongside the focused screen-size suite and request goldens.

#### `PostHogDeepLinkIntegrationTests.swift`

**R**
- `buildPropertiesWithValidReferrerURL`
- `buildPropertiesWithNonURLReferrer`
- `buildPropertiesWithoutReferrer`
- `extractsReferringDomainFromUniversalLink`
- `handlesCustomURLScheme`
- `handlesURLWithQueryAndFragment`
- `capturesDeepLinkOpenedEvent`
- `capturesDeepLinkWithUserActivity`
- `ignoresNonBrowsingUserActivity`
- `capturesMultipleURLsFilteringFileURLs`
- `doesNotCaptureWhenDisabled`

**Contract/regression:** Preserve URLs, optional referrers/domains, valid activity filtering, file-URL rejection, and opt-in capture. Pure property construction (`PostHogDeepLinkHelper`) and integration notification routing are complementary.

#### `PostHogIntegrationInstallationTest.swift`

**R**
- `replayIntegrationInstalledOnce`
- `autocaptureIntegrationInstalledOnce`
- `appLifeCycleIntegrationInstalledOnce` — `captureLifecycle=false,true`
- `lifecycleOwnershipReleasedWithSDK` — `explicitClose=false,true`
- `screenViewIntegrationInstalledOnce`
- `noIntegrationsWhenHostOwnsConsent`
- `errorTrackingInstalledBeforeRemoteConfig`
- `errorTrackingNotInstalledWhenRemoteConfigDisables`
- `errorTrackingUninstallsWhenRemoteConfigDisables`
- `errorTrackingInstallsWhenRemoteConfigEnablesAfterCachedDisable`
- `errorTrackingInstallsAfterFailedRemoteConfigFetch`
- `pushNotificationOpenedIntegrationInstalledOnce`
- `pushNotificationOpenedIntegrationNotInstalledWhenDisabled`
- `pushNotificationOpenedIntegrationSkippedWithoutSwizzling`
- `pushNotificationSubscriptionIntegrationInstalledOnce`
- `pushNotificationSubscriptionIntegrationNotInstalledWhenDisabled`
- `pushNotificationSubscriptionIntegrationSkippedWithoutSwizzling`

**F — A16**
- `errorTrackingStaysInstalledWhenRemoteConfigEnables`

**Contract/regression:** Single ownership, release/reacquisition, consent, swizzling configuration, and first-launch versus cached/live remote-config states. Explicit simulated failed-fetch state is appropriate for testing the gate, but is not a replacement for HTTP failure-path tests.

### 5. Exceptions, crash metadata, and exception steps

#### `PostHogCrashReportProcessorTest.swift`

**R**
- `processesLiveCrashReport`
- `liveReportContainsExceptionList`
- `liveReportExceptionHasTypeAndMechanism`
- `liveReportContainsStackTrace`
- `liveReportContainsDebugImages`
- `debugImagesHaveRequiredFields`
- `extractsCrashTimestamp`
- `exceptionHasThreadId`
- `parsesSwiftFatalErrorType`
- `sanitizesCrashInfoMessage`

**F — A13**
- `liveReportFramesHaveInstructionAddresses`
- `marksFramesAsInApp`
- `marksSystemFramesAsNotInApp`

**Contract/regression:** Real crash-report parsing and required server-facing metadata. Keep live-report tests; improve selected-frame proof rather than replacing everything with synthetic dictionaries.

#### `PostHogDebugImageProviderTest.swift`

**R: `GetAllBinaryImagesTests`**
- `returnsNonEmptyList`
- `imagesHaveUUIDs`

**F**
- `includesMainExecutable` — A14
- `imagesHaveValidAddresses` — A13
- `uuidsAreInCorrectFormat` — A13

**R: `GetDebugImagesForFramesTests`**
- `returnsDebugImagesForValidAddresses`
- `returnsEmptyForInvalidAddresses`
- `returnsEmptyForEmptyFrames`
- `deduplicatesImagesByAddress`

**R: `GetDebugImagesFromExceptionsTests`**
- `extractsDebugImagesFromExceptionList`
- `handlesExceptionsWithoutStacktrace`
- `handlesEmptyExceptionList`
- `collectsFromMultipleExceptions`

**R: `BinaryImageInfoDictionaryTests`**
- `omitsNilUUID`
- `omitsZeroVmAddress`
- `omitsNilArch`

**Contract/regression:** Loaded-image enumeration, frame-to-image selection, deduplication, and optional metadata serialization. Empty-input/invalid-address cases are meaningful negatives, unlike accidentally empty positive fixtures.

#### `PostHogErrorTrackingIgnoredTypesTest.swift`

**R**
- `exceptionListMatcher`, all seven exact labels:
  - `"empty ignored list never matches"`
  - `"outer type in ignored list matches"`
  - `"underlying type anywhere in chain matches"`
  - `"type not in list passes through"`
  - `"missing $exception_list key returns false"`
  - `"empty $exception_list returns false"`
  - `"match is case-sensitive (NSException class names are stable identifiers)"`
- `defaultIsRCTFatalException`
- `genericCaptureDropsIgnoredType`
- `genericCaptureKeepsOtherTypes`
- `captureExceptionStillDropsIgnoredType`

**Contract/regression:** Prevent duplicate React Native fatal events while retaining unrelated exceptions. The matcher table and SDK capture tests cover classification and wiring separately.

**Routing F:** A2.

#### `PostHogErrorTrackingUtilsTest.swift`

**R**
- `formatsUUIDWithoutHyphens`
- `preservesFormattedUUID`
- `uppercasesLowercaseUUID`
- `returnsOriginalForInvalidLength`
- `handlesMixedCaseUUID`
- `returnsArm64`
- `returnsX86_64`
- `returnsArmv7`
- `returnsArmv7s`
- `returnsArmForUnknownSubtype`
- `returnsNilForUnknownType`

**Contract/regression:** Server-compatible debug IDs and architecture labels, including malformed/unknown inputs. Retain small deterministic utility tests.

#### `PostHogExceptionProcessorTest.swift`

**R: error conversion**
- `convertsSimpleSwiftError`
- `convertsNSErrorWithDomain`
- `walksErrorChain`
- `usesCustomMechanismType` — error-conversion suite
- `extractsModuleFromDomain`

**F**
- `handlesCircularReferences` — A12

**R: NSException conversion**
- `convertsNSException`
- `handlesExceptionWithoutReason`
- `marksUnhandled`

**R: message conversion**
- `convertsMessageString`
- `messageExceptionsAreSyntheticAndHandled`
- `usesCustomMechanismType` — message-conversion suite

**R: `DebugImagesTests`**
- `attachesDebugImages`

**F**
- `debugImagesHaveValidUUID` — A13

**R: `StackTraceTests`**
- `stackTraceHasRawType`
- `stackTraceContainsFrames`
- `framesHaveRequiredFields`
- `framesHaveHexAddressFormat`

**Contract/regression:** Distinguish NSError chains, Swift errors, NSException, and synthetic message exceptions; preserve mechanism/handled state and symbolication metadata. Same-name mechanism tests exercise different entry paths.

#### `PostHogExceptionStepsBufferTest.swift`

**R: buffer**
- `keepsOrder`
- `evictsOldest`
- `rejectsOversized`
- `rejectsInvalidMessage`
- `validatesTimestamp`
- `clearEmpties`
- `countsUtf8Bytes`
- `handlesUnserializableValue`
- `normalizesStoredStep`
- `publishesStepsOnChange`
- `concurrentAccessIsSafe`

**R: context/steps serialization**
- `writesContextAndSteps`
- `contextChangeKeepsSteps`
- `emptyStepsKeepContext`

**Contract/regression:** Byte-bounded FIFO rather than character/item-count limits; normalization; safe concurrent snapshots; correct context/step merging. Preserve non-ASCII and oversized cases.

**Routing F:** A2.

#### `PostHogExceptionStepsTest.swift`

**R**
- `attachesInOrder`
- `respectsManualOverride`
- `preservesBufferOnManualOverride`
- `concurrentStepsDuringIntegrationChurn`
- `stripsReservedKeys`
- `persistsAcrossCaptures`
- `persistsAcrossIdentityChange`
- `preservesStepsOnDrop`
- `ignoresEmptyMessage`
- `oneBufferPerInstance`
- `timestampReflectsCallTime`
- `disabledIsNoOp`
- `replaysStepsOnOptIn`
- `noReplayWhenBufferEmptyOnOptIn`

**Contract/regression:** Rolling snapshots attach to successive exceptions, survive identity/reset as specified, respect manual overrides and consent, and remain instance-isolated. Do not change to consume-on-capture behavior. Crash durability is a separate layer.

**Routing F:** A2.

### 6. Shared support and ObjC fixtures

These files contain support declarations, not standalone discovered tests.

#### `ExampleSanitizer.swift`

**R — `ExampleSanitizer.sanitize(_:)`.**

Removes empty string-valued properties while preserving other entries. Consumer search found `PostHogSDKTest.swift:1166`, outside this assigned root-file range. It is therefore not unused support. No deletion proposed.

#### `TestUtils/MockApplicationLifecyclePublisher.swift`

**R**
- `MockApplicationLifecyclePublisher`
- `onDidBecomeActive`
- `onDidEnterBackground`
- `onDidFinishLaunching`
- `isInBackground`
- `simulateAppDidEnterBackground`
- `simulateAppDidBecomeActive`
- `simulateAppDidFinishLaunching`

Preserves a controllable multicast event boundary. The simulated event functions do not automatically change `isInBackground`; that property is explicitly configured by consumers. No production-lifecycle equivalence beyond this fixture contract is claimed.

#### `TestUtils/MockScreenViewPublisher.swift`

**R**
- `MockScreenViewPublisher`
- `onScreenView`
- `onNewScreenName`
- `startAutoCapture`
- `stopAutoCapture`
- `simulateAutoCapture`
- `simulateScreenView`
- `didStartAutoCapture`
- `didStopAutoCapture`

Auto-capture callbacks and passive notifications intentionally represent different routes. Keep both rather than collapsing them into a mock that bypasses integration wiring.

#### `TestUtils/TestError.swift`

**R — `TestError` and its string-literal/error-description support.**

Retain useful throwing diagnostics; no standalone test count implied.

#### `TestUtils/URLSession+body.swift`

**F — `URLRequest.body()`**, A20.

Preserve HTTP body/stream access while handling read errors and cleanup.

#### `TestUtils/MockPostHogServer.swift`

**F**
- Request arrays/state and `trackBatchRequest`, `trackSnapshotRequest`, `trackLogsRequest`, `trackFlags` — A3.
- `parseRequest` — A20.
- Lifecycle use of `start`, `reset`, `stop` by owning suites — A4; retain distinct reset versus unregister semantics.

**R**
- Endpoint response fixtures and configurable flag/config/log/batch/push handlers.
- Locked `pushSubscriptionRequests` storage.
- `parsePostHogEvents`, as a consumer of repaired body parsing.

The server has many consumers outside the assigned range. Any shared change requires broader consumer validation; do not replace it with a narrower fixture without that work.

#### `TestUtils/TestPostHog.swift`

**R**
- `TestPollingConfiguration.configure` — retained scheduling/global-reset support, with isolation caveat below.
- `testRequestTimeout`
- `waitForSnapshotRequest`
- `getServerEvents`
- `MockDate`
- `resetPostHogTestGlobals`
- `withMockedNow`
- `withMockedClock`
- `ResetGlobalStateTrait.provideScope`
- `Trait.resetsGlobalState`
- `waitUntil`
- `AsyncLatch.init`, `signal`, `wait`, and its locked continuation/opening support
- `Bundle.test`

**U — U5**
- `getBatchedEvents`
- `waitFlagsRequest`
- `waitForFeatureFlagsLoaded`
- `getFlagsRequest`, transitively through its waiter

`waitUntil` and `AsyncLatch.wait` intentionally do not fail automatically on timeout: callers must assert the awaited end state. A16 identifies a concrete caller that does not prove its prerequisite.

Quick setup resets global time and removes the application-support root (`:20–28`). Existing serialized routing reduces test-to-test overlap, but this is not safe general-purpose parallel isolation. Do not claim `.resetsGlobalState` resets installation ownership or all SDK state.

#### `PostHogTestsObjC/PHBeforeSendExceptionTestFixture.h/.m`

**R**
- `PHBeforeSendExceptionTestFixture`
- `makeThrowingBox:`
- `invokeWithoutException:`
- `setBeforeSendBlocks:onConfig:`

Necessary to exercise Objective-C exceptions and block/KVC bridging that Swift `throw` cannot simulate. Scoped consumer: `PostHogLogsCaptureTest.swift:354–364`; additional SDK-test consumers were found outside this root-file range.

#### `PostHogTestsObjC/PHNotificationDelegateTestFixture.h/.m`

**R**
- `PHNotificationDelegateTestFixture`
- `invokeWithCompletionHandler:`
- `PH_IMPLEMENT_NOTIFICATION_RESPONSE`
- `PHDirectNotificationDelegateTestFixture`
- `PHDuplicateNotificationDelegateTestFixture`
- `PHInheritedNotificationDelegateBaseTestFixture`
- `PHInheritedNotificationDelegateTestFixture`
- `PHSuperclassFirstNotificationDelegateBaseTestFixture`
- `PHSuperclassFirstNotificationDelegateTestFixture`
- `PHMissingNotificationDelegateTestFixture`

The direct, duplicate, inherited, superclass-first, and missing-method shapes are distinct Objective-C dispatch/swizzling fixtures. Preserve selector and completion-handler observation. Full downstream notification-suite behavior is outside this assignment; no deletion inference is drawn.

## CI and execution disposition

- `make test` runs the package suite with `--no-parallel` and `-DTESTING` (`Makefile:189–190`). It also invokes the upload-symbol test prerequisite.
- The macOS workflow uses macOS 15 and latest-stable Xcode; markdown-only changes skip substantive test steps.
- macOS compilation excludes iOS-only declarations.
- `make testOniOSSimulator` uses Xcode’s test scheme and up to three attempts (`Makefile:99–106`). The scheme marks the test target nonparallel.
- This does not neutralize asynchronous callbacks within one test or justify unsynchronized shared request arrays.
- Retry results are currently weakened by A1.
- A2 identifies scoped files missing from the simulator target.
- No scoped watchOS/tvOS/visionOS test execution was established. Build support is not equivalent to executing these tests.
- The compliance workflow is additional contract coverage, not proof that scoped unit tests were discovered. Its PR path/fork restrictions further prevent treating it as universal coverage.

## Preservation and validation handoff

No tests, assertions, fixtures, or production seams were removed. No snapshot was regenerated.

Recommended repair batches:
1. Fix fail-open result classification and simulator discovery.
2. Repair shared server synchronization, parsing, and fixture teardown.
3. Strengthen endpoint/header/log/flag oracles without changing product policy.
4. Repair exception and crash fixtures.
5. Resolve baseline failures and the two explicitly deferred spec-policy questions separately.

Suggested supervisor-run validation, **not executed here**:
- `make test filter=PostHogApiTest`
- `make test filter=PostHogLogs`
- `make test filter=PostHogFileBackedQueue`
- `make test filter=PostHogFeatureFlags`
- `make test filter=PostHogDeviceBucketingTests`
- `make test filter=PostHogIdentityTests`
- `make test`
- `make testOniOSSimulator`
- `make build`
- `make lint`

Use the controlled defects described above in an isolated authorized checkout, then restore them and verify the clean candidate passes. Shared-support repairs require consumers outside this reviewer’s bounded root-file range.

### Residual risks

- No independent test execution or mutation result; R decisions are source-based.
- Baseline device-bucketing and privacy failure diagnoses remain unresolved here.
- No verified evidence attributes the privacy failure to leaked rage-click ownership.
- Parent-owned edits began during the audit; the checkpoint patch and final combined state were not reviewed.
- XCTest-to-Swift-Testing failure attribution remains unverified.
- Actual simulator discovery and retry outcomes require structured execution evidence.
- Canonical spec revision and historical failure reproductions were not independently pinned.
- Downstream consumers outside the named scope were searched where relevant, not exhaustively behavior-audited.