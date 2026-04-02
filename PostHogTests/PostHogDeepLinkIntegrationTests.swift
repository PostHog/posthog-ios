import Foundation
@testable import PostHog
import Testing

@Suite("Deep Link Helper Tests")
struct PostHogDeepLinkHelperTests {
    @Test("builds properties with valid referrer URL")
    func buildPropertiesWithValidReferrerURL() {
        let url = URL(string: "myapp://product/123?utm_source=newsletter")!
        let referrer = "https://www.google.com/path?q=search"

        let props = PostHogDeepLinkHelper.buildDeepLinkProperties(url: url, referrer: referrer)

        #expect(props["url"] as? String == url.absoluteString)
        #expect(props["$referrer"] as? String == referrer)
        #expect(props["$referring_domain"] as? String == "www.google.com")
    }

    @Test("builds properties with non-URL referrer string (bundle ID)")
    func buildPropertiesWithNonURLReferrer() {
        let url = URL(string: "myapp://home")!
        let referrer = "com.example.sourceApp"

        let props = PostHogDeepLinkHelper.buildDeepLinkProperties(url: url, referrer: referrer)

        #expect(props["url"] as? String == url.absoluteString)
        #expect(props["$referrer"] as? String == referrer)
        #expect(props["$referring_domain"] == nil, "$referring_domain should be absent for non-URL referrers")
    }

    @Test("builds properties without referrer")
    func buildPropertiesWithoutReferrer() {
        let url = URL(string: "https://myapp.com/welcome")!

        let props = PostHogDeepLinkHelper.buildDeepLinkProperties(url: url, referrer: nil)

        #expect(props["url"] as? String == url.absoluteString)
        #expect(props["$referrer"] == nil)
        #expect(props["$referring_domain"] == nil)
    }

    @Test("extracts referring domain from universal link referrer")
    func extractsReferringDomainFromUniversalLink() {
        let url = URL(string: "https://myapp.com/article/42")!
        let referrer = "https://news.ycombinator.com/item?id=42"

        let props = PostHogDeepLinkHelper.buildDeepLinkProperties(url: url, referrer: referrer)

        #expect(props["$referring_domain"] as? String == "news.ycombinator.com")
    }

    @Test("handles custom URL scheme")
    func handlesCustomURLScheme() {
        let url = URL(string: "posthog://dashboard/analytics")!

        let props = PostHogDeepLinkHelper.buildDeepLinkProperties(url: url, referrer: nil)

        #expect(props["url"] as? String == "posthog://dashboard/analytics")
    }

    @Test("handles URL with query parameters and fragments")
    func handlesURLWithQueryAndFragment() {
        let url = URL(string: "myapp://page?foo=bar&baz=qux#section")!
        let referrer = "https://example.com"

        let props = PostHogDeepLinkHelper.buildDeepLinkProperties(url: url, referrer: referrer)

        #expect(props["url"] as? String == "myapp://page?foo=bar&baz=qux#section")
        #expect(props["$referrer"] as? String == "https://example.com")
        #expect(props["$referring_domain"] as? String == "example.com")
    }
}
