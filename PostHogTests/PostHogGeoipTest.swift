import Foundation
@testable import PostHog
import Testing

@Suite("GeoIP Tests", .serialized)
class PostHogGeoipTests {
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

    func getSut(disableGeoip: Bool = false) -> PostHogSDK {
        let config = PostHogConfig(projectToken: testProjectToken, host: "http://localhost:9001")
        config.flushAt = 1
        config.captureApplicationLifecycleEvents = false
        config.disableReachabilityForTesting = true
        config.disableQueueTimerForTesting = true
        config.disableGeoip = disableGeoip

        let storage = PostHogStorage(config)
        storage.reset()

        return PostHogSDK.with(config)
    }

    @Test("disableGeoip defaults to false")
    func disableGeoipDefaultsToFalse() {
        let config = PostHogConfig(projectToken: testProjectToken)
        #expect(config.disableGeoip == false)
    }

    @Test("captured events have no $geoip_disable by default")
    func eventsHaveNoGeoipDisableByDefault() {
        let sut = getSut()

        sut.capture("test event")

        let events = getBatchedEvents(server)
        #expect(events.count == 1)
        #expect(events.first?.properties["$geoip_disable"] == nil)

        sut.reset()
        sut.close()
    }

    @Test("captured events have $geoip_disable when disableGeoip is enabled")
    func eventsHaveGeoipDisableWhenEnabled() {
        let sut = getSut(disableGeoip: true)

        sut.capture("test event")

        let events = getBatchedEvents(server)
        #expect(events.count == 1)
        #expect(events.first?.properties["$geoip_disable"] as? Bool == true)

        sut.reset()
        sut.close()
    }
}
