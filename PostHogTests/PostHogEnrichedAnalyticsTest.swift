import Foundation
import Nimble
@testable import PostHog
import Quick

class PostHogEnrichedAnalyticsTest: QuickSpec {
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

    override func spec() {
        var server: MockPostHogServer!

        func deleteDefaults() {
            let userDefaults = UserDefaults.standard
            userDefaults.removeObject(forKey: "PHGVersionKey")
            userDefaults.removeObject(forKey: "PHGBuildKeyV2")
            userDefaults.synchronize()

            deleteSafely(applicationSupportDirectoryURL())
        }

        beforeEach {
            deleteDefaults()
            server = MockPostHogServer(version: 4)
            server.start()
        }
        afterEach {
            server.stop()
            server = nil
        }

        it("captures $feature_view event") {
            let sut = self.getSut()

            sut.captureFeatureView("test-flag")

            let events = getBatchedEvents(server)
            expect(events.count) == 1

            let event = events.first!
            expect(event.event) == "$feature_view"
            expect(event.properties["feature_flag"] as? String) == "test-flag"

            sut.reset()
            sut.close()
        }

        it("captures $feature_interaction event") {
            let sut = self.getSut()

            sut.captureFeatureInteraction("test-flag")

            let events = getBatchedEvents(server)
            expect(events.count) == 1

            let event = events.first!
            expect(event.event) == "$feature_interaction"
            expect(event.properties["feature_flag"] as? String) == "test-flag"

            let setProps = event.properties["$set"] as? [String: Any]
            expect(setProps?["$feature_interaction/test-flag"] as? Bool) == true

            sut.reset()
            sut.close()
        }

        it("does not capture feature view if opt out") {
            let sut = self.getSut(optOut: true)

            sut.captureFeatureView("test-flag")

            let events = getBatchedEvents(server, timeout: 1.0, failIfNotCompleted: false)
            expect(events.count) == 0

            sut.reset()
            sut.close()
        }

        it("does not capture feature interaction if opt out") {
            let sut = self.getSut(optOut: true)

            sut.captureFeatureInteraction("test-flag")

            let events = getBatchedEvents(server, timeout: 1.0, failIfNotCompleted: false)
            expect(events.count) == 0

            sut.reset()
            sut.close()
        }

        it("does not capture feature view if disabled") {
            let sut = self.getSut()
            sut.close() // Disable SDK

            sut.captureFeatureView("test-flag")

            let events = getBatchedEvents(server, timeout: 1.0, failIfNotCompleted: false)
            expect(events.count) == 0
        }

        it("does not capture feature interaction if disabled") {
            let sut = self.getSut()
            sut.close() // Disable SDK

            sut.captureFeatureInteraction("test-flag")

            let events = getBatchedEvents(server, timeout: 1.0, failIfNotCompleted: false)
            expect(events.count) == 0
        }
    }
}
