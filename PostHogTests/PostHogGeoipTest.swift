import Foundation
@testable import PostHog
import Testing

@Suite("GeoIP Tests")
class PostHogGeoipTests {
    @Test("disableGeoip defaults to false")
    func disableGeoipDefaultsToFalse() {
        let config = PostHogConfig(projectToken: testProjectToken)
        #expect(config.disableGeoip == false)
    }
}
