import XCTest
@testable import PostHog

final class PostHogDeepLinkIntegrationTests: XCTestCase {

    func testBuildDeepLinkProperties_withValidReferrerURL() {
        // Given
        let url = URL(string: "myapp://product/123?utm_source=newsletter")!
        let referrer = "https://www.google.com/path?q=search"

        // When
        let props = PostHogDeepLinkIntegration.buildDeepLinkProperties(url: url, referrer: referrer)

        // Then
        XCTAssertEqual(props["url"] as? String, url.absoluteString)
        XCTAssertEqual(props["$referrer"] as? String, referrer)
        XCTAssertEqual(props["$referring_domain"] as? String, "www.google.com")
    }

    func testBuildDeepLinkProperties_withNonURLReferrerString() {
        // Given
        let url = URL(string: "myapp://home")!
        let referrer = "com.example.sourceApp" // not a URL, should not produce $referring_domain

        // When
        let props = PostHogDeepLinkIntegration.buildDeepLinkProperties(url: url, referrer: referrer)

        // Then
        XCTAssertEqual(props["url"] as? String, url.absoluteString)
        XCTAssertEqual(props["$referrer"] as? String, referrer)
        XCTAssertNil(props["$referring_domain"], "$referring_domain should be absent for non-URL referrers")
    }

    func testBuildDeepLinkProperties_withoutReferrer() {
        // Given
        let url = URL(string: "https://myapp.com/welcome")!

        // When
        let props = PostHogDeepLinkIntegration.buildDeepLinkProperties(url: url, referrer: nil)

        // Then
        XCTAssertEqual(props["url"] as? String, url.absoluteString)
        XCTAssertNil(props["$referrer"])
        XCTAssertNil(props["$referring_domain"])
    }

    func testTrackDeepLink_userActivityBrowsingWeb_usesReferrerURL() {
        // This test validates the helper behavior indirectly for the userActivity flow.
        let url = URL(string: "https://myapp.com/article/42")!
        let referrer = "https://news.ycombinator.com/item?id=42"
        let props = PostHogDeepLinkIntegration.buildDeepLinkProperties(url: url, referrer: referrer)
        XCTAssertEqual(props["$referring_domain"] as? String, "news.ycombinator.com")
    }
}
