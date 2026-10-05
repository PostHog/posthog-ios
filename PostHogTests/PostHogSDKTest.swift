//
//  PostHogSDKTest.swift
//  PostHogTests
//
//  Created by Manoel Aranda Neto on 31.10.23.
//

import Foundation
@_spi(PostHogInternal) @testable import PostHog
#if SWIFT_PACKAGE
    import PostHogTestsObjC
#endif
import Testing
import XCTest

/// Per-test environment shared by every suite in this file: a fresh mock server, wiped storage and
/// defaults, and the mock app lifecycle publisher. Every SDK created through `getSut`/`track` is
/// closed on teardown.
private final class SDKTestFixture {
    // Every SDK getSut creates is tracked and closed on teardown. An unclosed SDK leaks its
    // queues, timers, URLSession and observers; across ~40 instances per run those pile up and
    // starve the background thread pool, stalling async work (flag loads, flushes) on CI.
    private var trackedSuts: [PostHogSDK] = []
    var server: MockPostHogServer!
    let mockAppLifecycle = MockApplicationLifecyclePublisher()

    init() {
        PostHogAppLifeCycleIntegration.clearInstalls()

        Self.deleteDefaults()
        server = MockPostHogServer(version: 4)
        server.start()

        DI.main.appLifecyclePublisher = mockAppLifecycle
    }

    deinit {
        // Close every SDK created this test so its queues/timers/observers don't leak into the
        // next one (close() is idempotent, so tests that already closed their sut are fine).
        trackedSuts.forEach { $0.close() }
        trackedSuts.removeAll()
        server?.stop()
        server = nil
    }

    private static func deleteDefaults() {
        let userDefaults = UserDefaults.standard
        userDefaults.removeObject(forKey: "PHGVersionKey")
        userDefaults.removeObject(forKey: "PHGBuildKeyV2")
        userDefaults.synchronize()

        deleteSafely(applicationSupportDirectoryURL())
    }

    func track(_ sut: PostHogSDK) {
        trackedSuts.append(sut)
    }

    func getSut(preloadFeatureFlags: Bool = false,
                sendFeatureFlagEvent: Bool = false,
                captureApplicationLifecycleEvents: Bool = false,
                flushAt: Int = 1,
                optOut: Bool = false,
                personProfiles: PostHogPersonProfiles = .identifiedOnly,
                setDefaultPersonProperties: Bool = true,
                beforeSend: [BeforeSendBlock]? = nil) -> PostHogSDK
    {
        let config = PostHogConfig(projectToken: testProjectToken, host: "http://localhost:9001")
        config.flushAt = flushAt
        config.preloadFeatureFlags = preloadFeatureFlags
        config.sendFeatureFlagEvent = sendFeatureFlagEvent
        config.disableReachabilityForTesting = true
        config.disableQueueTimerForTesting = true
        config.disableFlushOnBackgroundForTesting = true
        config.captureApplicationLifecycleEvents = captureApplicationLifecycleEvents
        config.optOut = optOut
        config.personProfiles = personProfiles
        config.setDefaultPersonProperties = setDefaultPersonProperties

        if let beforeSend = beforeSend {
            config.setBeforeSend(beforeSend)
        }

        let storage = PostHogStorage(config)
        storage.reset()

        let sut = PostHogSDK.with(config)
        track(sut)
        return sut
    }
}

/// `$app_version`/`$app_build` are read from `Bundle.main`'s Info.plist. Under XCTest (Xcode, or the
/// `xctest` runner `swift test` uses for XCTest) the host bundle has them; under `swift test`'s Swift
/// Testing runner (`swiftpm-testing-helper`) `Bundle.main` has no version keys, so the SDK omits them.
/// Assert against what the host actually provides rather than assuming an XCTest host.
private func hostAppInfoHas(_ key: String) -> Bool {
    Bundle.main.infoDictionary?[key] != nil
}

/// The app-version key the minimal `$feature_flag_called` allowlist keeps, when the host provides it.
private var hostAppVersionKeys: Set<String> {
    hostAppInfoHas("CFBundleShortVersionString") ? ["$app_version"] : []
}

@Suite("PostHogSDK", .serialized, .resetsGlobalState)
final class PostHogSDKTests {
    private let fixture = SDKTestFixture()

    private var server: MockPostHogServer {
        fixture.server
    }

    private var mockAppLifecycle: MockApplicationLifecyclePublisher {
        fixture.mockAppLifecycle
    }

    private func getSut(preloadFeatureFlags: Bool = false,
                        sendFeatureFlagEvent: Bool = false,
                        captureApplicationLifecycleEvents: Bool = false,
                        flushAt: Int = 1,
                        optOut: Bool = false) -> PostHogSDK
    {
        fixture.getSut(preloadFeatureFlags: preloadFeatureFlags,
                       sendFeatureFlagEvent: sendFeatureFlagEvent,
                       captureApplicationLifecycleEvents: captureApplicationLifecycleEvents,
                       flushAt: flushAt,
                       optOut: optOut)
    }

    private func bootstrapReconcileConfig(existing: (anon: String, distinct: String?, identified: Bool)) -> PostHogConfig {
        let config = PostHogConfig(projectToken: testProjectToken, host: "http://localhost:9001")
        config.disableReachabilityForTesting = true
        config.disableQueueTimerForTesting = true
        config.disableFlushOnBackgroundForTesting = true

        let storage = PostHogStorage(config)
        storage.reset()
        storage.setString(forKey: .anonymousId, contents: existing.anon)
        if let distinct = existing.distinct {
            storage.setString(forKey: .distinctId, contents: distinct)
        }
        if existing.identified {
            storage.setBool(forKey: .isIdentified, contents: true)
        }
        return config
    }

    @Test("no-ops setup when project token is empty after trimming")
    func noOpsSetupWhenProjectTokenIsEmpty() {
        let config = PostHogConfig(projectToken: " \n\t ", host: "http://localhost:9001")

        let sut = PostHogSDK.with(config)

        #expect(sut.config.projectToken.isEmpty)
        #expect(sut.storage == nil)
        #expect(sut.getDistinctId().isEmpty)
        #expect(sut.getSessionId() == nil)
    }

    @Test("merges an anonymous local user into an identified bootstrap")
    func mergesAnonymousUserIntoIdentifiedBootstrap() {
        let config = bootstrapReconcileConfig(existing: (anon: "anon-abc", distinct: nil, identified: false))
        config.bootstrap = PostHogBootstrapConfig(distinctId: "user-123", isIdentifiedId: true)

        let sut = PostHogSDK.with(config)
        fixture.track(sut)

        // the anonymous user is merged into the identified bootstrap ID
        #expect(sut.getDistinctId() == "user-123")
        #expect(config.storageManager?.isIdentified() == true)
        // the anonymous ID is preserved so the $identify links the merge ($anon_distinct_id)
        #expect(sut.getAnonymousId() == "anon-abc")
    }

    @Test("preserves a different already-identified local user against an identified bootstrap")
    func preservesDifferentIdentifiedUserAgainstBootstrap() {
        let config = bootstrapReconcileConfig(existing: (anon: "anon-xyz", distinct: "user-existing", identified: true))
        config.bootstrap = PostHogBootstrapConfig(distinctId: "user-123", isIdentifiedId: true)

        let sut = PostHogSDK.with(config)
        fixture.track(sut)

        // the existing identity wins; the bootstrap is ignored
        #expect(sut.getDistinctId() == "user-existing")
        #expect(config.storageManager?.isIdentified() == true)
    }

    @Test("upgrades a matching anonymous id to identified via an identified bootstrap")
    func upgradesMatchingAnonymousIdViaBootstrap() {
        let config = bootstrapReconcileConfig(existing: (anon: "user-123", distinct: nil, identified: false))
        config.bootstrap = PostHogBootstrapConfig(distinctId: "user-123", isIdentifiedId: true)

        let sut = PostHogSDK.with(config)
        fixture.track(sut)

        // matching id: the user is upgraded to identified without re-linking
        #expect(sut.getDistinctId() == "user-123")
        #expect(config.storageManager?.isIdentified() == true)
    }

    @Test("reconciles an identified bootstrap while opted out")
    func reconcilesIdentifiedBootstrapWhileOptedOut() {
        let config = bootstrapReconcileConfig(existing: (anon: "anon-xyz", distinct: nil, identified: false))
        config.optOut = true
        config.bootstrap = PostHogBootstrapConfig(distinctId: "user-456", isIdentifiedId: true)

        let sut = PostHogSDK.with(config)
        fixture.track(sut)

        // opted out: local identity is still reconciled, only event emission is suppressed
        #expect(sut.getDistinctId() == "user-456")
        #expect(config.storageManager?.isIdentified() == true)
    }

    @Test("early lifecycle events carry the reconciled bootstrap identity")
    func earlyLifecycleEventsCarryReconciledIdentity() {
        let config = bootstrapReconcileConfig(existing: (anon: "anon-abc", distinct: nil, identified: false))
        config.captureApplicationLifecycleEvents = true
        // reconcile emits $identify, then Application Installed captures on install; flush both together
        config.flushAt = 2
        config.bootstrap = PostHogBootstrapConfig(distinctId: "user-123", isIdentifiedId: true)

        let sut = PostHogSDK.with(config)
        fixture.track(sut)

        // reconcile runs before installIntegrations, so the Application Installed event captured
        // synchronously on install carries the merged bootstrap identity, not the old anonymous id
        let events = getBatchedEvents(server)
        let installed = events.first { $0.event == "Application Installed" }
        #expect(installed != nil)
        #expect(installed?.distinctId == "user-123")
    }

    // The .never asymmetry below is intentional posthog-js parity: the fresh-install seed applies the
    // identity via an ungated write, while the returning-anon path routes through identify(), which
    // no-ops under .never. These lock in that behavior so it isn't "made consistent" by mistake.
    @Test("applies an identified bootstrap on a fresh install even when personProfiles is never")
    func appliesIdentifiedBootstrapOnFreshInstallWhenPersonProfilesNever() {
        let config = PostHogConfig(projectToken: testProjectToken, host: "http://localhost:9001")
        config.disableReachabilityForTesting = true
        config.disableQueueTimerForTesting = true
        config.disableFlushOnBackgroundForTesting = true
        config.personProfiles = .never
        PostHogStorage(config).reset() // fresh install: no persisted identity
        config.bootstrap = PostHogBootstrapConfig(distinctId: "user-123", isIdentifiedId: true)

        let sut = PostHogSDK.with(config)
        fixture.track(sut)

        // fresh-install seed applies the identity directly, without the person-processing gate
        #expect(sut.getDistinctId() == "user-123")
        #expect(config.storageManager?.isIdentified() == true)
    }

    @Test("drops a differing identified bootstrap for a returning anonymous user when personProfiles is never")
    func dropsDifferingBootstrapForReturningAnonWhenPersonProfilesNever() {
        let config = bootstrapReconcileConfig(existing: (anon: "anon-abc", distinct: nil, identified: false))
        config.personProfiles = .never
        config.bootstrap = PostHogBootstrapConfig(distinctId: "user-123", isIdentifiedId: true)

        let sut = PostHogSDK.with(config)
        fixture.track(sut)

        // returning-anon path routes through identify(), which no-ops under .never, so the bootstrap
        // identity is dropped and the existing anonymous id is preserved
        #expect(sut.getDistinctId() == "anon-abc")
        #expect(config.storageManager?.isIdentified() == false)
    }

    @Test("drops a differing identified bootstrap for a returning anonymous user when personProfiles is never and opted out")
    func dropsDifferingBootstrapForReturningAnonWhenPersonProfilesNeverAndOptedOut() {
        let config = bootstrapReconcileConfig(existing: (anon: "anon-abc", distinct: nil, identified: false))
        config.personProfiles = .never
        config.optOut = true
        config.bootstrap = PostHogBootstrapConfig(distinctId: "user-456", isIdentifiedId: true)

        let sut = PostHogSDK.with(config)
        fixture.track(sut)

        // .never gates the reconcile regardless of opt-out, so the outcome matches the non-opted-out case above
        #expect(sut.getDistinctId() == "anon-abc")
        #expect(config.storageManager?.isIdentified() == false)
    }

    @Test("identifies an anonymous user via identify() when the id already matches the persisted distinct id")
    func identifiesAnonymousUserWhenIdMatchesPersistedDistinctId() {
        // Anonymous user whose persisted id already equals the id being identified with
        // (e.g. a non-identified bootstrap seeded the same id).
        let config = bootstrapReconcileConfig(existing: (anon: "user-123", distinct: nil, identified: false))
        config.captureApplicationLifecycleEvents = false
        config.flushAt = 1

        let sut = PostHogSDK.with(config)
        fixture.track(sut)

        sut.identify("user-123")

        // No $identify (nothing to merge); a single person-processed $set marks the transition.
        let events = getBatchedEvents(server)
        #expect(events.count == 1)
        #expect(events.first?.event == "$set")
        #expect(events.first?.properties["$process_person_profile"] as? Bool == true)
        #expect(config.storageManager?.isIdentified() == true)
    }

    @Test("does not emit a second $set on a repeated matching-id identify")
    func doesNotEmitSecondSetOnRepeatedMatchingIdIdentify() throws {
        let config = bootstrapReconcileConfig(existing: (anon: "user-123", distinct: nil, identified: false))
        config.captureApplicationLifecycleEvents = false
        config.flushAt = 2

        let sut = PostHogSDK.with(config)
        fixture.track(sut)

        sut.identify("user-123") // transition: one $set
        sut.identify("user-123") // already identified: no event
        sut.capture("event") // flushes the batch (flushAt 2)

        let events = getBatchedEvents(server)
        try #require(events.count == 2)
        #expect(events[0].event == "$set")
        #expect(events[1].event == "event")
    }

    @Test("forwards userProperties and userPropertiesSetOnce on a matching-id identify")
    func forwardsUserPropertiesOnMatchingIdIdentify() throws {
        let config = bootstrapReconcileConfig(existing: (anon: "user-123", distinct: nil, identified: false))
        config.captureApplicationLifecycleEvents = false
        config.flushAt = 1

        let sut = PostHogSDK.with(config)
        fixture.track(sut)

        sut.identify("user-123", userProperties: ["foo": "bar"], userPropertiesSetOnce: ["baz": "qux"])

        let events = getBatchedEvents(server)
        #expect(events.count == 1)

        let event = try #require(events.first)
        #expect(event.event == "$set")
        #expect(event.properties["$process_person_profile"] as? Bool == true)

        let set = event.properties["$set"] as? [String: Any] ?? [:]
        #expect(set["foo"] as? String == "bar")

        let setOnce = event.properties["$set_once"] as? [String: Any] ?? [:]
        #expect(setOnce["baz"] as? String == "qux")

        #expect(config.storageManager?.isIdentified() == true)
    }

    @Test("captures the capture event")
    func capturesTheCaptureEvent() throws {
        let sut = getSut()

        sut.capture("test event",
                    properties: ["foo": "bar"],
                    userProperties: ["userProp": "value"],
                    userPropertiesSetOnce: ["userPropOnce": "value"],
                    groups: ["groupProp": "value"])

        let events = getBatchedEvents(server)

        #expect(events.count == 1)

        let event = try #require(events.first)
        #expect(event.event == "test event")

        #expect(event.properties["foo"] as? String == "bar")

        let set = event.properties["$set"] as? [String: Any] ?? [:]
        #expect(set["userProp"] as? String == "value")

        let setOnce = event.properties["$set_once"] as? [String: Any] ?? [:]
        #expect(setOnce["userPropOnce"] as? String == "value")

        let groupProps = event.properties["$groups"] as? [String: String] ?? [:]
        #expect(groupProps["groupProp"] == "value")

        sut.reset()
        sut.close()
    }

    #if os(iOS)
        #if !SWIFT_PACKAGE || SessionReplay
            @Test("captures $recording_status on every event and the full replay debug bundle on the first eligible SDK event only")
            func capturesRecordingStatusAndReplayDebugBundle() throws {
                server.reset(batchCount: 1)
                let sut = getSut(flushAt: 3)

                sut.capture("test event")
                sut.screen("theScreen")
                sut.capture("$exception", properties: ["foo": "bar"])

                let events = getBatchedEvents(server)
                try #require(events.count == 3)

                #expect(events[0].properties["$recording_status"] as? String == "disabled")
                #expect(events[0].properties["$sdk_debug_session_start"] == nil)
                #expect(events[0].properties["$sdk_debug_replay_capture_mode"] == nil)

                #expect(events[1].properties["$recording_status"] as? String == "disabled")
                #expect(events[1].properties["$sdk_debug_replay_capture_mode"] as? String == "screenshot")
                #expect(events[1].properties["$sdk_debug_session_start"] != nil)

                // Inside the 30s window opened by $screen.
                #expect(events[2].properties["$recording_status"] as? String == "disabled")
                #expect(events[2].properties["$sdk_debug_session_start"] == nil)
                #expect(events[2].properties["$sdk_debug_replay_capture_mode"] == nil)

                for event in events {
                    #expect(event.properties["$sdk_debug_pending_queue_size"] != nil)
                }

                sut.reset()
                sut.close()
            }
        #endif

        @Test("excludes $recording_status and $sdk_debug_* properties from $snapshot events")
        func excludesRecordingStatusAndDebugPropertiesFromSnapshotEvents() throws {
            // $snapshot events route to the replay queue and the /s/ endpoint, not /batch —
            // read the raw request body rather than getBatchedEvents.
            server.reset(batchCount: 0, snapshotCount: 1)
            let sut = getSut()
            sut.sessionManager.setSessionId("00000000-0000-7000-8000-000000000099")

            sut.capture("$snapshot", properties: [
                "$session_id": "00000000-0000-7000-8000-000000000099",
                "$snapshot_source": "mobile",
                "$snapshot_data": ["type": 4, "data": ["width": 1, "height": 1], "timestamp": 0] as [String: Any],
            ])
            sut.flush()

            let result = XCTWaiter.wait(for: [server.snapshotExpectation!], timeout: testRequestTimeout)
            #expect(result == .completed)

            let request = try #require(server.snapshotRequests.first)
            let data = try #require(request.body()).gunzipped()
            let events = try #require(JSONSerialization.jsonObject(with: data) as? [[String: Any]])
            #expect(events.count == 1)
            let event = try #require(events.first)
            #expect(event["event"] as? String == "$snapshot")
            let props = try #require(event["properties"] as? [String: Any])
            #expect(props["$session_id"] as? String == "00000000-0000-7000-8000-000000000099")
            #expect(props["$snapshot_source"] as? String == "mobile")

            #expect(props["$recording_status"] == nil)
            #expect(!props.keys.contains { $0.hasPrefix("$sdk_debug_") })

            sut.reset()
            sut.close()
        }

        @Test("SDK-computed debug keys win over a same-named registered super property")
        func sdkComputedDebugKeysWinOverRegisteredSuperProperty() throws {
            server.reset(batchCount: 1)
            let sut = getSut()
            sut.register(["$recording_status": "bogus", "$sdk_debug_pending_queue_size": -1])

            sut.capture("test event")

            let events = getBatchedEvents(server)
            let props = try #require(events.first).properties
            #expect(props["$recording_status"] as? String == "disabled")
            let pendingQueueSize = try #require(props["$sdk_debug_pending_queue_size"] as? Int)
            #expect(pendingQueueSize != -1)

            sut.reset()
            sut.close()
        }

    #else
        @Test("reports disabled recording status with no replay keys on non-iOS platforms")
        func reportsDisabledRecordingStatusOnNonIOSPlatforms() throws {
            server.reset(batchCount: 1)
            let sut = getSut()

            sut.capture("test event")

            let events = getBatchedEvents(server)
            #expect(events.count == 1)

            let props = try #require(events.first).properties
            #expect(props["$recording_status"] as? String == "disabled")
            #expect(!props.keys.contains { $0.hasPrefix("$sdk_debug_replay_") })
            #expect(props["$sdk_debug_pending_queue_size"] != nil)

            sut.reset()
            sut.close()
        }
    #endif

    @Test("invokes reloadFeatureFlags callback when not enabled")
    func invokesReloadFeatureFlagsCallbackWhenNotEnabled() {
        let sut = getSut()
        sut.close()

        var result: PostHogFeatureFlagsLoaded?
        sut.reloadFeatureFlags { result = $0 }

        #expect(result?.errorsLoading == true)
        #expect(result?.flags.isEmpty == true)
    }

    @Test("captures a screen event")
    func capturesAScreenEvent() throws {
        let sut = getSut()

        sut.screen("theScreen", properties: ["prop": "value"])

        let events = getBatchedEvents(server)

        #expect(events.count == 1)

        let event = try #require(events.first)
        #expect(event.event == "$screen")

        #expect(event.properties["$screen_name"] as? String == "theScreen")
        #expect(event.properties["prop"] as? String == "value")

        sut.reset()
        sut.close()
    }

    @Test("captures a group event")
    func capturesAGroupEvent() throws {
        let sut = getSut()

        sut.group(type: "some-type", key: "some-key", groupProperties: [
            "name": "some-company-name",
        ])

        let events = getBatchedEvents(server)

        #expect(events.count == 1)

        let groupEvent = try #require(events.first)
        #expect(groupEvent.event == "$groupidentify")
        #expect(groupEvent.properties["$group_type"] as? String == "some-type")
        #expect(groupEvent.properties["$group_key"] as? String == "some-key")
        #expect((groupEvent.properties["$group_set"] as? [String: Any])?["name"] as? String == "some-company-name")

        sut.reset()
        sut.close()
    }

    @Test("setups optOut")
    func setupsOptOut() {
        let sut = getSut()

        sut.optOut()

        #expect(sut.isOptOut() == true)

        sut.optIn()

        #expect(sut.isOptOut() == false)

        sut.reset()
        sut.close()
    }

    @Test("sets opt out via config")
    func setsOptOutViaConfig() {
        let sut = getSut(optOut: true)

        #expect(sut.isOptOut() == true)

        sut.reset()
        sut.close()
    }

    @Test("removes all integrations on opt-out")
    func removesAllIntegrationsOnOptOut() {
        let sut = getSut(
            captureApplicationLifecycleEvents: true,
            optOut: false
        )

        #expect(sut.getAppLifeCycleIntegration() != nil)
        // Setup captures `Application Installed`; drain it so the upload can't land on the next test's server.
        _ = getBatchedEvents(server)

        sut.optOut()

        #expect(sut.getAppLifeCycleIntegration() == nil)

        sut.reset()
        sut.close()
    }

    @Test("does not capture event if opt out")
    func doesNotCaptureEventIfOptOut() {
        let sut = getSut()

        sut.optOut()

        sut.capture("event")

        // no need to await 15s
        let events = getBatchedEvents(server, timeout: 1.0, failIfNotCompleted: false)
        #expect(events.count == 0)

        sut.reset()
        sut.close()
    }

    @Test("calls reloadFeatureFlags")
    func callsReloadFeatureFlags() {
        let sut = getSut()

        let group = DispatchGroup()
        group.enter()

        sut.reloadFeatureFlags { _ in
            group.leave()
        }

        group.wait()

        #expect(sut.isFeatureEnabled("bool-value") == true)

        sut.reset()
        sut.close()
    }

    @Test("loads feature flags automatically")
    func loadsFeatureFlagsAutomatically() {
        let sut = getSut(preloadFeatureFlags: true)

        waitForFeatureFlagsLoaded(server, sut)
        #expect(sut.isFeatureEnabled("bool-value") == true)

        sut.reset()
        sut.close()
    }

    @Test("send feature flag event for isFeatureEnabled when enabled")
    func sendFeatureFlagEventForIsFeatureEnabled() throws {
        let sut = getSut(preloadFeatureFlags: true, sendFeatureFlagEvent: true)

        waitForFeatureFlagsLoaded(server, sut)
        #expect(sut.isFeatureEnabled("bool-value") == true)

        let events = getBatchedEvents(server)

        #expect(events.count == 1)

        let event = try #require(events.first)
        #expect(event.event == "$feature_flag_called")
        #expect(event.properties["$feature_flag"] as? String == "bool-value")
        #expect(event.properties["$feature_flag_response"] as? Bool == true)
        #expect(event.properties["$feature_flag_request_id"] as? String == "0f801b5b-0776-42ca-b0f7-8375c95730bf")
        #expect(event.properties["$feature_flag_id"] as? Int == 2)
        #expect(event.properties["$feature_flag_version"] as? Int == 23)
        #expect(event.properties["$feature_flag_reason"] as? String == "Matched condition set 3")
        #expect(event.properties["$feature_flag_has_experiment"] as? Bool == true)

        // $feature_flag_called gets the required keys but never the optional ones.
        #expect(event.properties["$recording_status"] as? String == "disabled")
        #expect(event.properties["$sdk_debug_session_start"] == nil)
        #expect(event.properties["$sdk_debug_pending_queue_size"] != nil)

        sut.reset()
        sut.close()
    }

    @Test("send feature flag event with variant response for isFeatureEnabled when enabled")
    func sendFeatureFlagEventWithVariantResponse() throws {
        let sut = getSut(preloadFeatureFlags: true, sendFeatureFlagEvent: true)

        waitForFeatureFlagsLoaded(server, sut)
        #expect(sut.isFeatureEnabled("string-value") == true)

        let events = getBatchedEvents(server)

        #expect(events.count == 1)

        let event = try #require(events.first)
        #expect(event.event == "$feature_flag_called")
        #expect(event.properties["$feature_flag"] as? String == "string-value")
        #expect(event.properties["$feature_flag_response"] as? String == "test")
        #expect(event.properties["$feature_flag_request_id"] as? String == "0f801b5b-0776-42ca-b0f7-8375c95730bf")
        #expect(event.properties["$feature_flag_id"] as? Int == 3)
        #expect(event.properties["$feature_flag_version"] as? Int == 1)
        #expect(event.properties["$feature_flag_reason"] as? String == "Matched condition set 1")
        #expect(event.properties["$feature_flag_has_experiment"] as? Bool == false)

        sut.reset()
        sut.close()
    }

    @Test("send feature flag event without has_experiment when server omits it")
    func sendFeatureFlagEventWithoutHasExperiment() throws {
        let sut = getSut(preloadFeatureFlags: true, sendFeatureFlagEvent: true)

        waitForFeatureFlagsLoaded(server, sut)
        #expect(sut.isFeatureEnabled("number-value") == true)

        let events = getBatchedEvents(server)

        #expect(events.count == 1)

        let event = try #require(events.first)
        #expect(event.event == "$feature_flag_called")
        #expect(event.properties["$feature_flag"] as? String == "number-value")
        #expect(event.properties["$feature_flag_has_experiment"] == nil)

        sut.reset()
        sut.close()
    }

    @Test("sends minimal feature flag event when gated and flag has no experiment")
    func sendsMinimalFeatureFlagEventWhenGated() throws {
        server.minimalFlagCalledEvents = true
        let sut = getSut(preloadFeatureFlags: true, sendFeatureFlagEvent: true)

        waitForFeatureFlagsLoaded(server, sut)
        #expect(sut.isFeatureEnabled("string-value") == true)

        let events = getBatchedEvents(server)

        #expect(events.count == 1)

        let event = try #require(events.first)
        #expect(event.event == "$feature_flag_called")
        // Strict allowlist: everything else (super properties, $active_feature_flags,
        // $feature/<key>, $is_identified) is stripped; $os_name/$os_version/$app_version
        // survive as mobile's OS- and app-version-breakdown analog.
        #expect(Set(event.properties.keys) == Set([
            "$feature_flag",
            "$feature_flag_response",
            "$feature_flag_has_experiment",
            "$feature_flag_id",
            "$feature_flag_version",
            "$feature_flag_reason",
            "$feature_flag_request_id",
            "$feature_flag_evaluated_at",
            "$process_person_profile",
            "$session_id",
            "$lib",
            "$lib_version",
            "$os_name",
            "$os_version",
        ]).union(hostAppVersionKeys))
        #expect(event.properties["$feature_flag"] as? String == "string-value")
        #expect(event.properties["$feature_flag_response"] as? String == "test")
        #expect(event.properties["$feature_flag_has_experiment"] as? Bool == false)
        // Not on the allowlist, so the minimal shape must never carry the replay debug envelope.
        #expect(event.properties["$recording_status"] == nil)
        #expect(!event.properties.keys.contains { $0.hasPrefix("$sdk_debug_") })

        sut.reset()
        sut.close()
    }

    @Test("keeps $groups on minimal feature flag events")
    func keepsGroupsOnMinimalFeatureFlagEvents() throws {
        server.minimalFlagCalledEvents = true
        // flushAt 2 so the $groupidentify and $feature_flag_called events share one batch
        let sut = getSut(preloadFeatureFlags: true, sendFeatureFlagEvent: true, flushAt: 2)

        waitForFeatureFlagsLoaded(server, sut)

        sut.group(type: "some-type", key: "some-key")

        #expect(sut.isFeatureEnabled("string-value") == true)

        let events = getBatchedEvents(server)

        #expect(events.count == 2)

        let event = try #require(events.last)
        #expect(event.event == "$feature_flag_called")
        // $groups is correctness-required (ingestion dedup key + personful routing for group
        // flags), so it must survive minimization when groups are registered.
        #expect(Set(event.properties.keys) == Set([
            "$feature_flag",
            "$feature_flag_response",
            "$feature_flag_has_experiment",
            "$feature_flag_id",
            "$feature_flag_version",
            "$feature_flag_reason",
            "$feature_flag_request_id",
            "$feature_flag_evaluated_at",
            "$groups",
            "$process_person_profile",
            "$session_id",
            "$lib",
            "$lib_version",
            "$os_name",
            "$os_version",
        ]).union(hostAppVersionKeys))
        let groups = event.properties["$groups"] as? [String: String]
        #expect(groups?["some-type"] == "some-key")

        sut.reset()
        sut.close()
    }

    @Test("sends full feature flag event when gated but flag has an experiment")
    func sendsFullFeatureFlagEventWhenFlagHasExperiment() throws {
        server.minimalFlagCalledEvents = true
        let sut = getSut(preloadFeatureFlags: true, sendFeatureFlagEvent: true)

        waitForFeatureFlagsLoaded(server, sut)
        #expect(sut.isFeatureEnabled("bool-value") == true)

        let events = getBatchedEvents(server)

        #expect(events.count == 1)

        let event = try #require(events.first)
        #expect(event.event == "$feature_flag_called")
        #expect(event.properties["$feature_flag_has_experiment"] as? Bool == true)
        #expect(event.properties["$feature/bool-value"] as? Bool == true)
        #expect(event.properties["$active_feature_flags"] != nil)
        #expect(event.properties["$is_identified"] != nil)
        #expect(event.properties["$recording_status"] as? String == "disabled")

        sut.reset()
        sut.close()
    }

    @Test("sends full feature flag event when gated but has_experiment is unknown")
    func sendsFullFeatureFlagEventWhenHasExperimentUnknown() throws {
        server.minimalFlagCalledEvents = true
        let sut = getSut(preloadFeatureFlags: true, sendFeatureFlagEvent: true)

        waitForFeatureFlagsLoaded(server, sut)
        #expect(sut.isFeatureEnabled("number-value") == true)

        let events = getBatchedEvents(server)

        #expect(events.count == 1)

        let event = try #require(events.first)
        #expect(event.event == "$feature_flag_called")
        #expect(event.properties["$feature_flag_has_experiment"] == nil)
        #expect(event.properties["$active_feature_flags"] != nil)

        sut.reset()
        sut.close()
    }

    @Test("sends full feature flag event when the server does not gate minimal events")
    func sendsFullFeatureFlagEventWhenServerDoesNotGate() throws {
        let sut = getSut(preloadFeatureFlags: true, sendFeatureFlagEvent: true)

        waitForFeatureFlagsLoaded(server, sut)
        #expect(sut.isFeatureEnabled("string-value") == true)

        let events = getBatchedEvents(server)

        #expect(events.count == 1)

        let event = try #require(events.first)
        #expect(event.event == "$feature_flag_called")
        #expect(event.properties["$feature_flag_has_experiment"] as? Bool == false)
        #expect(event.properties["$feature/string-value"] as? String == "test")
        #expect(event.properties["$active_feature_flags"] != nil)

        sut.reset()
        sut.close()
    }

    @Test("send feature flag event for getFeatureFlag when enabled")
    func sendFeatureFlagEventForGetFeatureFlag() throws {
        let sut = getSut(preloadFeatureFlags: true, sendFeatureFlagEvent: true)

        waitForFeatureFlagsLoaded(server, sut)
        #expect(sut.getFeatureFlag("bool-value") as? Bool == true)

        let events = getBatchedEvents(server)

        #expect(events.count == 1)

        let event = try #require(events.first)
        #expect(event.event == "$feature_flag_called")
        #expect(event.properties["$feature_flag"] as? String == "bool-value")
        #expect(event.properties["$feature_flag_response"] as? Bool == true)

        sut.reset()
        sut.close()
    }

    @Test("force send feature flag event for getFeatureFlag when config disabled")
    func forceSendFeatureFlagEventWhenConfigDisabled() throws {
        let sut = getSut(preloadFeatureFlags: true, sendFeatureFlagEvent: false)

        waitForFeatureFlagsLoaded(server, sut)
        #expect(sut.getFeatureFlag("bool-value", sendFeatureFlagEvent: true) as? Bool == true)

        let events = getBatchedEvents(server)

        #expect(events.count == 1)

        let event = try #require(events.first)
        #expect(event.event == "$feature_flag_called")
        #expect(event.properties["$feature_flag"] as? String == "bool-value")
        #expect(event.properties["$feature_flag_response"] as? Bool == true)

        sut.reset()
        sut.close()
    }

    @Test("don't send feature flag event for getFeatureFlag when config enabled")
    func dontSendFeatureFlagEventWhenOverriddenOff() {
        let sut = getSut(preloadFeatureFlags: true, sendFeatureFlagEvent: true)

        waitForFeatureFlagsLoaded(server, sut)
        #expect(sut.getFeatureFlag("bool-value", sendFeatureFlagEvent: false) as? Bool == true)

        let events = getBatchedEvents(server, failIfNotCompleted: false)

        #expect(events.count == 0)

        sut.reset()
        sut.close()
    }

    @Test("reloadFeatureFlags adds groups if any")
    func reloadFeatureFlagsAddsGroups() throws {
        let sut = getSut()
        // group reloads flags when there are new groups
        // but in this case we want to reload manually and assert the response
        sut.remoteConfig?.canReloadFlagsForTesting = false
        sut.group(type: "some-type", key: "some-key", groupProperties: [
            "name": "some-company-name",
        ])
        sut.remoteConfig?.canReloadFlagsForTesting = true

        let events = getBatchedEvents(server)

        #expect(events.count == 1)

        sut.reloadFeatureFlags()

        let requests = getFlagsRequest(server)

        #expect(requests.count == 1)
        let request = try #require(requests.first)

        let groups = request["groups"] as? [String: String] ?? [:]
        #expect(groups["some-type"] == "some-key")

        sut.reset()
        sut.close()
    }

    @Test("merge groups when group is called")
    func mergeGroupsWhenGroupIsCalled() throws {
        let sut = getSut(flushAt: 3)

        sut.group(type: "some-type", key: "some-key")

        sut.group(type: "some-type-2", key: "some-key-2")

        sut.capture("event")

        let events = getBatchedEvents(server)

        #expect(events.count == 3)
        let event = try #require(events.last)

        let groups = try #require(event.properties["$groups"] as? [String: String])
        #expect(groups["some-type"] == "some-key")
        #expect(groups["some-type-2"] == "some-key-2")

        sut.reset()
        sut.close()
    }

    @Test("register and unregister properties")
    func registerAndUnregisterProperties() throws {
        let sut = getSut(flushAt: 1)

        sut.register(["test1": "test"])
        sut.register(["test2": "test"])
        sut.unregister("test2")
        sut.register(["test3": "test"])

        sut.capture("event")

        let events = getBatchedEvents(server)

        #expect(events.count == 1)
        let event = try #require(events.last)

        #expect(event.properties["test1"] as? String == "test")
        #expect(event.properties["test3"] as? String == "test")
        #expect(event.properties["test2"] as? String == nil)

        sut.reset()
        sut.close()
    }

    @Test("add active feature flags as part of the event")
    func addActiveFeatureFlagsToEvent() throws {
        let sut = getSut()

        sut.reloadFeatureFlags()
        waitForFeatureFlagsLoaded(server, sut)

        sut.capture("event")

        let events = getBatchedEvents(server)

        #expect(events.count == 1)
        let event = try #require(events.first)

        let activeFlags = event.properties["$active_feature_flags"] as? [Any] ?? []
        #expect(activeFlags.contains { $0 as? String == "bool-value" } == true)
        #expect(activeFlags.contains { $0 as? String == "disabled-flag" } == false)

        #expect(event.properties["$feature/bool-value"] as? Bool == true)
        #expect(event.properties["$feature/disabled-flag"] as? Bool == false)

        sut.reset()
        sut.close()
    }

    @Test("caller-supplied feature flag properties override cached values")
    func callerSuppliedFeatureFlagPropertiesOverrideCachedValues() throws {
        let sut = getSut()

        sut.reloadFeatureFlags()
        waitForFeatureFlagsLoaded(server, sut)

        sut.capture("event", properties: [
            "$feature/bool-value": "server-value",
            "$active_feature_flags": ["server-flag"],
        ])

        let events = getBatchedEvents(server)

        #expect(events.count == 1)
        let event = try #require(events.first)

        #expect(event.properties["$feature/bool-value"] as? String == "server-value")
        let activeFlags = event.properties["$active_feature_flags"] as? [Any] ?? []
        #expect(activeFlags.count == 1)
        #expect(activeFlags.first as? String == "server-flag")

        sut.reset()
        sut.close()
    }

    @Test("sanitize properties")
    func sanitizeProperties() throws {
        let sut = getSut(flushAt: 1)

        sut.register(["boolIsOk": true,
                      "test5": UserDefaults.standard])

        sut.capture("test event",
                    properties: ["foo": "bar",
                                 "test1": UserDefaults.standard,
                                 "arrayIsOk": [1, 2, 3],
                                 "dictIsOk": ["1": "one"]],
                    userProperties: ["userProp": "value",
                                     "test2": UserDefaults.standard],
                    userPropertiesSetOnce: ["userPropOnce": "value",
                                            "test3": UserDefaults.standard])

        let events = getBatchedEvents(server)

        #expect(events.count == 1)
        let event = try #require(events.first)

        #expect(event.properties["test1"] == nil)
        let set = try #require(event.properties["$set"] as? [String: Any])
        let setOnce = try #require(event.properties["$set_once"] as? [String: Any])
        #expect(set["userProp"] as? String == "value")
        #expect(setOnce["userPropOnce"] as? String == "value")
        #expect(set["test2"] == nil)
        #expect(setOnce["test3"] == nil)
        #expect(event.properties["test5"] == nil)
        #expect(event.properties["arrayIsOk"] != nil)
        #expect(event.properties["dictIsOk"] != nil)
        #expect(event.properties["boolIsOk"] != nil)

        sut.reset()
        sut.close()
    }

    @Test("sets sessionId on app start")
    func setsSessionIdOnAppStart() throws {
        let sut = getSut(captureApplicationLifecycleEvents: true, flushAt: 1)

        mockAppLifecycle.simulateAppDidFinishLaunching()

        let events = getBatchedEvents(server)

        #expect(events.count == 1)

        let event = try #require(events.first)
        #expect(event.properties["$session_id"] != nil)

        sut.reset()
        sut.close()
    }

    @Test("uses the same sessionId for all events in a session")
    func usesSameSessionIdForAllEventsInSession() throws {
        let sut = getSut(flushAt: 3)
        let mockNow = MockDate()
        now = { mockNow.date }

        sut.capture("event1")

        mockNow.date.addTimeInterval(10)

        sut.capture("event2")

        mockNow.date.addTimeInterval(10)

        sut.capture("event3")

        let events = getBatchedEvents(server)

        try #require(events.count == 3)

        let sessionId = events[0].properties["$session_id"] as? String
        #expect(sessionId != nil)
        #expect(events[1].properties["$session_id"] as? String == sessionId)
        #expect(events[2].properties["$session_id"] as? String == sessionId)

        sut.reset()
        sut.close()
    }

    @Test("clears sessionId for background events after 30 mins in background")
    func clearsSessionIdAfterThirtyMinutesInBackground() throws {
        let sut = getSut(captureApplicationLifecycleEvents: false, flushAt: 2)
        let mockNow = MockDate()
        now = { mockNow.date }

        sut.capture("event captured in foreground")

        mockAppLifecycle.simulateAppDidEnterBackground()

        mockNow.date.addTimeInterval(60 * 30 + 1) // Background "timer": 30 mins 1 second

        sut.capture("event captured while in background")

        let events = getBatchedEvents(server)
        try #require(events.count == 2)

        #expect(events[0].properties["$session_id"] as? String != nil)
        #expect(events[1].properties["$session_id"] as? String == nil)

        sut.reset()
        sut.close()
    }

    @Test("reset sessionId after reset")
    func resetSessionIdAfterReset() throws {
        let sut = getSut(captureApplicationLifecycleEvents: false, flushAt: 1)
        let mockNow = MockDate()
        now = { mockNow.date }

        sut.capture("event captured with session")

        var events = getBatchedEvents(server)
        try #require(events.count == 1)

        let currentSessionId = events[0].properties["$session_id"] as? String
        #expect(currentSessionId != nil)

        sut.reset()

        fixture.server.stop()
        fixture.server = nil
        fixture.server = MockPostHogServer()
        fixture.server.start()

        sut.capture("event captured w/o session")

        events = getBatchedEvents(server)
        try #require(events.count == 1)

        let newSessionId = events[0].properties["$session_id"] as? String
        #expect(newSessionId != nil)

        #expect(currentSessionId != newSessionId)

        sut.reset()
        sut.close()
    }

    @Test("reset deletes posthog files but not other folders")
    func resetDeletesPostHogFilesButNotOtherFolders() {
        let appFolder = applicationSupportDirectoryURL()
        // Ensure clean state - previous async operations may have recreated the directory
        deleteSafely(appFolder)

        let sut = getSut()

        sut.reset()
        sut.close()

        #expect(FileManager.default.fileExists(atPath: appFolder.path) == true)
    }

    @Test("reset reloads flags as anon user")
    func resetReloadsFlagsAsAnonUser() {
        let sut = getSut()

        sut.reset()

        waitForFeatureFlagsLoaded(server, sut)
        #expect(sut.isFeatureEnabled("bool-value") == true)

        sut.close()
    }

    @Test("captures an event with a custom timestamp as the equivalent UTC instant")
    func capturesEventWithCustomTimestampAsUTC() throws {
        let sut = getSut()
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(secondsFromGMT: 5 * 60 * 60 + 30 * 60))
        let eventDate = try #require(calendar.date(from: DateComponents(
            year: 2024,
            month: 12,
            day: 17,
            hour: 22,
            minute: 21,
            second: 6,
            nanosecond: 952_000_000
        )))

        sut.capture("test event",
                    properties: ["foo": "bar"],
                    userProperties: ["userProp": "value"],
                    userPropertiesSetOnce: ["userPropOnce": "value"],
                    groups: ["groupProp": "value"],
                    timestamp: eventDate)

        let events = getBatchedEvents(server)
        #expect(events.count == 1)

        let requestBody = try server.parseRequest(#require(server.batchRequests.first))
        let event = (requestBody?["batch"] as? [[String: Any]])?.first

        #expect(event?["event"] as? String == "test event")
        #expect(event?["timestamp"] as? String == "2024-12-17T16:51:06.952Z")

        let properties = event?["properties"] as? [String: Any] ?? [:]
        #expect(properties["foo"] as? String == "bar")

        let set = properties["$set"] as? [String: Any] ?? [:]
        #expect(set["userProp"] as? String == "value")

        let setOnce = properties["$set_once"] as? [String: Any] ?? [:]
        #expect(setOnce["userPropOnce"] as? String == "value")

        let groupProps = properties["$groups"] as? [String: String] ?? [:]
        #expect(groupProps["groupProp"] == "value")

        sut.reset()
        sut.close()
    }

    @Test("captures $feature_flag_called when getFeatureFlag is called")
    func capturesFeatureFlagCalledWhenGetFeatureFlagIsCalled() throws {
        let sut = getSut(
            sendFeatureFlagEvent: true,
            flushAt: 1
        )

        _ = sut.getFeatureFlag("some_key")

        let event = getBatchedEvents(server)
        let first = try #require(event.first)
        #expect(first.event == "$feature_flag_called")
        // v3 responses carry no flag details, so has_experiment is unknown and omitted
        #expect(first.properties["$feature_flag_has_experiment"] == nil)
    }

    @Test("does not capture $feature_flag_called when getFeatureFlag is called twice")
    func doesNotCaptureFeatureFlagCalledTwice() throws {
        let sut = getSut(
            sendFeatureFlagEvent: true,
            flushAt: 2
        )

        _ = sut.getFeatureFlag("some_key")
        _ = sut.getFeatureFlag("some_key")
        sut.capture("force_batch_flush")

        let event = getBatchedEvents(server)
        try #require(event.count == 2)
        #expect(event[0].event == "$feature_flag_called")
        #expect(event[1].event == "force_batch_flush")
    }

    @Test("does not capture $feature_flag_called again when getFeatureFlag called twice after reloading flags")
    func doesNotCaptureFeatureFlagCalledAgainAfterReload() throws {
        let sut = getSut(
            sendFeatureFlagEvent: true,
            flushAt: 2
        )

        _ = sut.getFeatureFlag("some_key")

        let reloaded = XCTestExpectation(description: "second flag lookup completed")
        sut.reloadFeatureFlags { _ in
            _ = sut.getFeatureFlag("some_key")
            reloaded.fulfill()
        }
        #expect(XCTWaiter.wait(for: [reloaded], timeout: testRequestTimeout) == .completed)
        sut.capture("force_batch_flush")

        let event = getBatchedEvents(server)
        try #require(event.count == 2)
        #expect(event[0].event == "$feature_flag_called")
        #expect(event[1].event == "force_batch_flush")
    }

    @Test("captures $feature_flag_called again when getFeatureFlag returns different value after reloading flags")
    func capturesFeatureFlagCalledAgainWhenValueChangesAfterReload() throws {
        let sut = getSut(
            sendFeatureFlagEvent: true,
            flushAt: 3
        )

        // First call gets a false value
        _ = sut.getFeatureFlag("disabled-flag")

        // Change the mock server to return a different value for the same key
        server.disabledFlag = true

        sut.reloadFeatureFlags { _ in
            // Second call gets a true value
            _ = sut.getFeatureFlag("disabled-flag")
            sut.capture("force_batch_flush")
        }

        waitFlagsRequest(server)

        let events = getBatchedEvents(server)
        try #require(events.count == 3)

        #expect(events[0].event == "$feature_flag_called")
        #expect(events[1].event == "$feature_flag_called")
        #expect(events[2].event == "force_batch_flush")
    }
}

// MARK: - beforeSend hook

/// Per-test environment for the "beforeSend hook" suites: the shared fixture plus the suite-level
/// `sut`, which is reset and closed before the fixture tears down (inner teardown runs before the shared one).
private final class BeforeSendScope {
    let env = SDKTestFixture()
    var sut: PostHogSDK!

    var server: MockPostHogServer {
        env.server
    }

    deinit {
        sut?.reset()
        sut?.close()
    }
}

extension PostHogSDKTests {
    static let beforeSendEventTriggers: [BeforeSendTestEventContext] = [
        .init(
            triggerClosure: { $0.capture("test_event") },
            targetKey: "test_event",
            testName: "capture"
        ),
        .init(
            triggerClosure: { $0.screen("screen_name") },
            targetKey: "$screen",
            testName: "screen"
        ),
        .init(
            triggerClosure: { $0.autocapture(eventType: "test_type", elementsChain: "chain", properties: [:]) },
            targetKey: "$autocapture",
            testName: "autocapture"
        ),
        .init(
            triggerClosure: { $0.identify("user_id") },
            targetKey: "$identify",
            testName: "identify"
        ),
        .init(
            triggerClosure: { $0.group(type: "test_type", key: "test_key") },
            targetKey: "$groupidentify",
            testName: "group"
        ),
        .init(
            triggerClosure: { $0.alias("test_alias") },
            targetKey: "$create_alias",
            testName: "alias"
        ),
        .init(
            triggerClosure: { _ = $0.getFeatureFlag("key") },
            targetKey: "$feature_flag_called",
            testName: "get feature flag"
        ),
    ]

    static let beforeSendOtherEventKey = "other_event"

    @Suite("beforeSend hook")
    final class BeforeSendHook {
        private let scope = BeforeSendScope()

        @Suite("returns nil")
        final class ReturnsNil {
            private let scope = BeforeSendScope()

            private func makeSut(_ eventTrigger: BeforeSendTestEventContext) -> PostHogSDK {
                scope.sut = scope.env.getSut(
                    sendFeatureFlagEvent: true,
                    flushAt: 100,
                    beforeSend: [{
                        $0.event == eventTrigger.targetKey ? nil : $0
                    }]
                )
                return scope.sut
            }

            @Test("skips the event", arguments: PostHogSDKTests.beforeSendEventTriggers)
            func skipsTheEvent(eventTrigger: BeforeSendTestEventContext) {
                let sut = makeSut(eventTrigger)
                sut.capture(PostHogSDKTests.beforeSendOtherEventKey)
                eventTrigger.triggerClosure(sut)
                sut.flush()

                let events = getBatchedEvents(scope.server)
                let eventNames = events.map(\.event)

                #expect(events.count == 1)
                #expect(!eventNames.contains(eventTrigger.targetKey))
            }

            @Test("preserves other events", arguments: PostHogSDKTests.beforeSendEventTriggers)
            func preservesOtherEvents(eventTrigger: BeforeSendTestEventContext) throws {
                let sut = makeSut(eventTrigger)
                sut.capture(PostHogSDKTests.beforeSendOtherEventKey)
                eventTrigger.triggerClosure(sut)
                sut.flush()

                let event = getBatchedEvents(scope.server)

                try #require(event.count == 1)
                #expect(event[0].event == PostHogSDKTests.beforeSendOtherEventKey)
            }
        }

        @Suite("event is updated")
        final class EventIsUpdated {
            private let scope = BeforeSendScope()
            private let testUpdatedEventKey = "updated_event"

            private func makeSut(_ eventTrigger: BeforeSendTestEventContext) -> PostHogSDK {
                let testUpdatedEventKey = testUpdatedEventKey
                scope.sut = scope.env.getSut(
                    sendFeatureFlagEvent: true,
                    flushAt: 2,
                    beforeSend: [{
                        if $0.event == eventTrigger.targetKey {
                            $0.event = testUpdatedEventKey
                        }

                        return $0
                    }]
                )
                return scope.sut
            }

            @Test("updates the event", arguments: PostHogSDKTests.beforeSendEventTriggers)
            func updatesTheEvent(eventTrigger: BeforeSendTestEventContext) {
                let sut = makeSut(eventTrigger)
                sut.capture(PostHogSDKTests.beforeSendOtherEventKey)
                eventTrigger.triggerClosure(sut)

                let events = getBatchedEvents(scope.server)
                let eventNames = events.map(\.event)

                #expect(events.count == 2)
                #expect(eventNames.contains(testUpdatedEventKey))
            }

            @Test("preserves all events", arguments: PostHogSDKTests.beforeSendEventTriggers)
            func preservesAllEvents(eventTrigger: BeforeSendTestEventContext) throws {
                let sut = makeSut(eventTrigger)
                sut.capture(PostHogSDKTests.beforeSendOtherEventKey)
                eventTrigger.triggerClosure(sut)

                let event = getBatchedEvents(scope.server)

                try #require(event.count == 2)
                #expect(event[0].event == PostHogSDKTests.beforeSendOtherEventKey)
            }
        }

        @Suite("default hook")
        final class DefaultHook {
            private let scope = BeforeSendScope()

            @Test("keeps the events intact", arguments: PostHogSDKTests.beforeSendEventTriggers)
            func keepsTheEventsIntact(eventTrigger: BeforeSendTestEventContext) throws {
                scope.sut = scope.env.getSut(
                    sendFeatureFlagEvent: true,
                    flushAt: 2
                )
                let sut: PostHogSDK = scope.sut
                sut.capture(PostHogSDKTests.beforeSendOtherEventKey)
                eventTrigger.triggerClosure(sut)

                let events = getBatchedEvents(scope.server)
                let eventNames = events.map(\.event)

                try #require(events.count == 2)
                #expect(eventNames[0] == PostHogSDKTests.beforeSendOtherEventKey)
                #expect(eventNames[1] == eventTrigger.targetKey)
            }
        }

        @Test("skip updated to $session event")
        func skipUpdatedToSessionEvent() throws {
            let testKey = "test_key"
            scope.sut = scope.env.getSut(
                sendFeatureFlagEvent: true,
                flushAt: 1,
                beforeSend: [{
                    if $0.event == testKey {
                        $0.event = "$snapshot"
                    }
                    return $0
                }]
            )
            let sut: PostHogSDK = scope.sut

            sut.capture(testKey)
            sut.capture("other_test")

            let events = getBatchedEvents(scope.server)
            try #require(events.count == 1)
            #expect(events[0].event == "other_test")
        }

        @Test("runs boxed Objective-C callbacks through the exception boundary")
        func runsBoxedObjCCallbacksThroughExceptionBoundary() throws {
            scope.sut = scope.env.getSut(flushAt: 1)
            let sut: PostHogSDK = scope.sut
            let boxes: [NSObject] = [
                BoxedBeforeSendBlock { event in
                    event.event = "boxed_modified_event"
                    return event
                },
            ]
            PHBeforeSendExceptionTestFixture.setBeforeSend(boxes, on: sut.config)

            sut.capture("original_event")

            let events = getBatchedEvents(scope.server)
            try #require(events.count == 1)
            #expect(events[0].event == "boxed_modified_event")
        }

        @Test("contains Objective-C exceptions from boxed callbacks")
        func containsObjCExceptionsFromBoxedCallbacks() throws {
            scope.sut = scope.env.getSut(flushAt: 1)
            let sut: PostHogSDK = scope.sut
            var laterCallbackInvoked = false
            let throwingBox = PHBeforeSendExceptionTestFixture.makeThrowingBox(BoxedBeforeSendBlock.self)
            let boxes: [NSObject] = [
                throwingBox,
                BoxedBeforeSendBlock { event in
                    laterCallbackInvoked = true
                    return event
                },
            ]
            PHBeforeSendExceptionTestFixture.setBeforeSend(boxes, on: sut.config)

            let returnedNormally = PHBeforeSendExceptionTestFixture.invokeWithoutException {
                sut.capture("objc_exception_event")
            }
            sut.flush()

            let storage = try #require(sut.storage, "Expected analytics storage to be configured")
            let persistedQueue = PostHogFileBackedQueue(queue: storage.url(forKey: .queue))
            #expect(returnedNormally)
            #expect(!laterCallbackInvoked)
            #expect(persistedQueue.depth == 0)
            #expect(scope.server.batchRequests.isEmpty)
        }

        @Suite("array edge cases")
        final class ArrayEdgeCases {
            private let scope = BeforeSendScope()

            @Test("properly handles empty beforeSend array")
            func properlyHandlesEmptyBeforeSendArray() {
                scope.sut = scope.env.getSut(
                    sendFeatureFlagEvent: true,
                    flushAt: 2,
                    beforeSend: []
                )
                let sut: PostHogSDK = scope.sut

                let expectedEvents = [
                    "first_event",
                    "second_event",
                ]

                for event in expectedEvents {
                    sut.capture(event)
                }

                let events = getBatchedEvents(scope.server)
                #expect(events.count == expectedEvents.count)
                #expect(events.map(\.event) == expectedEvents)
            }

            @Test("supports trailing closure syntax for single block")
            func supportsTrailingClosureSyntaxForSingleBlock() throws {
                let sut = scope.env.getSut(
                    sendFeatureFlagEvent: true,
                    flushAt: 1
                )

                sut.config.setBeforeSend { $0.event == "first_event" ? nil : $0 }

                sut.capture("first_event")
                sut.capture("second_event")

                let events = getBatchedEvents(scope.server)
                try #require(events.count == 1)
                #expect(events[0].event == "second_event")
            }

            @Test("supports multiple beforeSend blocks")
            func supportsMultipleBeforeSendBlocks() {
                let sut = scope.env.getSut(
                    sendFeatureFlagEvent: true,
                    flushAt: 2,
                    beforeSend: [
                        { $0.event == "first_event" ? nil : $0 },
                        { $0.event = "modified_event"
                            return $0 },
                        { $0.event == "second_event" ? nil : $0 },
                    ]
                )

                sut.capture("first_event")
                sut.capture("second_event")
                sut.capture("third_event")

                // first event is skipped by the first block
                // second event is modified by the second block and not skipped by the third block(because it became "modified_event")
                // third event is modified by the second block
                let expectedEvents = [
                    "modified_event",
                    "modified_event",
                ]

                let events = getBatchedEvents(scope.server)
                #expect(events.count == expectedEvents.count)
                #expect(events.map(\.event) == expectedEvents)
            }
        }
    }
}

// MARK: - automatic person properties

extension PostHogSDKTests {
    @Suite("automatic person properties")
    final class AutomaticPersonProperties {
        private let fixture = SDKTestFixture()

        @Test("sets default person properties on SDK setup when enabled")
        func setsDefaultPersonPropertiesWhenEnabled() throws {
            _ = fixture.getSut(preloadFeatureFlags: true)

            let requests = getFlagsRequest(fixture.server)
            #expect(requests.count > 0)

            let lastRequest = try #require(requests.last, "No flags request found")

            let personProperties = try #require(
                lastRequest["person_properties"] as? [String: Any],
                "Person properties not found in request"
            )

            // Verify expected default properties are set
            // $app_version/$app_build come from the host process's Info.plist (see hostAppInfoHas).
            #expect((personProperties["$app_version"] != nil) == hostAppInfoHas("CFBundleShortVersionString"))
            #expect((personProperties["$app_build"] != nil) == hostAppInfoHas("CFBundleVersion"))
            #expect(personProperties["$app_namespace"] != nil)
            #expect(personProperties["$os_name"] != nil)
            #expect(personProperties["$os_version"] != nil)
            #expect(personProperties["$device_type"] != nil)
            #expect(personProperties["$lib"] != nil)
            #expect(personProperties["$lib_version"] != nil)
        }

        @Test("does not set default person properties when disabled")
        func doesNotSetDefaultPersonPropertiesWhenDisabled() throws {
            let sut = fixture.getSut(setDefaultPersonProperties: false)

            // Manually trigger a flag request since no automatic one will happen
            sut.reloadFeatureFlags()

            let requests = getFlagsRequest(fixture.server)
            #expect(requests.count > 0)

            let lastRequest = try #require(requests.last, "No flags request found")

            // person_properties should be nil when default properties are disabled
            #expect(lastRequest["person_properties"] == nil)
        }
    }
}

// MARK: - autocapture

#if os(iOS)
    extension PostHogSDKTests {
        @Suite("autocapture")
        final class Autocapture {
            private let fixture = SDKTestFixture()

            @Test("isAutocaptureActive() should be false if disabled by config")
            func isAutocaptureActiveFalseWhenDisabledByConfig() {
                let config = PostHogConfig(projectToken: testProjectToken)
                config.captureElementInteractions = false
                let sut = PostHogSDK.with(config)
                defer { sut.close() }

                #expect(!sut.isAutocaptureActive())
            }

            @Test("isAutocaptureActive() should be false if SDK is not enabled")
            func isAutocaptureActiveFalseWhenSDKNotEnabled() {
                let config = PostHogConfig(projectToken: testProjectToken)
                config.captureElementInteractions = true
                let sut = PostHogSDK.with(config)
                sut.close()
                #expect(!sut.isAutocaptureActive())
            }
        }
    }
#endif

struct BeforeSendTestEventContext {
    let triggerClosure: (PostHogSDK) -> Void
    let targetKey: String
    let testName: String
}

// Parameterized-test argument: shown by its trigger name ("capture", "screen", ...) in test output.
// The closures only run on the serialized test that receives them, so the unchecked conformance is safe.
extension BeforeSendTestEventContext: @unchecked Sendable, CustomTestStringConvertible {
    var testDescription: String {
        testName
    }
}
