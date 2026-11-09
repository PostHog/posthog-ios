//
//  PostHogWrapperEventTest.swift
//  PostHogTests
//

import Foundation
@_spi(PostHogInternal) @testable import PostHog
import Testing

@Suite("Wrapper build and send", .serialized, .resetsGlobalState)
final class PostHogWrapperEventTest {
    private let server: MockPostHogServer

    init() {
        deleteSafely(applicationSupportDirectoryURL())
        server = MockPostHogServer()
        server.start(batchCount: 0)
    }

    deinit {
        server.stop()
    }

    private func makeSDK(beforeSend: BeforeSendBlock? = nil, reuseAnonymousId: Bool = false) -> PostHogSDK {
        let config = PostHogConfig(projectToken: "phc_wrapper_\(UUID().uuidString)", host: "http://localhost:9001")
        config.reuseAnonymousId = reuseAnonymousId
        config.flushAt = 1
        config.preloadFeatureFlags = false
        config.sendFeatureFlagEvent = false
        config.disableReachabilityForTesting = true
        config.disableQueueTimerForTesting = true
        config.disableFlushOnBackgroundForTesting = true
        config.captureApplicationLifecycleEvents = false
        if let beforeSend {
            config.setBeforeSend(beforeSend)
        }
        server.batchProjectToken = config.projectToken
        return PostHogSDK.with(config)
    }

    private func build(_ sut: PostHogSDK, _ event: String = "test", properties: [String: Any]? = nil, ai: Bool = false) -> PostHogEvent? {
        sut.buildEventForWrapper(event: event, distinctId: nil, properties: properties, userProperties: ["plan": "pro"],
                                 userPropertiesSetOnce: nil, groups: nil, options: ["cookieless_mode": true], ai: ai)
    }

    @Test("build returns the filled event without running beforeSend or queueing it")
    func buildFillsWithoutSending() async throws {
        var hookCalls = 0
        let sut = makeSDK { event in
            hookCalls += 1
            return event
        }
        defer { sut.close() }
        sut.register(["registered": "yes"])

        let built = try #require(build(sut, "built", properties: ["call": 1]))

        #expect(built.properties["registered"] as? String == "yes")
        #expect(built.properties["call"] as? Int == 1)
        #expect(built.properties["$set"] as? [String: String] == ["plan": "pro"])
        #expect(built.properties["$session_id"] != nil)
        #expect(built.properties["$lib"] != nil)
        #expect(built.options["cookieless_mode"] as? Bool == true)
        #expect(built.distinctId == sut.getDistinctId())
        #expect(hookCalls == 0)

        server.reset(batchCount: 1)
        sut.capture("other")
        #expect(try await getServerEvents(server).map(\.event) == ["other"])
    }

    @Test("send runs beforeSend, adds no properties, and keeps the uuid and timestamp")
    func sendKeepsBuiltEvent() async throws {
        var hookCalls = 0
        let sut = makeSDK { event in
            hookCalls += 1
            event.properties["native"] = true
            return event
        }
        defer { sut.close() }
        sut.register(["registered": "yes"])
        let built = try #require(build(sut))
        built.properties.removeValue(forKey: "registered")
        built.properties["wrapper"] = true

        server.reset(batchCount: 1)
        let uuid = sut.sendBuiltEventForWrapper(built, ai: false)
        let sent = try #require(try await getServerEvents(server).first)

        #expect(hookCalls == 1)
        #expect(uuid == built.uuid.postHogUuidString)
        #expect(sent.uuid == built.uuid)
        #expect(toISO8601String(sent.timestamp) == toISO8601String(built.timestamp))
        #expect(sent.properties["registered"] == nil)
        #expect(sent.properties["wrapper"] as? Bool == true)
        #expect(sent.properties["native"] as? Bool == true)
    }

    @Test("an AI event is sent on the AI lane")
    func sendsAiOnAiLane() async throws {
        let sut = makeSDK()
        defer { sut.close() }
        let built = try #require(build(sut, "$ai_generation", ai: true))

        sut.sendBuiltEventForWrapper(built, ai: true)
        await waitUntil { self.server.aiRequests.count == 1 }

        let request = try #require(server.aiRequests.first)
        let sent = server.parsePostHogEvents(request)
        #expect(sent.map(\.uuid) == [built.uuid])
        #expect(sent.first?.properties["$sdk_debug_session_start"] != nil)
        #expect(server.batchRequests.isEmpty)
    }

    @Test("build and send return nil when the SDK is opted out")
    func optedOutReturnsNil() throws {
        let sut = makeSDK()
        defer { sut.close() }
        let built = try #require(build(sut))

        sut.optOut()

        #expect(build(sut) == nil)
        #expect(build(sut, "$screen", properties: ["$screen_name": "Home"]) == nil)
        #expect(sut.sendBuiltEventForWrapper(built, ai: false) == nil)
    }

    @Test("send returns nil when native beforeSend drops the event")
    func nativeDropReturnsNil() throws {
        let sut = makeSDK { _ in nil }
        defer { sut.close() }

        #expect(try sut.sendBuiltEventForWrapper(#require(build(sut)), ai: false) == nil)
    }

    @Test("a sent $screen event becomes the current screen; a built one doesn't")
    func screenRecordedAtSend() async throws {
        let sut = makeSDK()
        defer { sut.close() }

        let screen = try #require(build(sut, "$screen", properties: ["$screen_name": "Home", "tab": 1]))
        #expect(screen.properties["$screen_name"] as? String == "Home")
        #expect(screen.properties["tab"] as? Int == 1)
        #expect(build(sut)?.properties["$screen_name"] == nil)

        sut.sendBuiltEventForWrapper(screen, ai: false)

        #expect(build(sut)?.properties["$screen_name"] as? String == "Home")
    }

    @Test("a $screen the wrapper renames isn't recorded as a screen")
    func renamedScreenNotRecorded() async throws {
        let sut = makeSDK()
        defer { sut.close() }
        let screen = try #require(build(sut, "$screen", properties: ["$screen_name": "Home"]))
        screen.event = "custom"

        sut.sendBuiltEventForWrapper(screen, ai: false)

        #expect(build(sut)?.properties["$screen_name"] == nil)
    }

    @Test("an event built under another name and sent as $screen isn't recorded as a screen")
    func eventRenamedToScreenNotRecorded() throws {
        let sut = makeSDK()
        defer { sut.close() }
        let built = try #require(build(sut, "$captured_screen", properties: ["$screen_name": "Home"]))
        built.event = "$screen"

        #expect(sut.sendBuiltEventForWrapper(built, ai: false) != nil)

        #expect(build(sut)?.properties["$screen_name"] == nil)
    }

    @Test("a $screen sent after reset doesn't restore its screen name")
    func screenNotRestoredAfterReset() throws {
        let sut = makeSDK()
        defer { sut.close() }
        let screen = try #require(build(sut, "$screen", properties: ["$screen_name": "Home"]))

        sut.reset()
        #expect(sut.sendBuiltEventForWrapper(screen, ai: false) != nil)

        #expect(build(sut)?.properties["$screen_name"] == nil)
    }

    @Test("a $screen build without a $screen_name returns nil", arguments: [nil, "", "  "] as [String?])
    func screenNeedsName(name: String?) {
        let sut = makeSDK()
        defer { sut.close() }

        #expect(build(sut, "$screen", properties: name.map { ["$screen_name": $0] }) == nil)
    }

    @Test("an event is sent once, on the lane given at send")
    func sendsOnceOnSendLane() async throws {
        let sut = makeSDK()
        defer { sut.close() }
        let built = try #require(build(sut, "$ai_generation", ai: true))

        let uuid = sut.sendBuiltEventForWrapper(built, ai: false)
        await waitUntil { self.server.batchRequests.count == 1 }

        #expect(uuid == built.uuid.postHogUuidString)
        #expect(sut.sendBuiltEventForWrapper(built, ai: true) == nil)
        #expect(server.aiRequests.isEmpty)
    }

    @Test("feature flags get the person properties the wrapper left on the sent event")
    func flagsUseSentPersonProperties() throws {
        let sut = makeSDK()
        defer { sut.close() }
        let built = try #require(build(sut))
        built.properties["$set"] = ["kept": "yes"]

        sut.sendBuiltEventForWrapper(built, ai: false)

        let flagProperties = try #require(sut.remoteConfig).getPersonPropertiesForFlags()
        #expect(flagProperties["kept"] as? String == "yes")
        #expect(flagProperties["plan"] == nil)
    }

    @Test("an event sent after reset doesn't give its person properties to the new user's flags")
    func flagsSkipPersonPropertiesAfterReset() throws {
        let sut = makeSDK()
        defer { sut.close() }
        let built = try #require(build(sut))

        sut.reset()
        sut.sendBuiltEventForWrapper(built, ai: false)

        #expect(try #require(sut.remoteConfig).getPersonPropertiesForFlags()["plan"] == nil)
    }

    @Test("a reset that keeps the distinct ID still counts as a new identity at send")
    func resetKeepingDistinctIdIsNewIdentity() throws {
        let sut = makeSDK(reuseAnonymousId: true)
        defer { sut.close() }
        let built = try #require(build(sut))
        let distinctId = sut.getDistinctId()

        sut.reset()
        #expect(sut.getDistinctId() == distinctId)
        sut.sendBuiltEventForWrapper(built, ai: false)

        #expect(try #require(sut.remoteConfig).getPersonPropertiesForFlags()["plan"] == nil)
        #expect(sut.config.storageManager?.isPersonProcessing() == false)
    }

    @Test("an event sent for another distinct ID leaves the current user's person state alone")
    func anotherDistinctIdKeepsPersonState() async throws {
        let sut = makeSDK()
        defer { sut.close() }
        let built = try #require(build(sut))
        built.distinctId = "other-user"

        server.reset(batchCount: 1)
        sut.sendBuiltEventForWrapper(built, ai: false)

        let sent = try #require(try await getServerEvents(server).first)
        #expect(sent.distinctId == "other-user")
        #expect(sent.properties["$set"] as? [String: String] == ["plan": "pro"])
        #expect(try #require(sut.remoteConfig).getPersonPropertiesForFlags()["plan"] == nil)
        #expect(sut.config.storageManager?.isPersonProcessing() == false)
    }

    @Test("a build turns on person processing only when it's sent")
    func personProcessingDeferredToSend() throws {
        let sut = makeSDK()
        defer { sut.close() }
        let built = try #require(build(sut))

        #expect(sut.config.storageManager?.isPersonProcessing() == false)
        #expect(built.options["process_person_profile"] == nil)

        sut.sendBuiltEventForWrapper(built, ai: false)

        #expect(sut.config.storageManager?.isPersonProcessing() == true)
    }

    @Test("registered options are sent on every event, under the event's own options")
    func registeredOptionsUnderEventOptions() async throws {
        let sut = makeSDK()
        defer { sut.close() }
        sut.registerOptionsForWrapper(["cookieless_mode": false, "disable_skew_correction": true])

        server.reset(batchCount: 2)
        sut.capture("plain")
        sut.capture("own", options: ["cookieless_mode": true])
        let sent = try await getServerEvents(server)

        #expect(sent.map(\.event) == ["plain", "own"])
        #expect(sent[0].options["cookieless_mode"] as? Bool == false)
        #expect(sent[0].options["disable_skew_correction"] as? Bool == true)
        #expect(sent[1].options["cookieless_mode"] as? Bool == true)
        #expect(sent[1].options["disable_skew_correction"] as? Bool == true)
    }

    @Test("a wrapper build carries the registered options, so the wrapper's beforeSend sees them")
    func buildCarriesRegisteredOptions() throws {
        let sut = makeSDK()
        defer { sut.close() }
        sut.registerOptionsForWrapper(["disable_skew_correction": true, "cookieless_mode": false])

        let built = try #require(build(sut))

        #expect(built.options["disable_skew_correction"] as? Bool == true)
        #expect(built.options["cookieless_mode"] as? Bool == true)
    }

    @Test("a registered process_person_profile replaces the SDK's personless default")
    func registeredPersonProcessingOption() async throws {
        let sut = makeSDK()
        defer { sut.close() }
        sut.registerOptionsForWrapper(["process_person_profile": true])

        server.reset(batchCount: 1)
        sut.capture("anonymous")
        let sent = try #require(try await getServerEvents(server).first)

        #expect(sent.options["process_person_profile"] as? Bool == true)
    }

    @Test("unregister and reset remove registered options")
    func unregisterAndResetRemoveOptions() throws {
        let sut = makeSDK()
        defer { sut.close() }
        sut.registerOptionsForWrapper(["cookieless_mode": true, "disable_skew_correction": true])

        sut.unregisterOptionsForWrapper("cookieless_mode")
        let afterUnregister = try #require(sut.buildEventForWrapper(event: "e", distinctId: nil, properties: nil, userProperties: nil,
                                                                    userPropertiesSetOnce: nil, groups: nil, options: nil, ai: false))
        #expect(afterUnregister.options["cookieless_mode"] == nil)
        #expect(afterUnregister.options["disable_skew_correction"] as? Bool == true)

        sut.reset()
        let afterReset = try #require(sut.buildEventForWrapper(event: "e", distinctId: nil, properties: nil, userProperties: nil,
                                                               userPropertiesSetOnce: nil, groups: nil, options: nil, ai: false))
        #expect(afterReset.options["disable_skew_correction"] == nil)
    }

    @Test("registered options persist across setups")
    func registeredOptionsPersist() throws {
        let config = PostHogConfig(projectToken: "phc_wrapper_persist_\(UUID().uuidString)", host: "http://localhost:9001")
        config.disableReachabilityForTesting = true
        config.disableQueueTimerForTesting = true
        config.preloadFeatureFlags = false
        config.captureApplicationLifecycleEvents = false
        let first = PostHogSDK.with(config)
        first.registerOptionsForWrapper(["cookieless_mode": true])
        first.close()

        let second = PostHogSDK.with(config)
        defer { second.close() }
        let built = try #require(second.buildEventForWrapper(event: "e", distinctId: nil, properties: nil, userProperties: nil,
                                                             userPropertiesSetOnce: nil, groups: nil, options: nil, ai: false))
        #expect(built.options["cookieless_mode"] as? Bool == true)
    }

    @Test("an event built before close and setup isn't sent through the new setup")
    func sendAfterReconfigureDrops() throws {
        let sut = makeSDK()
        defer { sut.close() }
        let built = try #require(build(sut))

        sut.close()
        let config = PostHogConfig(projectToken: "phc_wrapper_\(UUID().uuidString)", host: "http://localhost:9001")
        config.disableReachabilityForTesting = true
        config.disableQueueTimerForTesting = true
        sut.setup(config)

        #expect(sut.sendBuiltEventForWrapper(built, ai: false) == nil)
    }

    @Test("a setup replaced during send doesn't receive the event")
    func reconfigureDuringSendKeepsBuildSetupQueue() throws {
        let replacement = PostHogConfig(projectToken: "phc_wrapper_\(UUID().uuidString)", host: "http://localhost:9001")
        replacement.disableReachabilityForTesting = true
        replacement.disableQueueTimerForTesting = true
        var sut: PostHogSDK!
        sut = makeSDK { event in
            sut.close()
            sut.setup(replacement)
            event.event = "$snapshot"
            event.properties["$session_id"] = "session"
            return event
        }
        defer { sut.close() }
        let built = try #require(build(sut))

        sut.sendBuiltEventForWrapper(built, ai: false)

        #expect(try #require(sut.replayQueue).depth == 0)
    }

    @Test("a capture built before close() and setup() isn't queued on the new setup", arguments: [false, true])
    func reconfigureDuringCaptureDropsEvent(aiLane: Bool) throws {
        let replacement = PostHogConfig(projectToken: "phc_wrapper_\(UUID().uuidString)", host: "http://localhost:9001")
        replacement.disableReachabilityForTesting = true
        replacement.disableQueueTimerForTesting = true
        let sut = makeSDK()
        defer { sut.close() }
        var reconfigured = false
        sut.onCapturePreparedForTesting = {
            sut.onCapturePreparedForTesting = nil
            sut.close()
            sut.setup(replacement)
            reconfigured = true
        }

        let uuid = sut.captureInternal(aiLane ? "$ai_generation" : "event", aiLane: aiLane)

        #expect(reconfigured)
        #expect(uuid == nil)
        #expect(try #require(sut.replayQueue).depth == 0)
        #expect(try #require(sut.aiQueue).depth == 0)
    }

    @Test("a screen built before close() and setup() isn't queued on the new setup")
    func reconfigureDuringScreenDropsEvent() {
        let replacement = PostHogConfig(projectToken: "phc_wrapper_\(UUID().uuidString)", host: "http://localhost:9001")
        replacement.disableReachabilityForTesting = true
        replacement.disableQueueTimerForTesting = true
        let screenReachedNewSetup = AsyncLatch()
        replacement.setBeforeSend { event in
            if event.event == "$screen" { screenReachedNewSetup.signal() }
            return event
        }
        let sut = makeSDK()
        defer { sut.close() }
        var reconfigured = false
        sut.onCapturePreparedForTesting = {
            sut.onCapturePreparedForTesting = nil
            sut.close()
            sut.setup(replacement)
            reconfigured = true
        }

        sut.screen("Home")

        #expect(reconfigured)
        #expect(!screenReachedNewSetup.isSignaled)
    }

    @Test("a wrapper event built across close() and setup() isn't sent through the new setup")
    func reconfigureDuringWrapperBuildDropsEvent() throws {
        let replacement = PostHogConfig(projectToken: "phc_wrapper_\(UUID().uuidString)", host: "http://localhost:9001")
        replacement.disableReachabilityForTesting = true
        replacement.disableQueueTimerForTesting = true
        let sut = makeSDK()
        defer { sut.close() }
        var reconfigured = false
        sut.onCapturePreparedForTesting = {
            sut.onCapturePreparedForTesting = nil
            sut.close()
            sut.setup(replacement)
            reconfigured = true
        }

        let built = try #require(build(sut))

        #expect(reconfigured)
        #expect(sut.sendBuiltEventForWrapper(built, ai: false) == nil)
    }

    @Test("an event built on one SDK instance isn't sent through another")
    func sendOnOtherInstanceDrops() throws {
        let sut = makeSDK()
        let other = makeSDK()
        defer {
            sut.close()
            other.close()
        }
        let built = try #require(build(sut))

        #expect(other.sendBuiltEventForWrapper(built, ai: false) == nil)
    }

    @Test("an event sent after reset doesn't turn on person processing for the new user")
    func personProcessingSkippedAfterReset() throws {
        let sut = makeSDK()
        defer { sut.close() }
        let built = try #require(build(sut))

        sut.reset()
        sut.sendBuiltEventForWrapper(built, ai: false)

        #expect(sut.config.storageManager?.isPersonProcessing() == false)
    }

    @Test("the replay debug values sent are the ones from build, even if the session changed")
    func replayDebugSnapshotAtBuild() throws {
        let sut = makeSDK()
        defer { sut.close() }
        let built = try #require(build(sut, "$wrapped"))
        let builtStart = try #require(sut.sessionManager.sessionStartTimestampSnapshot)

        sut.endSession()
        server.reset(batchCount: 1)
        sut.sendBuiltEventForWrapper(built, ai: false)
        let sent = try #require(getBatchedEvents(server).first)

        #expect(sent.properties["$sdk_debug_session_start"] as? Int64 == Int64(builtStart * 1000))
    }

    #if os(iOS)
        #if !SWIFT_PACKAGE || SessionReplay
            @Test("the replay debug bundle is claimed when a wrapper event is sent, not when it's built")
            func wrapperClaimsReplayDebugBundleAtSend() throws {
                let sut = makeSDK()
                defer { sut.close() }
                let built = try #require(build(sut, "$wrapped"))
                #expect(built.properties["$sdk_debug_replay_capture_mode"] == nil)

                server.reset(batchCount: 1)
                sut.sendBuiltEventForWrapper(built, ai: false)
                let sent = try #require(getBatchedEvents(server).first)

                #expect(sent.properties["$sdk_debug_replay_capture_mode"] != nil)
            }

            @Test("a wrapper event renamed by the hook keeps the replay debug eligibility of its built name")
            func wrapperReplayEligibilityFromBuiltName() throws {
                let sut = makeSDK()
                defer { sut.close() }
                let built = try #require(build(sut, "$wrapped"))
                built.event = "renamed"

                server.reset(batchCount: 1)
                sut.sendBuiltEventForWrapper(built, ai: false)
                let sent = try #require(getBatchedEvents(server).first)

                #expect(sent.properties["$sdk_debug_replay_capture_mode"] != nil)
            }

            @Test("send doesn't add back a required replay property the wrapper removed")
            func wrapperRemovalOfRequiredReplayPropertyKept() throws {
                let sut = makeSDK()
                defer { sut.close() }
                let built = try #require(build(sut, "$wrapped"))
                #expect(built.properties["$recording_status"] != nil)
                built.properties.removeValue(forKey: "$recording_status")

                server.reset(batchCount: 1)
                sut.sendBuiltEventForWrapper(built, ai: false)
                let sent = try #require(getBatchedEvents(server).first)

                #expect(sent.properties["$recording_status"] == nil)
            }
        #endif
    #endif
}
