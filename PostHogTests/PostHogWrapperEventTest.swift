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

    private func makeSDK(beforeSend: BeforeSendBlock? = nil) -> PostHogSDK {
        let config = PostHogConfig(projectToken: "phc_wrapper_\(UUID().uuidString)", host: "http://localhost:9001")
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
        #expect(server.parsePostHogEvents(request).map(\.uuid) == [built.uuid])
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
        #endif
    #endif
}
