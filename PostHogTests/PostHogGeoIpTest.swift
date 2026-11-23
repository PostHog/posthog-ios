import Foundation
@testable import PostHog
import Testing

@Suite("GeoIP Tests", .serialized)
class PostHogGeoIpTests {
    let server: MockPostHogServer

    init() {
        server = MockPostHogServer(version: 4)
        server.start()
    }

    deinit {
        server.stop()
    }

    func getSut(disableGeoIp: Bool = false, flushAt: Int = 1) -> PostHogSDK {
        // A token per test keeps its storage and requests apart from other suites' SDK instances
        let config = PostHogConfig(projectToken: "geoip_\(UUID().uuidString)", host: "http://localhost:9001")
        config.flushAt = flushAt
        config.captureApplicationLifecycleEvents = false
        config.disableReachabilityForTesting = true
        config.disableQueueTimerForTesting = true
        config.disableGeoIp = disableGeoIp

        server.batchProjectToken = config.projectToken
        server.flagsProjectToken = config.projectToken

        return PostHogSDK.with(config)
    }

    @Test("disableGeoIp defaults to false")
    func disableGeoIpDefaultsToFalse() {
        let config = PostHogConfig(projectToken: testProjectToken)
        #expect(config.disableGeoIp == false)
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

    @Test("captured events have $geoip_disable when disableGeoIp is enabled")
    func eventsHaveGeoipDisableWhenEnabled() {
        let sut = getSut(disableGeoIp: true)

        sut.capture("test event")

        let events = getBatchedEvents(server)
        #expect(events.count == 1)
        #expect(events.first?.properties["$geoip_disable"] as? Bool == true)

        sut.reset()
        sut.close()
    }

    @Test("registered and caller $geoip_disable values override disableGeoIp")
    func registeredAndCallerOverrideGeoipDisable() {
        // flushAt 2 so both events share one batch
        let sut = getSut(disableGeoIp: true, flushAt: 2)

        sut.register(["$geoip_disable": false])
        sut.capture("registered")
        sut.capture("caller", properties: ["$geoip_disable": true])

        let events = getBatchedEvents(server)
        #expect(events.first { $0.event == "registered" }?.properties["$geoip_disable"] as? Bool == false)
        #expect(events.first { $0.event == "caller" }?.properties["$geoip_disable"] as? Bool == true)

        sut.reset()
        sut.close()
    }

    @Test("flags requests send geoip_disable false by default")
    func flagsRequestsSendGeoipDisableFalseByDefault() async throws {
        let sut = getSut()

        await withCheckedContinuation { continuation in
            sut.reloadFeatureFlags { _ in
                continuation.resume()
            }
        }

        let request = try #require(server.flagsRequests.last)
        let body = try #require(server.parseRequest(request, gzip: false))
        #expect(body["geoip_disable"] as? Bool == false)

        sut.reset()
        sut.close()
    }

    @Test("flags requests have geoip_disable when disableGeoIp is enabled")
    func flagsRequestsHaveGeoipDisableWhenEnabled() async throws {
        let sut = getSut(disableGeoIp: true)

        await withCheckedContinuation { continuation in
            sut.reloadFeatureFlags { _ in
                continuation.resume()
            }
        }

        let request = try #require(server.flagsRequests.last)
        let body = try #require(server.parseRequest(request, gzip: false))
        #expect(body["geoip_disable"] as? Bool == true)

        sut.reset()
        sut.close()
    }
}
