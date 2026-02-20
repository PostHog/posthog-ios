import Foundation
@testable import PostHog
import Testing

@Suite("PostHogEnrichedAnalytics Tests", .serialized)
class PostHogEnrichedAnalyticsTest {
    let server: MockPostHogServer

    init() {
        Self.deleteDefaults()
        server = MockPostHogServer(version: 4)
        server.start()
    }

    deinit {
        server.stop()
    }

    private static func deleteDefaults() {
        let userDefaults = UserDefaults.standard
        userDefaults.removeObject(forKey: "PHGVersionKey")
        userDefaults.removeObject(forKey: "PHGBuildKeyV2")
        userDefaults.synchronize()

        deleteSafely(applicationSupportDirectoryURL())
    }

    func getSut(optOut: Bool = false) -> PostHogSDK {
        let config = PostHogConfig(apiKey: testAPIKey, host: "http://localhost:9001")
        config.flushAt = 1
        config.captureApplicationLifecycleEvents = false
        config.disableReachabilityForTesting = true
        config.disableQueueTimerForTesting = true
        config.optOut = optOut

        let storage = PostHogStorage(config)
        storage.reset()

        return PostHogSDK.with(config)
    }

    @Test("captures $feature_view event")
    func capturesFeatureViewEvent() {
        let sut = getSut()

        sut.captureFeatureView(flag: "test-flag", flagVariant: nil)

        let events = getBatchedEvents(server)
        #expect(events.count == 1)

        let event = events.first!
        #expect(event.event == "$feature_view")
        #expect(event.properties["feature_flag"] as? String == "test-flag")
        let setProps = event.properties["$set"] as? [String: Any]
        #expect(setProps?["$feature_view/test-flag"] as? Bool == true)

        sut.reset()
        sut.close()
    }

    @Test("captures $feature_interaction event")
    func capturesFeatureInteractionEvent() {
        let sut = getSut()

        sut.captureFeatureInteraction(flag: "test-flag", flagVariant: nil)

        let events = getBatchedEvents(server)
        #expect(events.count == 1)

        let event = events.first!
        #expect(event.event == "$feature_interaction")
        #expect(event.properties["feature_flag"] as? String == "test-flag")

        let setProps = event.properties["$set"] as? [String: Any]
        #expect(setProps?["$feature_interaction/test-flag"] as? Bool == true)

        sut.reset()
        sut.close()
    }

    @Test("does not capture feature view if opt out")
    func doesNotCaptureFeatureViewIfOptOut() {
        let sut = getSut(optOut: true)

        sut.captureFeatureView(flag: "test-flag", flagVariant: nil)

        let events = getBatchedEvents(server, timeout: 1.0, failIfNotCompleted: false)
        #expect(events.count == 0)

        sut.reset()
        sut.close()
    }

    @Test("does not capture feature interaction if opt out")
    func doesNotCaptureFeatureInteractionIfOptOut() {
        let sut = getSut(optOut: true)

        sut.captureFeatureInteraction(flag: "test-flag", flagVariant: nil)

        let events = getBatchedEvents(server, timeout: 1.0, failIfNotCompleted: false)
        #expect(events.count == 0)

        sut.reset()
        sut.close()
    }

    @Test("does not capture feature view if disabled")
    func doesNotCaptureFeatureViewIfDisabled() {
        let sut = getSut()
        sut.close() // Disable SDK

        sut.captureFeatureView(flag: "test-flag", flagVariant: nil)

        let events = getBatchedEvents(server, timeout: 1.0, failIfNotCompleted: false)
        #expect(events.count == 0)
    }

    @Test("does not capture feature interaction if disabled")
    func doesNotCaptureFeatureInteractionIfDisabled() {
        let sut = getSut()
        sut.close() // Disable SDK

        sut.captureFeatureInteraction(flag: "test-flag", flagVariant: nil)

        let events = getBatchedEvents(server, timeout: 1.0, failIfNotCompleted: false)
        #expect(events.count == 0)
    }
}
